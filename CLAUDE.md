# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Paper Suitecase** — A Flutter desktop (macOS-primary) app for managing academic PDF papers with hierarchical tagging, full-text search, arXiv integration, and BibTeX support.

## Common Commands

```bash
flutter pub get          # Install dependencies
flutter run -d macos     # Run on macOS
flutter build macos      # Build macOS app
flutter analyze          # Run linter
flutter test             # Run tests
flutter clean            # Clean build artifacts
```

### Supabase

```bash
supabase start           # Start local Supabase (Docker)
supabase db push         # Push migrations to remote
supabase functions deploy # Deploy all Edge Functions
supabase secrets set KEY=VAL # Set environment secret
```

## Architecture

### State Management
Single `AppState` class using `provider` with `ChangeNotifier`. All app state (papers, tags, entries, navigation history, UI state, settings) lives in `lib/providers/app_state.dart`. No Riverpod.

### Database
SQLite via `sqflite_common_ffi` (not drift). Schema is manually managed in `lib/database/database_service.dart` with migration versions (currently v6). Key tables: `entries`, `papers`, `tags`, `paper_tags`, `papers_fts` (FTS5 virtual table for full-text search with BM25 ranking). FTS is kept in sync via SQL triggers.

### Services Layer
- `PdfService` — text extraction (via syncfusion), thumbnail generation, file operations
- `ArxivService` — arXiv API queries, metadata parsing
- `EntryScannerService` — scans entry directories for new, removed, and renamed PDFs
- `ManifestService` — manages per-entry `.papersuitecase/` cache directories (thumbnails, extracted text, manifest.json, references.bib). Uses SHA1 file keys and SHA256 content hashes for rename detection.
- `BibtexService` — BibTeX parsing and import

### Models
- `Paper` — core entity with title, authors, abstract, extracted text, arxiv_id, bibtex, entry_id, relative_path
- `Tag` — hierarchical tags with parent_id, paper counts, expansion state
- `Entry` — reference to an external directory; papers always live in entries (symlink-only model)
- `ChatMessage` — LLM chat message model for paper Q&A

### Supabase Backend
Supabase provides auth (email/password + magic link), cloud sync (papers & tags), Edge Functions for LLM chat (`chat-with-paper`) and trending computation (`compute-trending`), and a recommendation engine. Key services: `SupabaseService` (auth/init), `SyncService` (bidirectional sync), `LlmChatService` (paper Q&A), `RecommendationService` (discover tab). User profiles track tier (`free`/`pro`) and monthly LLM usage.

### UI Structure
Single `MainScreen` with sidebar (`TagSidebar` with `EntrySidebarSection` and `TagSidebarSection`), content area (`PaperGrid`), and embedded PDF viewer. Custom macOS-style title bar via `window_manager`. Supports drag-and-drop import via `desktop_drop`.

### Key Patterns
- **Desktop-first**: Custom title bar, macOS-specific paths, window management
- **Local-first**: All data in SQLite, optional cloud sync via Supabase
- **Symlink-only entries**: Entries reference external directories; PDFs are never copied. Each entry has a `.papersuitecase/` cache dir with manifest, thumbnails, and extracted text
- **Auto-scanning**: `EntryScannerService` detects new/removed/renamed PDFs on startup by comparing manifest against filesystem
- **Navigation history**: Back/forward stack tracking tag/folder/search state changes

### Dependencies of Note
- `syncfusion_flutter_pdf` / `syncfusion_flutter_pdfviewer` — PDF text extraction and embedded viewer
- `sqflite_common_ffi` — SQLite for desktop (FFI-based, not mobile sqflite)
- `window_manager` — Custom window chrome
- `desktop_drop` — Drag-and-drop file import
- Dart SDK: `^3.10.1`
