import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import '../providers/app_state.dart';
import '../database/database_service.dart';
import '../services/arxiv_service.dart';

/// Dialog for downloading papers from arXiv with smart context-aware suggestions.
class DownloadDialog extends StatefulWidget {
  final String? arxivUrl;

  /// Current context for smart suggestions
  final Entry? contextEntry;
  final String? contextSubfolder;
  final Tag? contextTag;

  const DownloadDialog({
    super.key,
    this.arxivUrl,
    this.contextEntry,
    this.contextSubfolder,
    this.contextTag,
  });

  static Future<void> show(BuildContext context, {String? arxivUrl}) {
    final appState = context.read<AppState>();
    return showDialog(
      context: context,
      builder: (ctx) => DownloadDialog(
        arxivUrl: arxivUrl,
        contextEntry: appState.selectedEntry,
        contextSubfolder: appState.selectedSubfolder,
        contextTag: appState.selectedTag,
      ),
    );
  }

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  final ArxivService _arxivService = ArxivService();
  final TextEditingController _subfolderController = TextEditingController();

  ArxivMetadata? _metadata;
  Entry? _selectedEntry;
  bool _isFetchingMetadata = true;
  bool _isDownloading = false;
  String? _error;

  // Tag suggestions
  List<Tag> _suggestedTags = [];
  Set<int> _selectedTagIds = {};
  List<String> _subfolderSuggestions = [];
  bool _isCustomSubfolder = false;

  @override
  void initState() {
    super.initState();
    _initContext();
    _fetchMetadata();
  }

  void _initContext() {
    final appState = context.read<AppState>();
    final entries = appState.entries;

    // Pre-select entry from context
    if (widget.contextEntry != null) {
      _selectedEntry = entries
          .where((e) => e.id == widget.contextEntry!.id)
          .firstOrNull;
    }
    _selectedEntry ??= entries.isNotEmpty ? entries.first : null;

    // Pre-fill subfolder from context
    if (widget.contextSubfolder != null) {
      _subfolderController.text = widget.contextSubfolder!;
    }

    // Pre-select current tag
    if (widget.contextTag != null &&
        !widget.contextTag!.isUntagged &&
        widget.contextTag!.id != null) {
      _selectedTagIds.add(widget.contextTag!.id!);
    }

    // Build tag suggestions and subfolder suggestions
    _buildSuggestions(appState);
  }

  void _buildSuggestions(AppState appState) {
    final allTags = <Tag>[];
    void collectTags(List<Tag> tags) {
      for (final t in tags) {
        allTags.add(t);
        collectTags(t.children);
      }
    }
    collectTags(appState.tagTree);

    // Score tags: higher score = shown first
    // Current tag gets highest priority, then tags on papers in current context
    final tagScores = <int, int>{};
    for (final t in allTags) {
      if (t.id == null) continue;
      tagScores[t.id!] = 0;
    }

    // Current tag gets top score
    if (widget.contextTag != null && widget.contextTag!.id != null) {
      tagScores[widget.contextTag!.id!] = 1000;
    }

    // Tags from papers in current view get bonus
    for (final paper in appState.papers) {
      for (final tag in paper.tags) {
        if (tag.id != null) {
          tagScores[tag.id!] = (tagScores[tag.id!] ?? 0) + 10;
        }
      }
    }

    // Sort by score descending, then by name
    allTags.sort((a, b) {
      final scoreA = tagScores[a.id] ?? 0;
      final scoreB = tagScores[b.id] ?? 0;
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return a.name.compareTo(b.name);
    });

    _suggestedTags = allTags.where((t) => !t.isUntagged).toList();

    // Build subfolder suggestions from papers in current context
    final subfolders = <String, int>{};

    // If we have a tag selected, get subfolders from papers with that tag
    if (widget.contextTag != null) {
      for (final paper in appState.papers) {
        final dir = p.dirname(paper.filePath);
        if (dir != '.' && dir.isNotEmpty) {
          subfolders[dir] = (subfolders[dir] ?? 0) + 1;
        }
      }
    }
    // Also add subfolders from current entry
    if (_selectedEntry != null) {
      for (final key in _selectedEntry!.subfolderCounts.keys) {
        subfolders[key] = (subfolders[key] ?? 0) +
            _selectedEntry!.subfolderCounts[key]!;
      }
    }

    // Sort by frequency
    final sorted = subfolders.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _subfolderSuggestions = sorted.map((e) => e.key).toList();

    // Pre-fill subfolder
    if (widget.contextSubfolder != null) {
      // If context subfolder is in suggestions, select it; otherwise custom mode
      if (!_subfolderSuggestions.contains(widget.contextSubfolder)) {
        _subfolderSuggestions.insert(0, widget.contextSubfolder!);
      }
      _subfolderController.text = widget.contextSubfolder!;
    } else if (widget.contextTag != null &&
        _subfolderSuggestions.isNotEmpty) {
      _subfolderController.text = _subfolderSuggestions.first;
    }
  }

  @override
  void dispose() {
    _subfolderController.dispose();
    super.dispose();
  }

  Future<void> _fetchMetadata() async {
    final arxivId = ArxivService.parseArxivId(widget.arxivUrl ?? '');
    if (arxivId == null) {
      setState(() {
        _isFetchingMetadata = false;
        _error = 'Could not parse arXiv ID from URL';
      });
      return;
    }

    try {
      final metadata = await _arxivService.fetchMetadata(arxivId);
      if (!mounted) return;

      if (metadata == null) {
        setState(() {
          _isFetchingMetadata = false;
          _error = 'Could not fetch metadata for arXiv:$arxivId';
        });
      } else {
        setState(() {
          _metadata = metadata;
          _isFetchingMetadata = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingMetadata = false;
        _error = 'Error fetching metadata: $e';
      });
    }
  }

  String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _download() async {
    if (_metadata == null || _selectedEntry == null) return;

    setState(() => _isDownloading = true);

    try {
      // Build destination path
      var destDir = _selectedEntry!.path;
      final subfolder = _subfolderController.text.trim();
      if (subfolder.isNotEmpty) {
        destDir = p.join(destDir, subfolder);
        await Directory(destDir).create(recursive: true);
      }

      // Download PDF
      final response = await http.get(Uri.parse(_metadata!.pdfUrl));
      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      // Save file
      final sanitizedTitle = _sanitizeFilename(_metadata!.title);
      final fileName = '$sanitizedTitle.pdf';
      final filePath = p.join(destDir, fileName);
      await File(filePath).writeAsBytes(response.bodyBytes);

      // Compute relative path for DB
      final relativePath = p.relative(filePath, from: _selectedEntry!.path);

      // Insert paper into DB
      if (!mounted) return;
      final db = DatabaseService();
      final paper = Paper(
        title: _metadata!.title,
        filePath: relativePath,
        entryId: _selectedEntry!.id!,
        arxivId: _metadata!.arxivId,
        authors: _metadata!.authors,
        abstract: _metadata!.abstract,
        arxivUrl: _metadata!.pdfUrl
            .replaceAll('/pdf/', '/abs/')
            .replaceAll('.pdf', ''),
      );
      final paperId = await db.insertPaper(paper);

      // Assign selected tags
      for (final tagId in _selectedTagIds) {
        await db.addTagToPaper(paperId, tagId);
      }

      // Refresh
      if (!mounted) return;
      final appState = context.read<AppState>();
      await appState.scanAllEntries();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: ${_metadata!.title}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _error = 'Download failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = context.read<AppState>().entries;
    final hasEntries = entries.isNotEmpty;

    return AlertDialog(
      title: const Text('Download from arXiv'),
      content: SizedBox(
        width: 550,
        child: _isFetchingMetadata
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null && _metadata == null
                ? Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error))
                : _buildContent(entries, hasEntries),
      ),
      actions: [
        TextButton(
          onPressed:
              _isDownloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _isDownloading || _metadata == null || !hasEntries
                  ? null
                  : _download,
          child: _isDownloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Download'),
        ),
      ],
    );
  }

  Widget _buildContent(List<Entry> entries, bool hasEntries) {
    final meta = _metadata!;
    final abstractPreview = meta.abstract.length > 200
        ? '${meta.abstract.substring(0, 200)}...'
        : meta.abstract;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            meta.title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Authors
          Text(
            meta.authors,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Abstract
          if (abstractPreview.isNotEmpty)
            Text(
              abstractPreview,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5)),
            ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: colorScheme.error, fontSize: 12)),
          ],

          const Divider(height: 24),

          if (!hasEntries) ...[
            Text('Add an entry folder first',
                style: TextStyle(color: colorScheme.error)),
          ] else ...[
            // Entry picker
            Row(
              children: [
                Text('Entry:', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<Entry>(
                    value: _selectedEntry,
                    isExpanded: true,
                    isDense: true,
                    items: entries.map((entry) {
                      return DropdownMenuItem(
                          value: entry, child: Text(entry.name));
                    }).toList(),
                    onChanged: _isDownloading
                        ? null
                        : (entry) {
                            setState(() {
                              _selectedEntry = entry;
                              _buildSuggestions(context.read<AppState>());
                            });
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Subfolder dropdown with custom option
            Row(
              children: [
                Text('Subfolder:',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                Expanded(
                  child: _isCustomSubfolder
                      ? TextField(
                          controller: _subfolderController,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'Type subfolder name...',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() {
                                _isCustomSubfolder = false;
                                _subfolderController.clear();
                              }),
                            ),
                          ),
                          enabled: !_isDownloading,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : DropdownButton<String>(
                          value: _subfolderSuggestions
                                  .contains(_subfolderController.text)
                              ? _subfolderController.text
                              : '',
                          isExpanded: true,
                          isDense: true,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('(root)',
                                  style: TextStyle(
                                      fontStyle: FontStyle.italic)),
                            ),
                            ..._subfolderSuggestions.map((sf) {
                              return DropdownMenuItem(
                                  value: sf, child: Text(sf));
                            }),
                            const DropdownMenuItem(
                              value: '__custom__',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 14),
                                  SizedBox(width: 6),
                                  Text('New subfolder...'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: _isDownloading
                              ? null
                              : (value) {
                                  if (value == '__custom__') {
                                    setState(() {
                                      _isCustomSubfolder = true;
                                      _subfolderController.clear();
                                    });
                                  } else {
                                    setState(() {
                                      _subfolderController.text = value ?? '';
                                    });
                                  }
                                },
                        ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Tag assignment
            Text('Tags:', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            if (_suggestedTags.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _suggestedTags.take(20).map((tag) {
                      final isSelected =
                          tag.id != null && _selectedTagIds.contains(tag.id);
                      return FilterChip(
                        label: Text(tag.name,
                            style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        visualDensity: VisualDensity.compact,
                        onSelected: _isDownloading
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected && tag.id != null) {
                                    _selectedTagIds.add(tag.id!);
                                  } else if (tag.id != null) {
                                    _selectedTagIds.remove(tag.id!);
                                  }
                                });
                              },
                      );
                    }).toList(),
                  ),
                ),
              )
            else
              Text('No tags yet',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
        ],
      ),
    );
  }
}
