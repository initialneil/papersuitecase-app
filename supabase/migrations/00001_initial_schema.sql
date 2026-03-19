-- ============================================================
-- PROFILES (extends auth.users)
-- ============================================================
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro')),
  llm_calls_this_month INTEGER NOT NULL DEFAULT 0,
  llm_calls_reset_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- USER PAPERS (per-user metadata synced from local)
-- ============================================================
CREATE TABLE user_papers (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  arxiv_id TEXT,
  title TEXT NOT NULL,
  authors TEXT,
  abstract TEXT,
  bibtex TEXT,
  sync_key TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, sync_key)
);

-- ============================================================
-- USER TAGS (per-user tag hierarchy)
-- ============================================================
CREATE TABLE user_tags (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  parent_id BIGINT REFERENCES user_tags(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, name, parent_id)
);

-- ============================================================
-- USER PAPER TAGS (junction)
-- ============================================================
CREATE TABLE user_paper_tags (
  user_paper_id BIGINT NOT NULL REFERENCES user_papers(id) ON DELETE CASCADE,
  user_tag_id BIGINT NOT NULL REFERENCES user_tags(id) ON DELETE CASCADE,
  PRIMARY KEY (user_paper_id, user_tag_id)
);

-- ============================================================
-- SHARED CATALOG (deduplicated across users)
-- ============================================================
CREATE TABLE shared_catalog (
  id BIGSERIAL PRIMARY KEY,
  arxiv_id TEXT UNIQUE,
  doi TEXT UNIQUE,
  title_hash TEXT,
  title TEXT NOT NULL,
  authors TEXT,
  abstract TEXT,
  reader_count INTEGER NOT NULL DEFAULT 1,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (arxiv_id IS NOT NULL OR doi IS NOT NULL OR title_hash IS NOT NULL)
);

-- ============================================================
-- CATALOG TAGS (aggregated tag associations)
-- ============================================================
CREATE TABLE catalog_tags (
  id BIGSERIAL PRIMARY KEY,
  catalog_id BIGINT NOT NULL REFERENCES shared_catalog(id) ON DELETE CASCADE,
  tag_name TEXT NOT NULL,
  usage_count INTEGER NOT NULL DEFAULT 1,
  UNIQUE(catalog_id, tag_name)
);

-- ============================================================
-- TRENDING SCORES (computed daily)
-- ============================================================
CREATE TABLE trending_scores (
  id BIGSERIAL PRIMARY KEY,
  catalog_id BIGINT NOT NULL REFERENCES shared_catalog(id) ON DELETE CASCADE,
  score FLOAT NOT NULL DEFAULT 0,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_user_papers_user ON user_papers(user_id);
CREATE INDEX idx_user_papers_arxiv ON user_papers(arxiv_id);
CREATE INDEX idx_user_papers_sync_key ON user_papers(user_id, sync_key);
CREATE INDEX idx_shared_catalog_arxiv ON shared_catalog(arxiv_id);
CREATE INDEX idx_shared_catalog_title_hash ON shared_catalog(title_hash);
CREATE INDEX idx_catalog_tags_catalog ON catalog_tags(catalog_id);
CREATE INDEX idx_trending_scores_score ON trending_scores(score DESC);

-- ============================================================
-- ROW-LEVEL SECURITY
-- ============================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_select ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY profiles_update ON profiles FOR UPDATE USING (auth.uid() = id);

ALTER TABLE user_papers ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_papers_select ON user_papers FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_papers_insert ON user_papers FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_papers_update ON user_papers FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY user_papers_delete ON user_papers FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE user_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_tags_select ON user_tags FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_tags_insert ON user_tags FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_tags_update ON user_tags FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY user_tags_delete ON user_tags FOR DELETE USING (auth.uid() = user_id);

ALTER TABLE user_paper_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_paper_tags_select ON user_paper_tags FOR SELECT
  USING (EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid()));
CREATE POLICY user_paper_tags_insert ON user_paper_tags FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid())
    AND EXISTS (SELECT 1 FROM user_tags WHERE id = user_tag_id AND user_id = auth.uid())
  );
CREATE POLICY user_paper_tags_delete ON user_paper_tags FOR DELETE
  USING (EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid()));

ALTER TABLE shared_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY shared_catalog_select ON shared_catalog FOR SELECT USING (auth.role() = 'authenticated');

ALTER TABLE catalog_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_tags_select ON catalog_tags FOR SELECT USING (auth.role() = 'authenticated');

ALTER TABLE trending_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY trending_scores_select ON trending_scores FOR SELECT USING (auth.role() = 'authenticated');

-- ============================================================
-- RPC: Upsert to shared catalog (SECURITY DEFINER)
-- ============================================================
CREATE OR REPLACE FUNCTION upsert_shared_catalog(
  p_arxiv_id TEXT DEFAULT NULL,
  p_doi TEXT DEFAULT NULL,
  p_title_hash TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_authors TEXT DEFAULT NULL,
  p_abstract TEXT DEFAULT NULL,
  p_tag_names TEXT[] DEFAULT '{}'
)
RETURNS BIGINT AS $$
DECLARE
  v_catalog_id BIGINT;
  v_tag TEXT;
BEGIN
  SELECT id INTO v_catalog_id FROM shared_catalog
  WHERE (p_arxiv_id IS NOT NULL AND arxiv_id = p_arxiv_id)
     OR (p_doi IS NOT NULL AND doi = p_doi)
     OR (p_title_hash IS NOT NULL AND title_hash = p_title_hash)
  LIMIT 1;

  IF v_catalog_id IS NOT NULL THEN
    UPDATE shared_catalog
    SET reader_count = reader_count + 1,
        last_seen_at = NOW(),
        arxiv_id = COALESCE(shared_catalog.arxiv_id, p_arxiv_id),
        doi = COALESCE(shared_catalog.doi, p_doi),
        title_hash = COALESCE(shared_catalog.title_hash, p_title_hash)
    WHERE id = v_catalog_id;
  ELSE
    INSERT INTO shared_catalog (arxiv_id, doi, title_hash, title, authors, abstract)
    VALUES (p_arxiv_id, p_doi, p_title_hash, p_title, p_authors, p_abstract)
    RETURNING id INTO v_catalog_id;
  END IF;

  FOREACH v_tag IN ARRAY p_tag_names LOOP
    INSERT INTO catalog_tags (catalog_id, tag_name, usage_count)
    VALUES (v_catalog_id, LOWER(TRIM(v_tag)), 1)
    ON CONFLICT (catalog_id, tag_name)
    DO UPDATE SET usage_count = catalog_tags.usage_count + 1;
  END LOOP;

  RETURN v_catalog_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- RPC: Collaborative filtering recommendations
-- ============================================================
CREATE OR REPLACE FUNCTION get_collaborative_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  catalog_id BIGINT,
  arxiv_id TEXT,
  title TEXT,
  authors TEXT,
  abstract TEXT,
  reader_count INT,
  match_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH my_arxiv_ids AS (
    SELECT up.arxiv_id
    FROM user_papers up
    WHERE up.user_id = p_user_id AND up.arxiv_id IS NOT NULL AND up.deleted_at IS NULL
  ),
  similar_users AS (
    SELECT up2.user_id, COUNT(*) AS shared_count
    FROM user_papers up2
    JOIN my_arxiv_ids mai ON up2.arxiv_id = mai.arxiv_id
    WHERE up2.user_id != p_user_id AND up2.deleted_at IS NULL
    GROUP BY up2.user_id
    HAVING COUNT(*) >= 3
  ),
  their_papers AS (
    SELECT up3.arxiv_id, SUM(su.shared_count) AS match_score
    FROM user_papers up3
    JOIN similar_users su ON up3.user_id = su.user_id
    WHERE up3.arxiv_id IS NOT NULL
      AND up3.deleted_at IS NULL
      AND up3.arxiv_id NOT IN (SELECT mai2.arxiv_id FROM my_arxiv_ids mai2)
    GROUP BY up3.arxiv_id
  )
  SELECT sc.id, sc.arxiv_id, sc.title, sc.authors, sc.abstract, sc.reader_count, tp.match_score
  FROM their_papers tp
  JOIN shared_catalog sc ON sc.arxiv_id = tp.arxiv_id
  ORDER BY tp.match_score DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- RPC: Tag-based recommendations
-- ============================================================
CREATE OR REPLACE FUNCTION get_tag_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  catalog_id BIGINT,
  arxiv_id TEXT,
  title TEXT,
  authors TEXT,
  abstract TEXT,
  reader_count INT,
  tag_relevance BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH my_tags AS (
    SELECT LOWER(TRIM(ut.name)) AS tag_name
    FROM user_tags ut
    WHERE ut.user_id = p_user_id
  ),
  my_sync_keys AS (
    SELECT up.sync_key
    FROM user_papers up
    WHERE up.user_id = p_user_id AND up.deleted_at IS NULL
  ),
  relevant_catalog AS (
    SELECT ct.catalog_id, SUM(ct.usage_count) AS tag_relevance
    FROM catalog_tags ct
    JOIN my_tags mt ON ct.tag_name = mt.tag_name
    GROUP BY ct.catalog_id
  )
  SELECT sc.id, sc.arxiv_id, sc.title, sc.authors, sc.abstract, sc.reader_count, rc.tag_relevance
  FROM relevant_catalog rc
  JOIN shared_catalog sc ON sc.id = rc.catalog_id
  WHERE NOT EXISTS (
    SELECT 1 FROM my_sync_keys msk
    WHERE msk.sync_key = 'arxiv:' || sc.arxiv_id
       OR msk.sync_key = 'hash:' || sc.title_hash
  )
  ORDER BY rc.tag_relevance DESC, sc.reader_count DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- RPC: Trending recommendations
-- ============================================================
CREATE OR REPLACE FUNCTION get_trending_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  catalog_id BIGINT,
  arxiv_id TEXT,
  title TEXT,
  authors TEXT,
  abstract TEXT,
  reader_count INT,
  trending_score FLOAT
) AS $$
BEGIN
  RETURN QUERY
  WITH my_tags AS (
    SELECT LOWER(TRIM(ut.name)) AS tag_name
    FROM user_tags ut
    WHERE ut.user_id = p_user_id
  ),
  my_sync_keys AS (
    SELECT up.sync_key
    FROM user_papers up
    WHERE up.user_id = p_user_id AND up.deleted_at IS NULL
  )
  SELECT sc.id, sc.arxiv_id, sc.title, sc.authors, sc.abstract, sc.reader_count, ts.score
  FROM trending_scores ts
  JOIN shared_catalog sc ON sc.id = ts.catalog_id
  WHERE EXISTS (
    SELECT 1 FROM catalog_tags ct
    JOIN my_tags mt ON ct.tag_name = mt.tag_name
    WHERE ct.catalog_id = sc.id
  )
  AND NOT EXISTS (
    SELECT 1 FROM my_sync_keys msk
    WHERE msk.sync_key = 'arxiv:' || sc.arxiv_id
       OR msk.sync_key = 'hash:' || sc.title_hash
  )
  ORDER BY ts.score DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
