import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../models/settings_enums.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_service.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import '../models/import_data.dart';
import '../models/paper_folder.dart';
import '../services/pdf_service.dart';
import '../services/arxiv_service.dart';
import '../services/folder_import_service.dart';

class _NavigationState {
  final Tag? tag;
  final PaperFolder? folder;
  final String query;

  _NavigationState(this.tag, this.folder, this.query);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _NavigationState &&
          runtimeType == other.runtimeType &&
          tag?.id == other.tag?.id &&
          folder?.id == other.folder?.id &&
          folder?.path == other.folder?.path &&
          query == other.query;

  @override
  int get hashCode => Object.hash(tag?.id, folder?.id, folder?.path, query);
}

/// Main application state provider
class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final PdfService _pdfService = PdfService();
  final ArxivService _arxivService = ArxivService();
  final FolderImportService _folderImportService = FolderImportService();

  // State
  List<Paper> _papers = [];
  List<Tag> _tagTree = [];
  List<PaperFolder> _folders = [];
  List<PaperFolder> _folderTree = [];
  List<Tag> _relatedTags = [];
  Tag? _selectedTag;
  PaperFolder? _selectedFolder;
  List<Tag> _lastActiveTagPath = [];
  String _searchQuery = '';

  // Navigation History
  final List<_NavigationState> _history = [];
  int _historyIndex = -1;
  bool _isNavigatingHistory = false;

  bool _isLoading = false;
  String? _error;
  String? _detectedArxivUrl;
  final Set<int> _selectedPaperIds = {};
  Paper? _viewingPaper;
  int _untaggedCount = 0;
  // Open embedded viewer tabs (MRU order)
  final List<Paper> _openTabs = [];

  // Import State
  bool _isImporting = false;
  String _importStatus = '';
  double _importProgress = 0.0;
  List<Map<String, dynamic>> _importHistory = [];

  // Config State
  bool _isConfigMode = false;
  ThemeMode _themeMode = ThemeMode.system;
  PdfReaderType _pdfReaderType = PdfReaderType.embedded;
  String? _customPdfAppPath;
  List<String> _customPdfApps = [];

  // Getters
  List<Paper> get papers => _papers;
  List<Tag> get tagTree => _tagTree;
  List<PaperFolder> get folders => _folders;
  List<PaperFolder> get folderTree => _folderTree;

  /// Get visible subfolders for the current view
  List<PaperFolder> get visibleSubFolders {
    if (_selectedFolder == null) {
      // Root view: show top-level folders
      return _folderTree;
    }
    // Sub-folder view: show children of selected
    return _selectedFolder!.children;
  }

  List<Tag> get relatedTags => _relatedTags;
  Tag? get selectedTag => _selectedTag;
  PaperFolder? get selectedFolder => _selectedFolder;
  List<Tag> get lastActiveTagPath => _lastActiveTagPath;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get detectedArxivUrl => _detectedArxivUrl;
  Set<int> get selectedPaperIds => _selectedPaperIds;
  bool get isOthersSelected => false; // Removed Others selection logic
  Paper? get viewingPaper => _viewingPaper;
  int get untaggedCount => _untaggedCount;
  List<Paper> get openTabs => List.unmodifiable(_openTabs);

  // Import Getters
  bool get isImporting => _isImporting;
  String get importStatus => _importStatus;
  double get importProgress => _importProgress;
  List<Map<String, dynamic>> get importHistory => _importHistory;

  // Config Getters
  bool get isConfigMode => _isConfigMode;
  ThemeMode get themeMode => _themeMode;
  PdfReaderType get pdfReaderType => _pdfReaderType;
  String? get customPdfAppPath => _customPdfAppPath;
  List<String> get customPdfApps => _customPdfApps;

  // Navigation History Getters
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex < _history.length - 1;

  /// Initialize the app state
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await DatabaseService.initialize();
      await _loadSettings();
      // Push initial state
      _pushHistory();
      await refresh();
    } catch (e) {
      _error = 'Failed to initialize: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  void _pushHistory() {
    if (_isNavigatingHistory) return;

    final newState = _NavigationState(
      _selectedTag,
      _selectedFolder,
      _searchQuery,
    );

    // Don't push duplicates if nothing changed
    if (_historyIndex >= 0 && _history[_historyIndex] == newState) {
      return;
    }

    // Truncate future history if we're not at the end
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    _history.add(newState);
    _historyIndex = _history.length - 1;

    // Notify listeners so UI updates back/forward buttons
    // However, wait until current frame is done potentially?
    // Actually this is usually called before notifyListeners of the action itself.
  }

  Future<void> navigateBack() async {
    if (!canGoBack) return;

    _isNavigatingHistory = true;
    _historyIndex--;
    final state = _history[_historyIndex];

    _selectedTag = state.tag;
    _selectedFolder = state.folder;
    _searchQuery = state.query;

    await _loadPapers();
    _isNavigatingHistory = false;
    notifyListeners();
  }

  Future<void> navigateForward() async {
    if (!canGoForward) return;

    _isNavigatingHistory = true;
    _historyIndex++;
    final state = _history[_historyIndex];

    _selectedTag = state.tag;
    _selectedFolder = state.folder;
    _searchQuery = state.query;

    await _loadPapers();
    _isNavigatingHistory = false;
    notifyListeners();
  }

  /// Refresh all data
  Future<void> refresh() async {
    await Future.wait([_loadPapers(), _loadTagTree(), _loadFolders()]);
    notifyListeners();
  }

  Future<void> _loadPapers() async {
    // Handle search first, then apply tag/folder filtering if needed
    if (_searchQuery.isNotEmpty) {
      _papers = await _db.searchPapers(_searchQuery);
      _relatedTags = await _db.getRelatedTags(_searchQuery);

      // Apply folder filtering to search results if folder is selected
      if (_selectedFolder != null) {
        if (_selectedFolder!.isSymbolic) {
          // For symbolic folders, only show papers whose file path is under the folder's path
          final folderPath = _selectedFolder!.path;
          _papers = _papers.where((paper) {
            return paper.filePath.startsWith(folderPath);
          }).toList();
        } else if (_selectedFolder!.id != null) {
          // For regular folders, filter by folder_id
          final folderId = _selectedFolder!.id!;
          _papers = _papers.where((paper) {
            return paper.folderId == folderId;
          }).toList();
        }
      }
      // Apply tag filtering to search results if tag is selected
      else if (_selectedTag != null) {
        if (_selectedTag!.isOthers) {
          // For "Others" tag, only show untagged papers
          _papers = _papers.where((paper) => paper.tags.isEmpty).toList();
        } else {
          // For regular tags, filter by tag ID
          final tagId = _selectedTag!.id!;
          _papers = _papers.where((paper) {
            return paper.tags.any((tag) => tag.id == tagId);
          }).toList();
        }
      }
    }
    // No search query - load by tag or folder
    else if (_selectedTag != null) {
      if (_selectedTag!.isOthers) {
        _papers = await _db.getUntaggedPapers();
      } else {
        _papers = await _db.getPapersByTag(_selectedTag!.id!);
      }
    } else if (_selectedFolder != null) {
      if (_selectedFolder!.isSymbolic) {
        // For symbolic folders, mix DB papers with on-disk files
        // Handle virtual folders (null ID) - they only exist on disk
        List<Paper> dbPapers = [];
        if (_selectedFolder!.id != null) {
          dbPapers = await _db.getPapersByFolder(_selectedFolder!.id!);
        }

        final diskPapers = await _scanSymbolicFolderPapers(_selectedFolder!);

        // Merge lists, preferring DB papers if paths match
        final dbPaths = dbPapers.map((p) => p.filePath).toSet();
        _papers = [
          ...dbPapers,
          ...diskPapers.where((p) => !dbPaths.contains(p.filePath)),
        ];

        // Sort by name or date? Default to addedAt (file mod time for disk papers)
        _papers.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      } else {
        // Regular folder, must have ID
        if (_selectedFolder!.id != null) {
          _papers = await _db.getPapersByFolder(_selectedFolder!.id!);
        } else {
          _papers = [];
        }
      }
    } else if (_searchQuery.isNotEmpty) {
      _papers = await _db.searchPapers(_searchQuery);
      _relatedTags = await _db.getRelatedTags(_searchQuery);
    } else {
      _papers = await _db.getAllPapers();
      _relatedTags = [];
    }
    _untaggedCount = await _db.getUntaggedPaperCount();
    // Clear selection when loading new papers
    _selectedPaperIds.clear();
  }

  Future<void> _loadTagTree() async {
    _tagTree = await _db.getTagTree();
  }

  Future<void> _loadFolders() async {
    final allFolders = await _db.getAllFolders();

    // Fetch all papers to compute counts and previews
    // This assumes all papers are loaded. For large libraries, efficient DB queries are better.
    final allPapers = await _db.getAllPapers();

    // Group papers by folder
    final papersByFolder = <int, List<Paper>>{};
    for (final paper in allPapers) {
      if (paper.folderId != null) {
        papersByFolder.putIfAbsent(paper.folderId!, () => []).add(paper);
      }
    }

    // Populate counts and previews
    for (final folder in allFolders) {
      if (folder.isSymbolic) {
        try {
          // Symbolic folder: scan disk for count and preview
          // We limit the scan if possible, but _scanSymbolicFolderPapers scans all
          // We can optimize _scanSymbolicFolderPapers later if needed
          final diskPapers = await _scanSymbolicFolderPapers(folder);
          folder.paperCount = diskPapers.length;
          folder.previewPapers = diskPapers.take(4).toList();
        } catch (e) {
          debugPrint('Error scanning symbolic folder ${folder.name}: $e');
        }
      } else if (folder.id != null && papersByFolder.containsKey(folder.id)) {
        final folderPapers = papersByFolder[folder.id]!;
        folder.paperCount = folderPapers.length;
        // Take up to 4 papers for preview
        folder.previewPapers = folderPapers.take(4).toList();
      }
    }

    _folders = allFolders;

    // Preserve expansion state if possible
    final expandedIds = _folderTree
        .expand((f) => [f, ..._getAllDescendants(f)])
        .where((f) => f.isExpanded)
        .map((f) => f.id)
        .toSet();

    _folderTree = _buildFolderTree(allFolders);

    // Restore expansion
    for (final folder in _folderTree) {
      await _restoreExpansion(folder, expandedIds);
    }

    notifyListeners();
  }

  List<PaperFolder> _getAllDescendants(PaperFolder folder) {
    if (folder.children.isEmpty) return [];
    return [
      ...folder.children,
      ...folder.children.expand((c) => _getAllDescendants(c)),
    ];
  }

  Future<void> _restoreExpansion(
    PaperFolder folder,
    Set<int?> expandedIds,
  ) async {
    if (folder.id != null && expandedIds.contains(folder.id)) {
      folder.isExpanded = true;
    }

    if (folder.isExpanded && folder.isSymbolic && folder.children.isEmpty) {
      await _scanSymbolicFolderChildren(folder);
    }

    for (final child in folder.children) {
      await _restoreExpansion(child, expandedIds);
    }
  }

  /// Toggle folder expansion
  Future<void> toggleFolderExpansion(PaperFolder folder) async {
    folder.isExpanded = !folder.isExpanded;
    notifyListeners();

    if (folder.isExpanded && folder.isSymbolic && folder.children.isEmpty) {
      await _scanSymbolicFolderChildren(folder);
      notifyListeners();
    }
  }

  /// Scan symbolic folder for subdirectories and add as virtual children
  Future<void> _scanSymbolicFolderChildren(PaperFolder folder) async {
    final subDirs = await FolderImportService.getSubDirectories(folder.path);
    if (subDirs.isEmpty) return;

    // Get existing children paths to avoid duplicates
    final existingPaths = folder.children.map((c) => c.path).toSet();

    for (final dir in subDirs) {
      if (!existingPaths.contains(dir.path)) {
        final name = p.basename(dir.path);
        // Create virtual folder
        final child = PaperFolder(
          parentId: folder.id,
          path: dir.path,
          name: name,
          isSymbolic: true,
          children: [],
        );

        // Populate stats for the child
        try {
          final diskPapers = await _scanSymbolicFolderPapers(child);
          child.paperCount = diskPapers.length;
          child.previewPapers = diskPapers.take(4).toList();
        } catch (e) {
          debugPrint('Error scanning subfolder $name: $e');
        }

        folder.children.add(child);
      }
    }

    // Sort children by name (directories first usually, but here all are dirs)
    folder.children.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  /// Scan symbolic folder for PDF files and return as transient Paper objects
  Future<List<Paper>> _scanSymbolicFolderPapers(PaperFolder folder) async {
    final dir = Directory(folder.path);
    if (!await dir.exists()) return [];

    try {
      final entities = await dir.list().toList();
      final pdfFiles = entities
          .whereType<File>()
          .where((f) => p.extension(f.path).toLowerCase() == '.pdf')
          .toList();

      return pdfFiles.map((file) {
        final stat = file.statSync();
        final name = p.basename(file.path);
        // Remove extension for title
        final title = p.basenameWithoutExtension(file.path);

        return Paper(
          id: -1 * (name.hashCode.abs()), // Negative ID for transient papers
          title: title,
          filePath: file.path,
          addedAt: stat.modified,
          isSymbolicLink: true,
          folderId: folder.id, // Associate with current parent
        );
      }).toList();
    } catch (e) {
      print('Error scanning papers in ${folder.path}: $e');
      return [];
    }
  }

  /// Build hierarchical tree from flat folder list
  List<PaperFolder> _buildFolderTree(List<PaperFolder> allFolders) {
    // Map of ID -> List of Children
    final childrenMap = <int, List<PaperFolder>>{};
    for (final folder in allFolders) {
      if (folder.parentId != null) {
        childrenMap.putIfAbsent(folder.parentId!, () => []).add(folder);
      }
    }

    // Helper to recursively build children
    List<PaperFolder> buildChildren(int? parentId) {
      final children = childrenMap[parentId] ?? [];
      return children.map((folder) {
        return PaperFolder(
          id: folder.id,
          parentId: folder.parentId,
          path: folder.path,
          name: folder.name,
          isSymbolic: folder.isSymbolic,
          addedAt: folder.addedAt,
          children: buildChildren(folder.id),
        );
      }).toList();
    }

    // Return root folders (those with parentId == null)
    return allFolders
        .where((f) => f.parentId == null)
        .map(
          (f) => PaperFolder(
            id: f.id,
            parentId: f.parentId,
            path: f.path,
            name: f.name,
            isSymbolic: f.isSymbolic,
            addedAt: f.addedAt,
            children: buildChildren(f.id),
          ),
        )
        .toList();
  }

  /// Get untagged paper count for "Others" category
  Future<int> getUntaggedCount() async {
    return await _db.getUntaggedPaperCount();
  }

  // Config Methods

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Theme
    final themeIndex = prefs.getInt('themeMode');
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    }

    // PDF Reader
    final pdfTypeIndex = prefs.getInt('pdfReaderType');
    if (pdfTypeIndex != null &&
        pdfTypeIndex >= 0 &&
        pdfTypeIndex < PdfReaderType.values.length) {
      _pdfReaderType = PdfReaderType.values[pdfTypeIndex];
    }

    _customPdfAppPath = prefs.getString('customPdfAppPath');
    _customPdfApps = prefs.getStringList('customPdfApps') ?? [];
  }

  void toggleConfigMode() {
    _isConfigMode = !_isConfigMode;
    if (_isConfigMode) {
      _viewingPaper = null; // Exit viewer if entering config
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setPdfReaderType(PdfReaderType type) async {
    _pdfReaderType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pdfReaderType', type.index);
  }

  Future<void> setCustomPdfAppPath(String path) async {
    _customPdfAppPath = path;
    if (!_customPdfApps.contains(path)) {
      _customPdfApps.add(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('customPdfApps', _customPdfApps);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customPdfAppPath', path);
  }
  // ==================== Selection (Folder/Tag) ====================

  /// Select a tag to filter papers
  Future<void> selectTag(Tag? tag) async {
    _selectedTag = tag;
    _selectedFolder = null; // Clear folder selection
    _searchQuery = '';
    _detectedArxivUrl = null;

    if (tag != null && !tag.isOthers) {
      _lastActiveTagPath = await _db.getTagAncestors(tag.id!);
    } else {
      _lastActiveTagPath = [];
    }

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Select a folder to filter papers
  Future<void> selectFolder(PaperFolder folder) async {
    _selectedFolder = folder;
    _selectedTag = null; // Clear tag selection
    _searchQuery = '';
    _detectedArxivUrl = null;
    _lastActiveTagPath = []; // Clear tag path

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Create a new top-level or sub folder
  Future<int> createFolder(
    String name, {
    bool isSymbolic = false,
    String? path,
    int? parentId,
  }) async {
    String folderPath = path ?? '';

    // Create physical directory for non-symbolic folders
    if (!isSymbolic && (path == null || path.isEmpty)) {
      String baseDir;
      if (parentId != null) {
        // Subfolder: inside parent's path
        try {
          final parent = _folders.firstWhere((f) => f.id == parentId);
          baseDir = parent.path;
        } catch (_) {
          baseDir = await PdfService.storageDirectory;
        }
      } else {
        baseDir = await PdfService.storageDirectory;
      }

      final safeName = PdfService.sanitizeFilename(name);
      folderPath = p.join(baseDir, safeName);

      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else if (!isSymbolic && path != null) {
      // Ensure specific path exists
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    // Check if folder with same path already exists (to avoid UNIQUE constraint error)
    // Especially for symbolic links which use the exact external path
    try {
      final existingFolders = await _db.getAllFolders();
      // Simple path check - might need normalization?
      final existing = existingFolders.cast<PaperFolder?>().firstWhere(
        (f) => f?.path == folderPath,
        orElse: () => null,
      );

      if (existing != null && existing.id != null) {
        return existing.id!;
      }

      final id = await _db.insertFolder(
        PaperFolder(
          name: name,
          path: folderPath,
          isSymbolic: isSymbolic,
          parentId: parentId,
        ),
      );
      await _loadFolders();
      return id;
    } catch (e) {
      print('Error creating folder: $e');
      rethrow;
    }
  }

  /// Delete a folder
  Future<void> deleteFolder(PaperFolder folder) async {
    if (folder.id == null) return;

    // 1. Handle Papers
    final papersInFolder = await _db.getPapersByFolder(folder.id!);

    if (folder.isSymbolic) {
      // For symbolic folders, just unlink papers
      for (final paper in papersInFolder) {
        await _db.updatePaperFolder(paper.id!, null);
      }
    } else {
      // Real folder: Delete papers and files
      for (final paper in papersInFolder) {
        // Delete paper (file and DB)
        await deletePaper(paper);
      }

      // Delete physical directory
      if (folder.path.isNotEmpty) {
        final dir = Directory(folder.path);
        if (await dir.exists()) {
          try {
            await dir.delete(recursive: true);
          } catch (e) {
            debugPrint('Error deleting directory: $e');
          }
        }
      }
    }

    // 2. Delete Folder DB Entry
    await _db.deleteFolder(folder.id!);

    // 3. Selection state
    if (_selectedFolder?.id == folder.id) {
      _selectedFolder = null;
      await _loadPapers();
    }
    await _loadFolders();
  }

  // ==================== Search ====================

  /// Update search query
  Future<void> search(String query) async {
    _searchQuery = query.trim();
    _selectedTag = null;
    // DO NOT clear _lastActiveTagPath here to persist context

    // Check for arXiv URL
    if (ArxivService.isArxivUrl(_searchQuery)) {
      _detectedArxivUrl = _searchQuery;
    } else {
      _detectedArxivUrl = null;
    }

    if (_searchQuery.isEmpty) {
      _relatedTags = [];
      await _loadPapers(); // Call _loadPapers to update _papers and _untaggedCount
    } else if (_detectedArxivUrl == null) {
      await _loadPapers();
    }

    // Only push history for non-empty search queries
    if (_searchQuery.isNotEmpty) {
      _pushHistory();
    } else {
      // If cleared, also push history? Or just treat as "root"?
      // If we go back from search "X" to empty, it should be in history.
      // But _onSearchChanged debounces, so multiple keystrokes might be an issue.
      // For now, let's push for empty too if we were previously searching.
      _pushHistory();
    }

    notifyListeners();
  }

  /// Clear search
  Future<void> clearSearch() async {
    _searchQuery = '';
    _detectedArxivUrl = null;
    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  /// Clear all selection (Tag/Folder/Search)
  Future<void> clearSelection() async {
    _selectedTag = null;
    _selectedFolder = null;
    _lastActiveTagPath = [];
    _searchQuery = '';
    _detectedArxivUrl = null;

    _pushHistory();
    await _loadPapers();
    notifyListeners();
  }

  // ==================== Paper Import ====================

  /// Import papers with assigned tags
  Future<List<Paper>> importPapers(
    List<PendingImport> pendingImports,
    bool useFolderTags, {
    int? folderId,
  }) async {
    // Fire and forget (background import)
    // We return empty list immediately so UI doesn't block
    _processImports(pendingImports, useFolderTags, folderId: folderId);
    return [];
  }

  Future<void> _processImports(
    List<PendingImport> pendingImports,
    bool useFolderTags, {
    int? folderId,
  }) async {
    _isImporting = true;
    _importProgress = 0.0;
    _importStatus = 'Starting import...';
    notifyListeners();

    // Resolve target directory
    String? targetDirectory;
    if (folderId != null) {
      try {
        final folder = _folders.firstWhere((f) => f.id == folderId);
        targetDirectory = folder.path;
      } catch (_) {}
    }

    final totalCount = pendingImports.where((p) => p.isSelected).length;
    int processedCount = 0;

    try {
      for (final pending in pendingImports) {
        if (!pending.isSelected) continue;

        processedCount++;
        _importProgress = processedCount / totalCount;
        _importStatus =
            'Importing ${processedCount}/${totalCount}: ${pending.fileName}';
        notifyListeners();

        try {
          // Extract title first to use as filename
          final title = await _pdfService.extractTitle(pending.sourcePath);

          // Copy PDF to storage
          final storedPath = await _pdfService.importPdf(
            pending.sourcePath,
            title: title,
            asLink: pending.asLink,
            destinationDirectory: targetDirectory,
          );

          // Extract text
          final text = await _pdfService.extractText(storedPath);

          // Create paper record
          final paperId = await _db.insertPaper(
            Paper(
              title: title,
              filePath: storedPath,
              extractedText: text,
              isSymbolicLink: pending.asLink,
              folderId: folderId,
            ),
          );

          // Create/get tags and associate
          final tagIds = <int>{};

          // Handle folder hierarchy if enabled
          final folderTagNames = <String>{};
          if (useFolderTags && pending.suggestedTags.isNotEmpty) {
            int? parentId;
            for (final tagName in pending.suggestedTags) {
              final tag = await _db.getOrCreateTag(tagName, parentId: parentId);
              parentId = tag.id;
              tagIds.add(tag.id!);
              folderTagNames.add(tagName);
            }
          }

          // Handle other tags (manual/context)
          for (final tagName in pending.assignedTags) {
            // Skip tags that were already handled as part of the folder hierarchy
            if (folderTagNames.contains(tagName)) continue;

            // Parse hierarchical paths like "A/B" into parent-child structure
            final tagId = await _getOrCreateTagFromPath(tagName);
            tagIds.add(tagId);
          }

          await _db.setTagsForPaper(paperId, tagIds.toList());

          _addImportHistory(title, true, 'Successfully imported');

          // Refresh tag tree and paper counts to show progress in UI live
          await _loadTagTree();
          _untaggedCount = await _db.getUntaggedPaperCount();
          notifyListeners();
        } catch (e) {
          print('Error importing ${pending.fileName}: $e');
          _addImportHistory(pending.fileName, false, 'Error: $e');
        }
      }

      await refresh();
    } catch (e) {
      _error = 'Import process failed: $e';
      print(_error);
    }

    _isImporting = false;
    _importStatus = '';
    notifyListeners();
  }

  /// Import from arXiv URL
  Future<Paper?> importFromArxiv(
    String urlOrId,
    List<String> tagNames, {
    int? folderId,
  }) async {
    _isLoading = true;
    _isImporting = true;
    _importProgress = 0.0;
    _importStatus = 'Starting import...';
    notifyListeners();

    String? arxivId;

    try {
      arxivId = ArxivService.parseArxivId(urlOrId);
      if (arxivId == null) {
        _error = 'Invalid arXiv URL or ID';
        _addImportHistory(urlOrId, false, 'Invalid arXiv URL or ID');
        _isLoading = false;
        _isImporting = false;
        notifyListeners();
        return null;
      }

      // Fetch metadata
      _importStatus = 'Fetching metadata from arXiv...';
      _importProgress = 0.2;
      notifyListeners();

      final metadata = await _arxivService.fetchMetadata(arxivId);
      if (metadata == null) {
        _error = 'Could not fetch arXiv metadata';
        _addImportHistory(arxivId, false, 'Failed to fetch metadata');
        _isLoading = false;
        _isImporting = false;
        notifyListeners();
        return null;
      }

      // Download PDF
      _importStatus = 'Downloading PDF: ${metadata.title}';
      _importProgress = 0.4;
      notifyListeners();

      final tempPath = await _arxivService.downloadPdf(arxivId);
      if (tempPath == null) {
        _error = 'Could not download PDF';
        _addImportHistory(metadata.title, false, 'Failed to download PDF');
        _isLoading = false;
        _isImporting = false;
        notifyListeners();
        return null;
      }

      // Resolve target directory
      String? targetDirectory;
      if (folderId != null) {
        try {
          final folder = _folders.firstWhere((f) => f.id == folderId);
          targetDirectory = folder.path;
        } catch (_) {}
      }

      // Import PDF
      _importStatus = 'Processing PDF...';
      _importProgress = 0.6;
      notifyListeners();

      final storedPath = await _pdfService.importPdf(
        tempPath,
        title: metadata.title,
        destinationDirectory: targetDirectory,
      );

      _importStatus = 'Extracting text...';
      _importProgress = 0.8;
      notifyListeners();

      final extractedText = await _pdfService.extractText(storedPath);

      // Create paper record
      final paperId = await _db.insertPaper(
        Paper(
          title: metadata.title,
          filePath: storedPath,
          arxivId: arxivId,
          authors: metadata.authors,
          abstract: metadata.abstract,
          extractedText: extractedText,
          arxivUrl: 'https://arxiv.org/abs/$arxivId',
          folderId: folderId,
        ),
      );

      // Create/get tags and associate
      final tagIds = <int>[];
      for (final tagName in tagNames) {
        // Parse hierarchical paths like "A/B" into parent-child structure
        final tagId = await _getOrCreateTagFromPath(tagName);
        tagIds.add(tagId);
      }
      await _db.setTagsForPaper(paperId, tagIds);

      // Clear detected URL
      _detectedArxivUrl = null;
      _searchQuery = '';

      _importStatus = 'Finalizing...';
      _importProgress = 0.95;
      notifyListeners();

      await refresh();

      final tags = await _db.getTagsForPaper(paperId);
      final paper = Paper(
        id: paperId,
        title: metadata.title,
        filePath: storedPath,
        arxivId: arxivId,
        authors: metadata.authors,
        abstract: metadata.abstract,
        extractedText: extractedText,
        arxivUrl: 'https://arxiv.org/abs/$arxivId',
        tags: tags,
      );

      _importStatus = 'Import complete!';
      _importProgress = 1.0;
      _addImportHistory(metadata.title, true, 'Successfully imported');

      // Clear import state after a brief delay
      Future.delayed(const Duration(seconds: 2), () {
        _isImporting = false;
        _importStatus = '';
        _importProgress = 0.0;
        notifyListeners();
      });

      _isLoading = false;
      notifyListeners();
      return paper;
    } catch (e) {
      _error = 'arXiv import failed: $e';
      _addImportHistory(arxivId ?? urlOrId, false, 'Error: $e');
      print(_error);
    }

    _isLoading = false;
    _isImporting = false;
    _importStatus = '';
    _importProgress = 0.0;
    notifyListeners();
    return null;
  }

  void _addImportHistory(String title, bool success, String message) {
    _importHistory.insert(0, {
      'title': title,
      'success': success,
      'message': message,
      'timestamp': DateTime.now(),
    });
    // Keep only last 50 imports
    if (_importHistory.length > 50) {
      _importHistory.removeLast();
    }
  }

  /// Scan folder for import preview
  Future<FolderScanResult?> scanFolder(String folderPath) async {
    try {
      return await _folderImportService.scanFolder(folderPath);
    } catch (e) {
      _error = 'Folder scan failed: $e';
      print(_error);
      return null;
    }
  }

  /// Fetch arXiv metadata for preview
  Future<ArxivMetadata?> fetchArxivMetadata(String urlOrId) async {
    final arxivId = ArxivService.parseArxivId(urlOrId);
    if (arxivId == null) return null;
    return await _arxivService.fetchMetadata(arxivId);
  }

  /// Rebuild title for a paper by extracting from PDF
  Future<void> rebuildPaperTitle(int paperId) async {
    try {
      final paper = _papers.firstWhere((p) => p.id == paperId);
      final newTitle = await _pdfService.extractTitle(paper.filePath);

      if (newTitle.isNotEmpty) {
        await _db.updatePaper(paper.copyWith(title: newTitle));
        await refresh();
      }
    } catch (e) {
      _error = 'Failed to rebuild title: $e';
      print(_error);
      notifyListeners();
    }
  }

  /// Rebuild titles for all papers
  Future<void> rebuildAllPaperTitles() async {
    _isLoading = true;
    _importStatus = 'Rebuilding paper titles...';
    _importProgress = 0.0;
    notifyListeners();

    try {
      final allPapers = await _db.getAllPapers();
      for (int i = 0; i < allPapers.length; i++) {
        final paper = allPapers[i];
        _importStatus = 'Rebuilding: ${paper.title}';
        _importProgress = (i + 1) / allPapers.length;
        notifyListeners();

        final newTitle = await _pdfService.extractTitle(paper.filePath);
        if (newTitle.isNotEmpty && newTitle != paper.title) {
          await _db.updatePaper(paper.copyWith(title: newTitle));
        }
      }

      await refresh();
      _importStatus = 'Titles rebuilt successfully!';
      _importProgress = 1.0;

      Future.delayed(const Duration(seconds: 2), () {
        _importStatus = '';
        _importProgress = 0.0;
        notifyListeners();
      });
    } catch (e) {
      _error = 'Failed to rebuild titles: $e';
      print(_error);
      _importStatus = '';
      _importProgress = 0.0;
    }

    _isLoading = false;
    notifyListeners();
  }

  // ==================== Tag Management ====================

  /// Create a new tag
  Future<Tag> createTag(String name, {int? parentId}) async {
    final tag = await _db.getOrCreateTag(name, parentId: parentId);
    await _loadTagTree();
    notifyListeners();
    return tag;
  }

  /// Update paper tags
  Future<void> updatePaperTags(int paperId, List<Tag> tags) async {
    await _db.setTagsForPaper(paperId, tags.map((t) => t.id!).toList());
    await refresh();
  }

  /// Add a tag to selected papers
  Future<void> addTagToSelectedPapers(Tag tag) async {
    if (_selectedPaperIds.isEmpty || tag.id == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      for (final paperId in _selectedPaperIds) {
        await _db.addTagToPaper(paperId, tag.id!);
      }

      // Refresh to show updated tags
      await refresh();
    } catch (e) {
      _error = 'Failed to assign tag: $e';
      print(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Delete a tag
  Future<void> deleteTag(int tagId) async {
    await _db.deleteTag(tagId);
    if (_selectedTag?.id == tagId) {
      _selectedTag = null;
    }
    await refresh();
  }

  /// Rename a tag
  Future<void> renameTag(int tagId, String newName) async {
    await _db.updateTag(tagId, newName);
    await refresh();
  }

  /// Toggle tag expansion in tree
  void toggleTagExpansion(Tag tag) {
    tag.isExpanded = !tag.isExpanded;
    notifyListeners();
  }

  /// Parse hierarchical tag path (e.g., "A/B/C") and create tags recursively
  /// Returns the ID of the leaf tag
  Future<int> _getOrCreateTagFromPath(String tagPath) async {
    // Split by '/' and create hierarchy
    final parts = tagPath
        .split('/')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw ArgumentError('Invalid tag path: $tagPath');
    }

    int? parentId;
    Tag? leafTag;

    for (final tagName in parts) {
      leafTag = await _db.getOrCreateTag(tagName, parentId: parentId);
      parentId = leafTag.id;
    }

    return leafTag!.id!;
  }

  /// Get all tags (flat list)
  Future<List<Tag>> getAllTags() async {
    return await _db.getAllTags();
  }

  /// Search tags by name
  Future<List<Tag>> searchTags(String query) async {
    return await _db.searchTags(query);
  }

  /// Get a paper by title from the database
  Future<Paper?> getPaperByTitle(String title) async {
    return await _db.getPaperByTitle(title);
  }

  /// Get tags for a specific paper
  Future<List<Tag>> getTagsForPaper(int paperId) async {
    return await _db.getTagsForPaper(paperId);
  }

  /// Get tag ancestors (full path from root to tag)
  Future<List<Tag>> getTagAncestors(int tagId) async {
    return await _db.getTagAncestors(tagId);
  }

  /// Set tags for a specific paper
  Future<void> setTagsForPaper(int paperId, List<int> tagIds) async {
    await _db.setTagsForPaper(paperId, tagIds);
    await refresh();
  }

  // ==================== Paper Management ====================

  /// Update paper
  Future<void> updatePaper(Paper paper) async {
    await _db.updatePaper(paper);
    await refresh();
  }

  /// Delete a paper
  Future<void> deletePaper(Paper paper) async {
    await _pdfService.deletePdf(paper.filePath);
    await _db.deletePaper(paper.id!);
    _openTabs.removeWhere((p) => p.id == paper.id);
    if (_viewingPaper?.id == paper.id) {
      _viewingPaper = _openTabs.isNotEmpty ? _openTabs.first : null;
    }
    await refresh();
  }

  /// Open paper with preferred PDF viewer
  Future<bool> openPaper(Paper paper) async {
    if (_pdfReaderType == PdfReaderType.embedded) {
      // Maintain MRU open tabs list
      _openTabs.removeWhere((p) => p.id == paper.id);
      _openTabs.insert(0, paper);
      _viewingPaper = paper;
      _isConfigMode = false;
      notifyListeners();
      return true;
    } else if (_pdfReaderType == PdfReaderType.custom &&
        _customPdfAppPath != null) {
      return await PdfService.openWithCustomApp(
        paper.filePath,
        _customPdfAppPath!,
      );
    } else {
      return await PdfService.openWithSystemViewer(paper.filePath);
    }
  }

  /// Close embedded viewer
  void closePaperViewer() {
    _viewingPaper = null;
    notifyListeners();
  }

  /// Switch to an already-open tab (or add if missing)
  void switchToTab(Paper paper) {
    _openTabs.removeWhere((p) => p.id == paper.id);
    _openTabs.insert(0, paper);
    _viewingPaper = paper;
    _isConfigMode = false;
    notifyListeners();
  }

  /// Close a specific open tab
  void closeTab(Paper paper) {
    final closingCurrent = _viewingPaper?.id == paper.id;
    _openTabs.removeWhere((p) => p.id == paper.id);
    if (closingCurrent) {
      _viewingPaper = _openTabs.isNotEmpty ? _openTabs.first : null;
    }
    notifyListeners();
  }

  /// Reveal paper in Finder
  Future<bool> revealPaperInFinder(Paper paper) async {
    return await PdfService.revealInFinder(paper.filePath);
  }

  // ==================== Selection Management ====================

  /// Toggle selection of a paper
  void togglePaperSelection(int paperId) {
    if (_selectedPaperIds.contains(paperId)) {
      _selectedPaperIds.remove(paperId);
    } else {
      _selectedPaperIds.add(paperId);
    }
    notifyListeners();
  }

  /// Select a single paper (clearing others)
  void selectPaper(int paperId) {
    _selectedPaperIds.clear();
    _selectedPaperIds.add(paperId);
    notifyListeners();
  }

  /// Clear all paper selections
  void clearPaperSelection() {
    _selectedPaperIds.clear();
    notifyListeners();
  }

  /// Check if papers exist in library
  /// returns a Set of filenames that already exist (based on target path collision)
  Future<Set<String>> checkIfPapersExist(List<PendingImport> files) async {
    if (files.isEmpty) return {};

    final appDocDir = await getApplicationSupportDirectory();
    final predictedPaths =
        <String, String>{}; // predictedPath -> originalFileName

    for (final file in files) {
      // Predict where the file would be saved
      final targetPath = p.join(appDocDir.path, 'papers', file.fileName);
      predictedPaths[targetPath] = file.fileName;
    }

    final existingPaths = await _db.checkPapersExist(
      predictedPaths.keys.toList(),
    );

    // Map existing paths back to filenames
    final existingFilenames = <String>{};
    for (final path in existingPaths) {
      if (predictedPaths.containsKey(path)) {
        existingFilenames.add(predictedPaths[path]!);
      }
    }

    return existingFilenames;
  }

  /// Select all currently visible papers
  void selectAllPapers() {
    _selectedPaperIds.clear();
    _selectedPaperIds.addAll(_papers.map((p) => p.id!));
    notifyListeners();
  }

  /// Deselect all papers
  void deselectAllPapers() {
    _selectedPaperIds.clear();
    notifyListeners();
  }

  /// Check if a paper is selected
  bool isPaperSelected(int paperId) => _selectedPaperIds.contains(paperId);

  /// Delete selected papers
  Future<void> deleteSelectedPapers() async {
    if (_selectedPaperIds.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    // Create a copy of IDs to delete to avoid modification during iteration
    final idsToDelete = _selectedPaperIds.toList();

    try {
      for (final id in idsToDelete) {
        // Find paper to get path for deletion
        // We use firstWhereOrNull logic essentially
        try {
          final paper = _papers.firstWhere((p) => p.id == id);

          // Delete file
          await _pdfService.deletePdf(paper.filePath);

          // Delete from DB (without triggering full refresh yet)
          await _db.deletePaper(id);
        } catch (e) {
          print('Error deleting paper $id: $e');
          // Continue deleting others even if one fails
        }
      }

      // Perform a single refresh at the end
      await refresh();
    } catch (e) {
      _error = 'Failed to delete selected papers: $e';
    }

    _selectedPaperIds.clear(); // Ensure selection is cleared
    _isLoading = false;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
