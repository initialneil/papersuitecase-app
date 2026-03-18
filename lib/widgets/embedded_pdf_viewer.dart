import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/paper.dart';
import '../services/reference_service.dart';
import '../providers/app_state.dart';
import 'paper_card.dart';

class EmbeddedPdfViewer extends StatefulWidget {
  final Paper paper;
  final VoidCallback onBack;

  const EmbeddedPdfViewer({
    super.key,
    required this.paper,
    required this.onBack,
  });

  @override
  State<EmbeddedPdfViewer> createState() => _EmbeddedPdfViewerState();
}

class _EmbeddedPdfViewerState extends State<EmbeddedPdfViewer> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  List<ReferenceInfo> _references = [];
  bool _isIndexing = false;
  OverlayEntry? _tooltipEntry;

  // Annotation mode
  bool _isHighlightMode = false;
  bool _isUnderlineMode = false;

  @override
  void initState() {
    super.initState();
    _indexReferences();
  }

  @override
  void didUpdateWidget(EmbeddedPdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper.filePath != widget.paper.filePath) {
      _indexReferences();
    }
  }

  @override
  void dispose() {
    _hideTooltip();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _indexReferences() async {
    setState(() => _isIndexing = true);
    try {
      debugPrint('🔍 Indexing references for ${widget.paper.title}...');
      final refs = await ReferenceService.extractReferences(
        widget.paper.filePath,
      );
      if (!mounted) return;

      debugPrint('📚 Extracted ${refs.length} bibliography entries');

      if (mounted) {
        setState(() {
          _references = refs;
        });
      }
    } catch (e) {
      debugPrint('❌ Error indexing: $e');
    } finally {
      if (mounted) {
        setState(() => _isIndexing = false);
      }
    }
  }

  void _hideTooltip() {
    _tooltipEntry?.remove();
    _tooltipEntry = null;
  }

  Future<void> _handleRightClick(Offset position) async {
    if (_references.isEmpty) return;

    // Since we can't detect which specific reference was clicked,
    // let's provide a smarter menu:
    // 1. If there's only one reference, show it directly
    // 2. Otherwise, show the selection menu

    if (_references.length == 1) {
      // Auto-show the only reference
      final ref = _references[0];
      final appState = context.read<AppState>();
      final Paper? foundPaper = await appState.getPaperByTitle(ref.title);
      if (mounted) {
        _showTooltip(ref, position, foundPaper);
      }
    } else {
      // Show selection menu for multiple references
      _showReferenceSelectionMenu(position, 'Select Reference');
    }
  }

  void _showReferenceSelectionMenu(Offset position, String title) {
    if (_references.isEmpty) return;

    String searchQuery = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final filteredRefs = searchQuery.isEmpty
              ? _references
              : _references.where((ref) {
                  final query = searchQuery.toLowerCase();
                  return ref.marker.toLowerCase().contains(query) ||
                      ref.title.toLowerCase().contains(query);
                }).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.search, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(title)),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by number or title...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => searchQuery = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${filteredRefs.length} reference${filteredRefs.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredRefs.isEmpty
                        ? const Center(
                            child: Text(
                              'No references found',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredRefs.length,
                            itemBuilder: (context, index) {
                              final ref = filteredRefs[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      ref.marker,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    ref.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  onTap: () async {
                                    Navigator.of(context).pop();
                                    final appState = context.read<AppState>();
                                    final Paper? foundPaper = await appState
                                        .getPaperByTitle(ref.title);
                                    if (mounted) {
                                      _showTooltip(ref, position, foundPaper);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTooltip(ReferenceInfo info, Offset position, Paper? foundPaper) {
    _hideTooltip();

    _tooltipEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideTooltip,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: position.dx + 10,
              top: position.dy + 10,
              child: GestureDetector(
                onTap: () {
                  if (foundPaper != null) {
                    _hideTooltip();
                    context.read<AppState>().openPaper(foundPaper);
                  }
                },
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: foundPaper != null
                      ? Container(
                          width: 280,
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: PaperCard(
                            paper: foundPaper,
                            isSelected: false,
                            onTap: () {
                              _hideTooltip();
                              context.read<AppState>().openPaper(foundPaper);
                            },
                          ),
                        )
                      : _buildInfoCard(info),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_tooltipEntry!);
  }

  Widget _buildInfoCard(ReferenceInfo info) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (info.authors != null) ...[
            const SizedBox(height: 8),
            Text(
              info.authors!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 14,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'Not in Suitecase',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(
          widget.paper.title,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.highlight,
              color: _isHighlightMode ? Colors.amber : null,
            ),
            tooltip: 'Highlight',
            onPressed: () {
              setState(() {
                _isHighlightMode = !_isHighlightMode;
                if (_isHighlightMode) _isUnderlineMode = false;
              });
            },
          ),
          IconButton(
            icon: Icon(
              Icons.format_underline,
              color: _isUnderlineMode ? Colors.blue : null,
            ),
            tooltip: 'Underline',
            onPressed: () {
              setState(() {
                _isUnderlineMode = !_isUnderlineMode;
                if (_isUnderlineMode) _isHighlightMode = false;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () =>
                _controller.zoomLevel = _controller.zoomLevel + 0.25,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () =>
                _controller.zoomLevel = _controller.zoomLevel - 0.25,
          ),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onSecondaryTapDown: (details) {
              if (!_isHighlightMode && !_isUnderlineMode) {
                _handleRightClick(details.localPosition);
              }
            },
            child: SfPdfViewer.file(
              File(widget.paper.filePath),
              key: _pdfViewerKey,
              controller: _controller,
              enableHyperlinkNavigation: false, // Prevent automatic jumping
              onTextSelectionChanged: (details) {
                if (_isHighlightMode || _isUnderlineMode) {
                  // Apply annotation
                  if (details.selectedText != null &&
                      details.selectedText!.isNotEmpty) {
                    // Note: Syncfusion requires premium license for annotation features
                    // For now, we'll just log it
                    debugPrint(
                      '${_isHighlightMode ? "Highlight" : "Underline"}: ${details.selectedText}',
                    );
                  }
                }
              },
            ),
          ),
          if (_isIndexing)
            Positioned(
              bottom: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Indexing references...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isHighlightMode || _isUnderlineMode)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  color: _isHighlightMode ? Colors.amber : Colors.blue,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      '${_isHighlightMode ? "Highlight" : "Underline"} mode - Select text to annotate',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Instruction banner
          if (!_isHighlightMode && !_isUnderlineMode && !_isIndexing)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.mouse, size: 16, color: Colors.white70),
                        SizedBox(width: 8),
                        Text(
                          'Right-click on any reference to view paper card',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
