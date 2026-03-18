import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import '../models/entry.dart';
import '../providers/app_state.dart';
import '../services/pdf_service.dart';

/// Full-window drop zone overlay
class DropZone extends StatefulWidget {
  final Widget child;

  const DropZone({
    super.key,
    required this.child,
  });

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _isDragging = false;
  bool _isFolder = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
          _isFolder = false;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
          _isFolder = false;
        });
      },
      onDragDone: (details) async {
        setState(() {
          _isDragging = false;
          _isFolder = false;
        });

        await _handleDrop(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragging)
            Positioned.fill(child: _DropOverlay(isFolder: _isFolder)),
        ],
      ),
    );
  }

  Future<void> _handleDrop(List<XFile> files) async {
    if (files.isEmpty) return;
    if (!mounted) return;

    final appState = context.read<AppState>();

    final pdfPaths = <String>[];
    String? folderPath;

    for (final file in files) {
      final path = file.path;

      // Check if it's a directory
      if (await FileSystemEntity.isDirectory(path)) {
        folderPath = path;
        break; // Only handle one folder at a time
      } else if (PdfService.isPdf(path)) {
        pdfPaths.add(path);
      }
    }

    if (folderPath != null) {
      // Folder drop: create an entry directly
      await appState.addEntry(folderPath);
    } else if (pdfPaths.isNotEmpty) {
      // PDF drop: show entry picker or snackbar
      if (!mounted) return;
      _handlePdfDrop(pdfPaths, appState);
    }
  }

  void _handlePdfDrop(List<String> pdfPaths, AppState appState) {
    final entries = appState.entries;

    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drop a folder to create an entry first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Show a dialog to pick which entry to copy the PDF(s) into
    showDialog(
      context: context,
      builder: (ctx) => _PdfEntryPickerDialog(
        pdfPaths: pdfPaths,
        entries: entries,
        appState: appState,
      ),
    );
  }
}

/// Dialog to pick an entry folder for dropped PDF files
class _PdfEntryPickerDialog extends StatefulWidget {
  final List<String> pdfPaths;
  final List<Entry> entries;
  final AppState appState;

  const _PdfEntryPickerDialog({
    required this.pdfPaths,
    required this.entries,
    required this.appState,
  });

  @override
  State<_PdfEntryPickerDialog> createState() => _PdfEntryPickerDialogState();
}

class _PdfEntryPickerDialogState extends State<_PdfEntryPickerDialog> {
  Entry? _selectedEntry;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    if (widget.entries.isNotEmpty) {
      _selectedEntry = widget.entries.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.pdfPaths.length;
    final fileLabel = count == 1
        ? p.basename(widget.pdfPaths.first)
        : '$count PDF files';

    return AlertDialog(
      title: const Text('Copy PDF to Entry'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Copy $fileLabel into:'),
          const SizedBox(height: 12),
          DropdownButton<Entry>(
            value: _selectedEntry,
            isExpanded: true,
            items: widget.entries.map((entry) {
              return DropdownMenuItem(
                value: entry,
                child: Text(entry.name),
              );
            }).toList(),
            onChanged: _isCopying
                ? null
                : (entry) => setState(() => _selectedEntry = entry),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCopying ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isCopying || _selectedEntry == null ? null : _copyFiles,
          child: _isCopying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Copy'),
        ),
      ],
    );
  }

  Future<void> _copyFiles() async {
    if (_selectedEntry == null) return;

    setState(() => _isCopying = true);

    try {
      final destDir = _selectedEntry!.path;
      for (final sourcePath in widget.pdfPaths) {
        final fileName = p.basename(sourcePath);
        final destPath = p.join(destDir, fileName);
        await File(sourcePath).copy(destPath);
      }

      // Trigger rescan to pick up new files
      await widget.appState.scanAllEntries();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Copied ${widget.pdfPaths.length} file(s) to ${_selectedEntry!.name}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error copying files: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }
}

/// Visual overlay shown during drag
class _DropOverlay extends StatelessWidget {
  final bool isFolder;

  const _DropOverlay({required this.isFolder});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
              style: BorderStyle.solid,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFolder ? Icons.folder_open : Icons.file_download_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                isFolder
                    ? 'Drop folder to add as entry'
                    : 'Drop PDF files to add to an entry',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFolder
                    ? 'Folder will be linked as an entry'
                    : 'Choose which entry to copy files into',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
