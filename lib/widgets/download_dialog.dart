import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../models/paper.dart';
import '../providers/app_state.dart';
import '../database/database_service.dart';
import '../services/arxiv_service.dart';

/// Dialog for downloading papers from arXiv
class DownloadDialog extends StatefulWidget {
  final String? arxivUrl;

  const DownloadDialog({super.key, this.arxivUrl});

  static Future<void> show(BuildContext context, {String? arxivUrl}) {
    return showDialog(
      context: context,
      builder: (context) => DownloadDialog(arxivUrl: arxivUrl),
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

  @override
  void initState() {
    super.initState();
    _fetchMetadata();
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
        final entries = context.read<AppState>().entries;
        setState(() {
          _metadata = metadata;
          _isFetchingMetadata = false;
          if (entries.isNotEmpty) {
            _selectedEntry = entries.first;
          }
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
    // Remove or replace characters that are problematic in filenames
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

      // Download PDF bytes
      final response = await http.get(Uri.parse(_metadata!.pdfUrl));
      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      // Save with sanitized filename
      final sanitizedTitle = _sanitizeFilename(_metadata!.title);
      final fileName = '$sanitizedTitle.pdf';
      final filePath = p.join(destDir, fileName);
      await File(filePath).writeAsBytes(response.bodyBytes);

      // Insert paper into DB with metadata
      if (!mounted) return;
      final db = DatabaseService();
      final paper = Paper(
        title: _metadata!.title,
        filePath: filePath,
        entryId: _selectedEntry!.id!,
        arxivId: _metadata!.arxivId,
        authors: _metadata!.authors,
        abstract: _metadata!.abstract,
        arxivUrl: _metadata!.pdfUrl.replaceAll('/pdf/', '/abs/').replaceAll('.pdf', ''),
      );
      await db.insertPaper(paper);

      // Refresh entries
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
        width: 500,
        child: _isFetchingMetadata
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null && _metadata == null
                ? Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                : _buildContent(entries, hasEntries),
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isDownloading || _metadata == null || !hasEntries
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
    final abstractPreview = meta.abstract.length > 300
        ? '${meta.abstract.substring(0, 300)}...'
        : meta.abstract;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          meta.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),

        // Authors
        Text(
          meta.authors,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),

        // Abstract preview
        if (abstractPreview.isNotEmpty) ...[
          Text(
            abstractPreview,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 16),
        ],

        // Error message (non-fatal, e.g. download retry)
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],

        const Divider(),
        const SizedBox(height: 8),

        if (!hasEntries) ...[
          Text(
            'Add an entry folder first',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ] else ...[
          // Entry picker
          const Text('Save to entry:'),
          const SizedBox(height: 8),
          DropdownButton<Entry>(
            value: _selectedEntry,
            isExpanded: true,
            items: entries.map((entry) {
              return DropdownMenuItem(
                value: entry,
                child: Text(entry.name),
              );
            }).toList(),
            onChanged: _isDownloading
                ? null
                : (entry) => setState(() => _selectedEntry = entry),
          ),
          const SizedBox(height: 12),

          // Subfolder field
          TextField(
            controller: _subfolderController,
            decoration: const InputDecoration(
              labelText: 'Subfolder (optional)',
              hintText: 'e.g. transformers/attention',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            enabled: !_isDownloading,
          ),
        ],
      ],
    );
  }
}
