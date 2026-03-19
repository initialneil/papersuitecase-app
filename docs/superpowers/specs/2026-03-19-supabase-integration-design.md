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
  content_hash TEXT,
  synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, content_hash)
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
  arxiv_id TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  authors TEXT,
  abstract TEXT,
  reader_count INTEGER NOT NULL DEFAULT 1,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE catalog_tags (
  id BIGSERIAL PRIMARY KEY,
  catalog_id BIGINT NOT NULL REFERENCES shared_catalog(id) ON DELETE CASCADE,
  tag_name TEXT NOT NULL,
  usage_count INTEGER NOT NULL DEFAULT 1,
  UNIQUE(catalog_id, tag_name)
);
```

### Sync Strategy

1. **Local SQLite is source of truth.** App works identically without an account.
2. **On login:** background sync pushes local metadata to `user_papers` and `user_tags`. Uses `content_hash` to detect changes and sync diffs only.
3. **Shared catalog contribution:** when a user syncs a paper with an `arxiv_id`, upsert into `shared_catalog` and increment `reader_count`. Papers without `arxiv_id` stay private.
4. **Conflict resolution:** last-write-wins on metadata fields. Tags merge (union of local + cloud). Deletes propagate.
5. **No full text or PDFs** ever leave the device.

### Row-Level Security (RLS)

- `user_papers`, `user_tags`, `user_paper_tags`: users read/write only their own rows.
- `shared_catalog`, `catalog_tags`: all authenticated users can read; writes via server-side functions only (controls deduplication).

### Storage Estimate

~50-100 KB per user for a 500-paper library. At 100 users: ~5-10 MB total.

---

## Section 3: Recommendation Engine

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

- Flutter calls Supabase RPC on app launch / pull-to-refresh.
- Results cached locally for offline access.
- "Discover" tab in UI shows recommendations grouped by type.

---

## Section 4: LLM Chat (Paper Understanding)

### Architecture

- Supabase Edge Function `chat-with-paper` proxies to MiniMax M2.5 API.
- Edge Function holds the MiniMax API key server-side.
- Rate limiting enforced server-side via `profiles.llm_calls_this_month`.

### Flow

1. User opens a paper, taps "Chat about this paper."
2. Flutter sends to Edge Function: `{ paper_title, authors, abstract, bibtex, user_question, conversation_history }`.
3. Edge Function builds system prompt with paper context.
4. Proxies to MiniMax M2.5, streams response back to Flutter.
5. Increments `llm_calls_this_month`.

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
