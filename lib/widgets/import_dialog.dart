import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/import_data.dart';
import '../models/tag.dart';
import '../models/paper_folder.dart';
import '../providers/app_state.dart';

/// Universal import confirmation dialog
class ImportDialog extends StatefulWidget {
  final ImportType importType;
  final List<PendingImport>? pendingFiles;
  final FolderScanResult? folderScanResult;
  final ArxivMetadata? arxivMetadata;
  final Tag? currentTag;
  final bool initialImportAsLink;

  const ImportDialog({
    super.key,
    required this.importType,
    this.pendingFiles,
    this.folderScanResult,
    this.arxivMetadata,
    this.currentTag,
    this.initialImportAsLink = false,
  });

  /// Show dialog for PDF file import
  static Future<bool?> showForFiles(
    BuildContext context,
    List<String> filePaths, {
    Tag? currentTag,
  }) async {
    final pendingFiles = filePaths
        .map(
          (path) => PendingImport(
            sourcePath: path,
            fileName: path.split('/').last,
            assignedTags: currentTag != null && !currentTag.isOthers
                ? [currentTag.name]
                : [],
          ),
        )
        .toList();

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportDialog(
        importType: filePaths.length == 1
            ? ImportType.singleFile
            : ImportType.multipleFiles,
        pendingFiles: pendingFiles,
        currentTag: currentTag,
      ),
    );
  }

  /// Show dialog for folder import
  static Future<bool?> showForFolder(
    BuildContext context,
    FolderScanResult scanResult, {
    Tag? currentTag,
    bool initialImportAsLink = false,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportDialog(
        importType: ImportType.folder,
        folderScanResult: scanResult,
        currentTag: currentTag,
        initialImportAsLink: initialImportAsLink,
      ),
    );
  }

  /// Show dialog for arXiv import
  static Future<bool?> showForArxiv(
    BuildContext context,
    ArxivMetadata metadata, {
    Tag? currentTag,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ImportDialog(
        importType: ImportType.arxiv,
        arxivMetadata: metadata,
        currentTag: currentTag,
      ),
    );
  }

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  late List<PendingImport> _files;
  List<PendingImport> _existingFiles = [];
  bool _useFolderTags = true;
  bool _createParentFolder = true;
  bool _applyCurrentTag = false;
  bool _importAsLink = false;
  int? _selectedFolderId;
  final Set<String> _additionalTags = {};
  final TextEditingController _tagController = TextEditingController();
  List<Tag> _allTags = [];
  List<Tag> _suggestedTags = [];
  String _searchQuery = '';
  bool _isLoading = false;
  Map<int, String> _tagIdToFullPath = {}; // Cache for tag full paths

  @override
  void initState() {
    super.initState();
    // Default to ROOT for folders, or selected folder for files?
    // User requested "when drag folder inside, always default location to root"
    // We will default to Root (null) generally if it is a folder scan
    final appState = context.read<AppState>();

    if (widget.importType == ImportType.folder) {
      _selectedFolderId = null;
    } else {
      _selectedFolderId = appState.selectedFolder?.id;
    }

    _importAsLink = widget.initialImportAsLink;

    _initializeFiles();
    _loadTags();
    _tagController.addListener(_onSearchChanged);
    // Defer check to next frame to allow context access if needed, though read works
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDuplicates());
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _tagController.text.toLowerCase();
      _updateSuggestions();
    });
  }

  void _updateSuggestions() {
    if (_searchQuery.isEmpty) {
      // Show unselected tags, limited to first 15
      final seenPaths = <String>{};
      _suggestedTags = _allTags
          .where((tag) {
            final fullPath = _tagIdToFullPath[tag.id] ?? tag.name;
            if (_additionalTags.contains(fullPath) ||
                seenPaths.contains(fullPath)) {
              return false;
            }
            seenPaths.add(fullPath);
            return true;
          })
          .take(15)
          .toList();
    } else {
      // Fuzzy search: match tags containing the search query
      final seenPaths = <String>{};
      _suggestedTags = _allTags
          .where((tag) {
            final tagLower = tag.name.toLowerCase();
            final fullPath = _tagIdToFullPath[tag.id] ?? tag.name;
            if (_additionalTags.contains(fullPath) ||
                seenPaths.contains(fullPath)) {
              return false;
            }
            if (tagLower.contains(_searchQuery)) {
              seenPaths.add(fullPath);
              return true;
            }
            return false;
          })
          .take(15)
          .toList();
    }
  }

  void _initializeFiles() {
    if (widget.importType == ImportType.folder &&
        widget.folderScanResult != null) {
      _files = List.from(widget.folderScanResult!.files);
    } else if (widget.pendingFiles != null) {
      _files = List.from(widget.pendingFiles!);
    } else {
      _files = [];
    }

    // Set applyCurrentTag if we have a current tag that's not "Others"
    if (widget.currentTag != null && !widget.currentTag!.isOthers) {
      _applyCurrentTag = true;
    }
  }

  Future<void> _checkDuplicates() async {
    final appState = context.read<AppState>();
    // Check all files initially
    final existingNames = await appState.checkIfPapersExist(_files);

    if (existingNames.isNotEmpty) {
      setState(() {
        final newFiles = <PendingImport>[];
        _existingFiles = <PendingImport>[];

        for (final file in _files) {
          if (existingNames.contains(file.fileName)) {
            _existingFiles.add(file);
            file.isSelected = false; // Default unselected for existing
          } else {
            newFiles.add(file);
          }
        }
        _files = newFiles;
      });
    }
  }

  Future<void> _loadTags() async {
    final appState = context.read<AppState>();
    _allTags = await appState.getAllTags();
    await _buildTagPathCache();
    _updateSuggestions();
    setState(() {});
  }

  /// Build cache of tag ID to full hierarchical path (e.g., "A/B")
  Future<void> _buildTagPathCache() async {
    final appState = context.read<AppState>();
    for (final tag in _allTags) {
      if (tag.id != null) {
        final ancestors = await appState.getTagAncestors(tag.id!);
        final fullPath = ancestors.map((t) => t.name).join('/');
        _tagIdToFullPath[tag.id!] = fullPath;
      }
    }
  }

  void _addTag(String tagName) {
    if (tagName.trim().isEmpty) return;

    setState(() {
      _additionalTags.add(tagName.trim());
      _tagController.clear();
      _updateSuggestions();
    });
  }

  void _addExistingTag(Tag tag) {
    setState(() {
      // Add full hierarchical path instead of just tag name
      final fullPath = _tagIdToFullPath[tag.id] ?? tag.name;
      _additionalTags.add(fullPath);
      _tagController.clear();
      _updateSuggestions();
    });
  }

  void _removeTag(String tagName) {
    setState(() {
      _additionalTags.remove(tagName);
    });
  }

  int get _selectedFileCount =>
      _files.where((f) => f.isSelected).length +
      _existingFiles.where((f) => f.isSelected).length;

  List<String> _getTagsForFile(PendingImport file) {
    final tags = <String>{};

    // Add folder tags if enabled
    if (_useFolderTags && widget.importType == ImportType.folder) {
      tags.addAll(file.suggestedTags);
    }

    // Add current tag if enabled
    if (_applyCurrentTag &&
        widget.currentTag != null &&
        !widget.currentTag!.isOthers) {
      tags.add(widget.currentTag!.name);
    }

    // Add additional tags
    tags.addAll(_additionalTags);

    return tags.toList();
  }

  Future<void> _import() async {
    setState(() => _isLoading = true);

    final appState = context.read<AppState>();

    try {
      // Resolve target folder
      int? targetFolderId = _selectedFolderId;

      if (widget.importType == ImportType.folder &&
          _createParentFolder &&
          widget.folderScanResult != null) {
        targetFolderId = await appState.createFolder(
          widget.folderScanResult!.folderName,
          path: widget.folderScanResult!.folderPath,
          isSymbolic: _importAsLink,
        );
      }

      if (widget.importType == ImportType.arxiv &&
          widget.arxivMetadata != null) {
        // arXiv import
        final tags = <String>[];
        if (_applyCurrentTag &&
            widget.currentTag != null &&
            !widget.currentTag!.isOthers) {
          tags.add(widget.currentTag!.name);
        }
        tags.addAll(_additionalTags);

        await appState.importFromArxiv(
          widget.arxivMetadata!.arxivId,
          tags,
          folderId: targetFolderId,
        );
      } else {
        // File/folder import
        // Combine both lists for import
        final allFiles = [..._files, ..._existingFiles];
        for (final file in allFiles) {
          if (file.isSelected) {
            file.assignedTags = _getTagsForFile(file);
            file.asLink = _importAsLink;
          }
        }

        await appState.importPapers(
          allFiles,
          _useFolderTags,
          folderId: targetFolderId,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: _existingFiles.isNotEmpty ? 900 : 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildContent(),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),
                    _buildTagSection(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String title;
    switch (widget.importType) {
      case ImportType.singleFile:
        title = 'Import Paper';
        break;
      case ImportType.multipleFiles:
        title = 'Import Papers';
        break;
      case ImportType.folder:
        title = 'Import Folder';
        break;
      case ImportType.arxiv:
        title = 'Import from arXiv';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            widget.importType == ImportType.arxiv
                ? Icons.cloud_download_outlined
                : widget.importType == ImportType.folder
                ? Icons.folder_open
                : Icons.picture_as_pdf,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.importType) {
      case ImportType.arxiv:
        return _buildArxivContent();
      case ImportType.folder:
        return _buildFolderContent();
      default:
        return _buildFileContent();
    }
  }

  Widget _buildArxivContent() {
    final metadata = widget.arxivMetadata!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metadata.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metadata.authors,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'arXiv:${metadata.arxivId}${metadata.category != null ? " [${metadata.category}]" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (metadata.abstract.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Abstract:',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              metadata.abstract.length > 300
                  ? '${metadata.abstract.substring(0, 300)}...'
                  : metadata.abstract,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildLocationSelector(),
        ],
      ),
    );
  }

  Widget _buildFolderContent() {
    final scanResult = widget.folderScanResult!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                scanResult.folderName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${scanResult.fileCount} PDF files discovered',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSplitFileList(),
        const SizedBox(height: 16),
        _buildLocationSelector(),
        CheckboxListTile(
          value: _createParentFolder,
          onChanged: (value) =>
              setState(() => _createParentFolder = value ?? true),
          title: Text('Create folder "${scanResult.folderName}"'),
          subtitle: const Text('Group imported papers into this folder'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _useFolderTags,
          onChanged: (value) => setState(() => _useFolderTags = value ?? true),
          title: const Text('Use folder names as tags'),
          subtitle: const Text(
            'Creates tag hierarchy matching folder structure',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _importAsLink,
          onChanged: (value) => setState(() => _importAsLink = value ?? false),
          title: const Text('Link only (do not copy files)'),
          subtitle: const Text(
            'Keep files in original location and create symbolic references',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildFileContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_existingFiles.isEmpty)
          Text(
            'Files to import:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        const SizedBox(height: 8),
        _buildSplitFileList(),
        const SizedBox(height: 16),
        _buildLocationSelector(),
        CheckboxListTile(
          value: _importAsLink,
          onChanged: (value) => setState(() => _importAsLink = value ?? false),
          title: const Text('Link only (do not copy files)'),
          subtitle: const Text(
            'Keep files in original location and create symbolic references',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildSplitFileList() {
    if (_existingFiles.isEmpty) {
      return _buildFileList(_files);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // New Files Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildListHeader('New Papers', _files),
              const SizedBox(height: 8),
              _buildFileList(_files),
            ],
          ),
        ),
        const SizedBox(width: 16),
        VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        const SizedBox(width: 16),
        // Existing Files Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildListHeader('Already in Library', _existingFiles),
              const SizedBox(height: 8),
              _buildFileList(_existingFiles),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader(String title, List<PendingImport> files) {
    bool allSelected = files.isNotEmpty && files.every((f) => f.isSelected);
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (files.isNotEmpty)
          Row(
            children: [
              Checkbox(
                value: allSelected,
                onChanged: (value) {
                  setState(() {
                    for (var f in files) {
                      f.isSelected = value ?? false;
                    }
                  });
                },
                visualDensity: VisualDensity.compact,
              ),
              Text('Select All', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }

  Widget _buildFileList(List<PendingImport> files) {
    if (files.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('No files', style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return Container(
      constraints: const BoxConstraints(
        maxHeight: 300,
      ), // Increased height for better view
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final allTags = _getTagsForFile(file);
          return CheckboxListTile(
            dense: true,
            value: file.isSelected,
            onChanged: (value) {
              setState(() => file.isSelected = value ?? true);
            },
            secondary: Icon(
              Icons.picture_as_pdf,
              color: Theme.of(context).colorScheme.error,
              size: 20,
            ),
            title: Text(
              file.fileName,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: allTags.isNotEmpty
                ? Wrap(
                    spacing: 4,
                    children: allTags
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            labelStyle: const TextStyle(fontSize: 10),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _buildTagSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tags:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),

        // Current tag option
        if (widget.currentTag != null && !widget.currentTag!.isOthers) ...[
          CheckboxListTile(
            value: _applyCurrentTag,
            onChanged: (value) =>
                setState(() => _applyCurrentTag = value ?? false),
            title: Row(
              children: [
                const Text('Apply current tag: '),
                Chip(
                  label: Text(widget.currentTag!.name),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                ),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
        ],

        // Selected tags (displayed above input)
        if (_additionalTags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _additionalTags.map((tag) {
              return Chip(
                label: Text(tag),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeTag(tag),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Tag input with add button
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                decoration: InputDecoration(
                  hintText: 'Search or create tag...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  if (value.trim().isEmpty) return;
                  // Check if exact match exists (by full path or leaf name)
                  final valueLower = value.trim().toLowerCase();
                  final existingTag = _allTags.cast<Tag?>().firstWhere((t) {
                    if (t == null) return false;
                    final fullPath = _tagIdToFullPath[t.id] ?? t.name;
                    return fullPath.toLowerCase() == valueLower ||
                        t.name.toLowerCase() == valueLower;
                  }, orElse: () => null);
                  if (existingTag != null) {
                    _addExistingTag(existingTag);
                  } else {
                    _addTag(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                final value = _tagController.text.trim();
                if (value.isEmpty) return;
                // Check if exact match exists (by full path or leaf name)
                final valueLower = value.toLowerCase();
                final existingTag = _allTags.cast<Tag?>().firstWhere((t) {
                  if (t == null) return false;
                  final fullPath = _tagIdToFullPath[t.id] ?? t.name;
                  return fullPath.toLowerCase() == valueLower ||
                      t.name.toLowerCase() == valueLower;
                }, orElse: () => null);
                if (existingTag != null) {
                  _addExistingTag(existingTag);
                } else {
                  _addTag(value);
                }
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),

        // Tag suggestions (up to 3 lines)
        if (_suggestedTags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 100),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _suggestedTags.map((tag) {
                final fullPath = _tagIdToFullPath[tag.id] ?? tag.name;
                return ActionChip(
                  label: Text(fullPath),
                  onPressed: () => _addExistingTag(tag),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    String buttonText;
    int count;

    switch (widget.importType) {
      case ImportType.arxiv:
        buttonText = 'Download & Import';
        count = 1;
        break;
      case ImportType.folder:
        buttonText = 'Import $_selectedFileCount Papers';
        count = _selectedFileCount;
        break;
      default:
        buttonText =
            'Import $_selectedFileCount ${_selectedFileCount == 1 ? "Paper" : "Papers"}';
        count = _selectedFileCount;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: (_isLoading || count == 0) ? null : _import,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(buttonText),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelector() {
    final appState = context.read<AppState>();

    // Ensure selected ID is valid
    if (_selectedFolderId != null &&
        !appState.folders.any((f) => f.id == _selectedFolderId)) {
      _selectedFolderId = null;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: DropdownButtonFormField<int?>(
        value: _selectedFolderId,
        decoration: const InputDecoration(
          labelText: 'Import Location',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.folder_open),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        isExpanded: true,
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('Root (No Folder)'),
          ),
          ...appState.folders.map(
            (folder) => DropdownMenuItem(
              value: folder.id,
              child: Row(
                children: [
                  Icon(folder.isSymbolic ? Icons.link : Icons.folder, size: 16),
                  const SizedBox(width: 8),
                  Text(folder.name),
                ],
              ),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _selectedFolderId = value),
      ),
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }
}
