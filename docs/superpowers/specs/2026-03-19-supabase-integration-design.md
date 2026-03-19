# Paper Suitcase — Supabase Integration Design

## Overview

Add Supabase backend to Paper Suitcase for user authentication, metadata sync, collaborative recommendations, and LLM-powered paper understanding chat. The app remains fully functional offline without an account. Cloud features are additive.

## Goals

- Minimal cloud storage: metadata only, no PDFs or extracted text
- Collaborative recommendations based on shared tagging behavior
- LLM chat (MiniMax M2.5) to help users understand papers
- Self-sustaining business model: bootstrap under $100/month, introduce subscriptions when costs grow

## Non-Goals

- Cloud storage of PDFs or full extracted text
- Syncing folder/entry organization (entries are a local concept tied to file paths)
- Real-time collaboration or shared libraries (future consideration)
- Mobile or web client (desktop-only for now)

---

## Section 1: Authentication & User Model

### Auth Provider
Supabase Auth with three login methods:
- Email/password
- Google OAuth
- GitHub OAuth

### User Profile Table
Extends Supabase `auth.users`:

```sql
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro')),
  llm_calls_this_month INTEGER NOT NULL DEFAULT 0,
  llm_calls_reset_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Key Decisions
- App remains fully functional offline without login. No account required for core paper management.
- Supabase session persisted locally via `supabase_flutter` built-in persistence.
- "Continue offline" option prominent on login screen.

---

## Section 2: Database Schema & Sync Strategy

### Supabase Tables

**Per-user metadata (synced from local SQLite):**

```sql
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
  synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, sync_key)
);

CREATE TABLE user_tags (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  parent_id BIGINT REFERENCES user_tags(id) ON DELETE SET NULL,
  UNIQUE(user_id, name, parent_id)
);

CREATE TABLE user_paper_tags (
  user_paper_id BIGINT NOT NULL REFERENCES user_papers(id) ON DELETE CASCADE,
  user_tag_id BIGINT NOT NULL REFERENCES user_tags(id) ON DELETE CASCADE,
  PRIMARY KEY (user_paper_id, user_tag_id)
);
```

**Shared catalog (deduplicated across users, for recommendations):**

```sql
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

CREATE TABLE catalog_tags (
  id BIGSERIAL PRIMARY KEY,
  catalog_id BIGINT NOT NULL REFERENCES shared_catalog(id) ON DELETE CASCADE,
  tag_name TEXT NOT NULL,
  usage_count INTEGER NOT NULL DEFAULT 1,
  UNIQUE(catalog_id, tag_name)
);

CREATE TABLE trending_scores (
  id BIGSERIAL PRIMARY KEY,
  catalog_id BIGINT NOT NULL REFERENCES shared_catalog(id) ON DELETE CASCADE,
  score FLOAT NOT NULL DEFAULT 0,
  computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for recommendation queries
CREATE INDEX idx_user_papers_user ON user_papers(user_id);
CREATE INDEX idx_user_papers_arxiv ON user_papers(arxiv_id);
CREATE INDEX idx_user_papers_sync_key ON user_papers(user_id, sync_key);
CREATE INDEX idx_shared_catalog_arxiv ON shared_catalog(arxiv_id);
CREATE INDEX idx_shared_catalog_title_hash ON shared_catalog(title_hash);
CREATE INDEX idx_catalog_tags_catalog ON catalog_tags(catalog_id);
CREATE INDEX idx_trending_scores_score ON trending_scores(score DESC);
```

### Sync Strategy

**Principles:**
1. **Local SQLite is source of truth.** App works identically without an account.
2. **No full text or PDFs** ever leave the device.
3. **Sync is local-to-cloud only** (unidirectional push). No cloud-to-local sync in v1. Future multi-device support would require bidirectional sync.

**Sync identity (`sync_key`):**
Each paper needs a stable, non-null identity for cloud dedup. The `sync_key` is computed locally as:
- `arxiv:{arxiv_id}` if arxiv_id is present
- `hash:{content_hash}` if content_hash is present
- `title:{sha256(lowercase(title + authors))}` as fallback
This is stored in a new local SQLite column `papers.sync_key` (added via migration).

**Local schema additions (SQLite migration v6):**
```sql
ALTER TABLE papers ADD COLUMN sync_key TEXT;
ALTER TABLE papers ADD COLUMN remote_id BIGINT;
ALTER TABLE papers ADD COLUMN updated_at TEXT;
ALTER TABLE papers ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;
ALTER TABLE tags ADD COLUMN remote_id BIGINT;
ALTER TABLE tags ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1;
```
- `sync_key`: stable dedup key for cloud upsert
- `remote_id`: corresponding Supabase row ID after sync
- `updated_at`: timestamp for conflict resolution (set on every local edit)
- `dirty`: 1 = needs sync, 0 = in sync. Set to 1 on any local change.

**Sync flow (on login / periodic / manual trigger):**
1. Query local papers where `dirty = 1`.
2. Batch upsert to `user_papers` (keyed on `user_id + sync_key`), sending title, authors, abstract, bibtex, arxiv_id, updated_at.
3. On success, store returned `remote_id` locally and set `dirty = 0`.
4. For papers with arxiv_id: upsert into `shared_catalog` via server-side RPC (increments `reader_count`).
5. Sync tags: topological sort (parents before children), upsert to `user_tags`, store `remote_id`.
6. Sync paper-tag associations using the resolved remote IDs.

**Tag hierarchy sync:**
Tags are synced parent-first via topological sort. If a parent tag doesn't have a `remote_id` yet, it is synced first. Tag identity is `(user_id, name, parent_remote_id)`.

**First-time bulk sync:**
On first login with an existing library, sync in batches of 50 papers with a progress indicator. Estimated time for 500 papers: ~5-10 seconds.

**Conflict resolution:**
Last-write-wins using `updated_at` timestamp. Since v1 is local-to-cloud only (single device), conflicts are unlikely. The `updated_at` field prepares for future multi-device support.

**Deletes:**
Local-to-cloud only. When a user deletes a paper locally, set a `deleted_at` timestamp (soft delete) and sync to cloud on next push. A periodic cleanup job hard-deletes soft-deleted records older than 30 days. Cloud deletions do not propagate back to local in v1.

**Shared catalog scope:**
The shared catalog supports three dedup keys: `arxiv_id`, `doi`, and `title_hash` (sha256 of normalized title+authors). Papers matching any key are merged. This extends recommendations beyond arXiv-only papers, though collaborative filtering works best when papers have stable identifiers (arxiv_id or doi). Papers with only title_hash matching may have false positives and are weighted lower in recommendations.

### Row-Level Security (RLS)

All tables have RLS enabled. Policies:

```sql
-- profiles: users can read/update only their own profile
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_select ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY profiles_update ON profiles FOR UPDATE USING (auth.uid() = id);

-- user_papers: users can CRUD only their own papers
ALTER TABLE user_papers ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_papers_select ON user_papers FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_papers_insert ON user_papers FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_papers_update ON user_papers FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY user_papers_delete ON user_papers FOR DELETE USING (auth.uid() = user_id);

-- user_tags: users can CRUD only their own tags
ALTER TABLE user_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_tags_select ON user_tags FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_tags_insert ON user_tags FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_tags_update ON user_tags FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY user_tags_delete ON user_tags FOR DELETE USING (auth.uid() = user_id);

-- user_paper_tags: access via join ownership check
ALTER TABLE user_paper_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_paper_tags_select ON user_paper_tags FOR SELECT
  USING (EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid()));
CREATE POLICY user_paper_tags_insert ON user_paper_tags FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid()));
CREATE POLICY user_paper_tags_delete ON user_paper_tags FOR DELETE
  USING (EXISTS (SELECT 1 FROM user_papers WHERE id = user_paper_id AND user_id = auth.uid()));

-- shared_catalog: all authenticated users can read, no direct writes (server-side RPC only)
ALTER TABLE shared_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY shared_catalog_select ON shared_catalog FOR SELECT USING (auth.role() = 'authenticated');

-- catalog_tags: all authenticated users can read, no direct writes
ALTER TABLE catalog_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalog_tags_select ON catalog_tags FOR SELECT USING (auth.role() = 'authenticated');

-- trending_scores: all authenticated users can read
ALTER TABLE trending_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY trending_scores_select ON trending_scores FOR SELECT USING (auth.role() = 'authenticated');
```

Shared catalog writes happen exclusively through Postgres RPC functions executed with `SECURITY DEFINER` (bypasses RLS, runs as the function owner). This ensures dedup logic is centralized.

### Storage Estimate

~50-100 KB per user for a 500-paper library. At 100 users: ~5-10 MB total.

---

## Section 3: Recommendation Engine

### Scope Limitation

Collaborative filtering (Type 1) and trending (Type 3) work best for papers with stable identifiers (arxiv_id or doi). Papers matched only by title_hash are weighted lower due to potential false positives. For fields with low arXiv/DOI coverage (medicine, humanities), tag-based suggestions (Type 2) will be the primary recommendation source. This is acceptable for v1 — the target audience is CS/ML/physics researchers who use arXiv heavily.

### Type 1: Collaborative Filtering ("Users like you also read")

- Find users sharing 3+ `arxiv_id`s with the current user.
- Surface papers they have that the current user doesn't.
- Implemented as a Postgres RPC function. No Edge Function needed.
- Privacy: users never see who shares their taste, only recommended papers.

### Type 2: Tag-Based Suggestions ("Based on your interests")

- Cross-reference user's tags against `catalog_tags`.
- Find papers with similar tag patterns that the user hasn't read.
- Weighted by `usage_count` — higher community usage ranks higher.
- Simple SQL join via Postgres RPC.

### Type 3: Trending ("Popular in your areas")

- Filter `shared_catalog` by tag overlap with user's tags.
- Sort by `reader_count` growth over last 30 days.
- A daily Edge Function cron computes trending scores into a `trending_scores` table.

### Delivery

- Flutter calls Supabase RPC on app launch / manual refresh button.
- Results cached locally for offline access.
- "Discover" tab in UI shows recommendations grouped by type.

---

## Section 4: LLM Chat (Paper Understanding)

### Architecture

- Supabase Edge Function `chat-with-paper` proxies to MiniMax M2.5 API.
- Edge Function holds the MiniMax API key server-side.
- Rate limiting enforced server-side via `profiles.llm_calls_this_month`.

### Flow

1. User opens a paper, clicks "Chat about this paper."
2. Flutter sends to Edge Function: `{ paper_title, authors, abstract, bibtex, user_question, conversation_history }`.
3. Edge Function checks rate limit first: if `llm_calls_this_month >= tier_limit`, return 429 immediately.
4. Edge Function increments `llm_calls_this_month` **before** calling MiniMax (pessimistic counting — prevents abuse via rapid requests; if MiniMax fails, user loses one credit but this is rare and preferable to allowing unlimited retries).
5. Edge Function builds system prompt with paper context.
6. Proxies to MiniMax M2.5, streams response back to Flutter.

**Conversation history limit:** maximum 10 previous turns (5 user + 5 assistant messages) sent to MiniMax. Older messages are truncated from the front. This keeps token usage predictable at ~4K tokens max for history.

### What Gets Sent to MiniMax

Metadata only: title, authors, abstract, bibtex, user question, and conversation history. No extracted text or PDFs.

### Key Decisions

- **No extracted text sent** — keeps payloads small, avoids sending potentially copyrighted full text.
- **Conversation history stored locally only** (SQLite), not in Supabase.
- **Streaming** response for good UX.
- **Monthly reset:** scheduled Postgres cron resets `llm_calls_this_month` on the 1st.

### Rate Limits

| Tier | Calls/month |
|---|---|
| Free | 30 |
| Pro | 300 |

---

## Section 5: Business Model & Subscription

### Phase 1 — Bootstrap (0-100 users, ~$30/mo)

- Free for all users (30 LLM calls/month, full sync & recommendations).
- Owner covers costs.
- No payment infrastructure.

### Phase 2 — Introduce Pro Tier (costs approach $100/mo)

- Trigger: ~300-500 active users or LLM costs exceeding $70/mo.
- Free: 30 LLM calls/month, basic recommendations.
- Pro ($3-5/month): 300 LLM calls, priority recommendations.
- Payment: Stripe via Edge Function webhook, updates `profiles.tier`.

### Phase 3 — Self-Sustaining

- At 500 users with 10% Pro conversion at $5/mo = $250/mo revenue.
- Costs: Supabase Pro ($25) + MiniMax (~$25) = ~$50/mo.

### Principles

- Core app (paper management, local search, tagging) is free forever, no account needed.
- Cloud features (sync, recommendations, LLM chat) are the premium layer.
- Supabase upgrade path: Free → Pro ($25/mo) immediately for production. Team ($599/mo) only if SOC2/SSO needed (unlikely).

---

## Section 6: Flutter Integration Architecture

### New Packages

- `supabase_flutter` — auth, database, edge function calls.

### Service Layer

New services alongside existing ones (no changes to existing services):

```
lib/services/
  ├── supabase_service.dart       — init, auth, session management
  ├── sync_service.dart           — local↔cloud metadata sync
  ├── recommendation_service.dart — fetch recommendations via RPC
  ├── llm_chat_service.dart       — proxy chat via Edge Function
```

### AppState Changes

- Auth state: user, session, logged-in flag.
- Sync state: last synced, syncing indicator.
- Recommendations list.
- Chat messages for current paper.
- All behind null checks — everything works when logged out.

### UI Additions

- Login/signup screen (email, Google, GitHub + "Continue offline").
- Settings: account section (login status, tier, usage stats).
- "Discover" tab for recommendations.
- Chat panel in paper detail view.
- Sync indicator in status bar.

### Offline Behavior

- No account: app works exactly as today.
- Logged in but offline: local SQLite is truth, sync queues changes for next connection.
- Network errors: silent retry with exponential backoff, never blocks UI.

---

## Supabase Cost Summary

| Item | Monthly Cost |
|---|---|
| Supabase Pro | $25 |
| MiniMax M2.5 (100 users) | ~$2-5 |
| MiniMax M2.5 (500 users) | ~$15-25 |
| **Total (100 users)** | **~$30** |
| **Total (500 users)** | **~$50** |

Comfortable within $100/mo budget. Pro subscriptions cover growth beyond that.
