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

## Architecture

### State Management
Single `AppState` class using `provider` with `ChangeNotifier`. All app state (papers, tags, folders, navigation history, UI state, settings) lives in `lib/providers/app_state.dart`. No Riverpod.

### Database
SQLite via `sqflite_common_ffi` (not drift). Schema is manually managed in `lib/database/database_service.dart` with migration versions (currently v4). Key tables: `papers`, `tags`, `paper_tags`, `folders`, `papers_fts` (FTS5 virtual table for full-text search with BM25 ranking). FTS is kept in sync via SQL triggers.

### Services Layer
- `PdfService` — text extraction (via syncfusion), thumbnail generation, file operations
- `ArxivService` — arXiv API queries, metadata parsing
- `FolderImportService` — recursive folder scanning with hierarchy preservation
- `BibtexService` — BibTeX parsing and import
- `ReferenceService` — reference metadata management

### Models
- `Paper` — core entity with title, authors, abstract, extracted text, arxiv_id, bibtex, folder_id
- `Tag` — hierarchical tags with parent_id, paper counts, expansion state
- `PaperFolder` — folder model supporting both database-managed and symbolic (linked) external folders
- `ImportData` — multi-stage import workflow structures (PendingImport, FolderScanResult, ArxivMetadata)

### UI Structure
Single `MainScreen` with sidebar (`TagSidebar`), content area (`PaperGrid`), and embedded PDF viewer. Custom macOS-style title bar via `window_manager`. Supports drag-and-drop import via `desktop_drop`.

### Key Patterns
- **Desktop-first**: Custom title bar, macOS-specific paths, window management
- **Local-first**: All data in SQLite, no cloud sync
- **Symbolic folders**: Can reference external folder paths without copying files into the database
- **Navigation history**: Back/forward stack tracking tag/folder/search state changes
- **Multi-stage import**: Folder scan → user selection → confirmation → import with progress tracking

### Dependencies of Note
- `syncfusion_flutter_pdf` / `syncfusion_flutter_pdfviewer` — PDF text extraction and embedded viewer
- `sqflite_common_ffi` — SQLite for desktop (FFI-based, not mobile sqflite)
- `window_manager` — Custom window chrome
- `desktop_drop` — Drag-and-drop file import
- Dart SDK: `^3.10.1`
