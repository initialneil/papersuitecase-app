import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';

import '../models/paper.dart';
import '../providers/app_state.dart';
import '../services/bibtex_service.dart';

/// Extracts the citation key from a BibTeX string.
String? _extractCitationKey(String? bibtex) {
  if (bibtex == null || bibtex.isEmpty) return null;
  final match = RegExp(r'@\w+\{(\w+),').firstMatch(bibtex);
  return match?.group(1);
}

/// Tag-scoped BibTeX management panel.
class BibtexPanel extends StatefulWidget {
  final List<Paper> papers;

  const BibtexPanel({super.key, required this.papers});

  @override
  State<BibtexPanel> createState() => _BibtexPanelState();
}

class _BibtexPanelState extends State<BibtexPanel> {
  bool _isBatchFetching = false;
  int _fetchProgress = 0;
  int _fetchTotal = 0;
  final Set<int> _fetchingIds = {};

  int get _hasBibtexCount =>
      widget.papers.where((p) => p.bibtex != null && p.bibtex!.isNotEmpty).length;

  int get _missingCount => widget.papers.length - _hasBibtexCount;

  Future<void> _autoFetchSingle(Paper paper) async {
    if (paper.id == null) return;
    setState(() => _fetchingIds.add(paper.id!));
    try {
      final bib = await BibtexService.autoFetch(paper);
      if (bib != null && mounted) {
        await context
            .read<AppState>()
            .updatePaperBibtex(paper.id!, bib, 'auto_fetched');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('BibTeX fetched successfully'),
                duration: Duration(seconds: 2)),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not find BibTeX for this paper'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fetch failed: $e'),
              duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingIds.remove(paper.id!));
    }
  }

  Future<void> _batchFetch() async {
    final appState = context.read<AppState>();
    setState(() {
      _isBatchFetching = true;
      _fetchProgress = 0;
      _fetchTotal =
          widget.papers.where((p) => p.bibtex == null || p.bibtex!.isEmpty).length;
    });

    try {
      final results = await BibtexService.batchAutoFetch(
        widget.papers,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _fetchProgress = completed;
              _fetchTotal = total;
            });
          }
        },
      );

      for (final entry in results.entries) {
        await appState.updatePaperBibtex(entry.key, entry.value, 'auto_fetched');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Fetched BibTeX for ${results.length} paper(s)'),
              duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Batch fetch error: $e'),
              duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchFetching = false);
    }
  }

  Future<void> _verifyPaper(Paper paper) async {
    if (paper.id == null) return;
    await context
        .read<AppState>()
        .updatePaperBibtex(paper.id!, paper.bibtex!, 'verified');
  }

  void _copyAllBibtex() {
    final combined = BibtexService.exportBibtex(widget.papers);
    if (combined.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No BibTeX to copy'),
            duration: Duration(seconds: 2)),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: combined));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('All BibTeX copied to clipboard'),
          duration: Duration(seconds: 2)),
    );
  }

  Future<void> _exportBibFile() async {
    final combined = BibtexService.exportBibtex(widget.papers);
    if (combined.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No BibTeX to export'),
            duration: Duration(seconds: 2)),
      );
      return;
    }

    final location = await getSaveLocation(
      suggestedName: 'references.bib',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'BibTeX', extensions: ['bib']),
      ],
    );
    if (location == null) return;

    final file = File(location.path);
    await file.writeAsString(combined);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Exported to ${location.path}'),
            duration: const Duration(seconds: 3)),
      );
    }
  }

  Widget _buildStatusIcon(Paper paper) {
    if (paper.bibtex != null && paper.bibtex!.isNotEmpty) {
      if (paper.bibStatus == 'verified') {
        return const Tooltip(
          message: 'Verified',
          child: Icon(Icons.check_circle, color: Colors.green, size: 18),
        );
      }
      return const Tooltip(
        message: 'Auto-fetched',
        child: Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
      );
    }
    return const Tooltip(
      message: 'Missing',
      child: Icon(Icons.cancel, color: Colors.red, size: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with status and action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.papers.length} papers \u2014 '
                    '$_hasBibtexCount have BibTeX, $_missingCount missing',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_isBatchFetching) ...[
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: _fetchTotal > 0 ? _fetchProgress / _fetchTotal : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_fetchProgress/$_fetchTotal',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 4),
                ] else ...[
                  _ActionButton(
                    icon: Icons.cloud_download_outlined,
                    tooltip: 'Batch Fetch Missing',
                    onPressed: _missingCount > 0 ? _batchFetch : null,
                  ),
                  _ActionButton(
                    icon: Icons.copy_all,
                    tooltip: 'Copy All BibTeX',
                    onPressed: _hasBibtexCount > 0 ? _copyAllBibtex : null,
                  ),
                  _ActionButton(
                    icon: Icons.save_alt,
                    tooltip: 'Export .bib',
                    onPressed: _hasBibtexCount > 0 ? _exportBibFile : null,
                  ),
                ],
              ],
            ),
          ),

          // Paper rows
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: widget.papers.length,
              separatorBuilder: (_, _2) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final paper = widget.papers[index];
                final citKey = _extractCitationKey(paper.bibtex);
                final hasBib = paper.bibtex != null && paper.bibtex!.isNotEmpty;
                final isFetching =
                    paper.id != null && _fetchingIds.contains(paper.id!);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      _buildStatusIcon(paper),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          paper.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (citKey != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            citKey,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _ActionButton(
                          icon: Icons.copy,
                          tooltip: 'Copy citation key',
                          size: 16,
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: citKey));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Copied: $citKey'),
                                  duration: const Duration(seconds: 1)),
                            );
                          },
                        ),
                      ],
                      const SizedBox(width: 4),
                      if (isFetching)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (!hasBib)
                        _ActionButton(
                          icon: Icons.cloud_download_outlined,
                          tooltip: 'Fetch BibTeX',
                          size: 16,
                          onPressed: () => _autoFetchSingle(paper),
                        )
                      else if (paper.bibStatus == 'auto_fetched')
                        _ActionButton(
                          icon: Icons.verified_outlined,
                          tooltip: 'Mark as verified',
                          size: 16,
                          onPressed: () => _verifyPaper(paper),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small icon button used in the panel.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: size),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}
