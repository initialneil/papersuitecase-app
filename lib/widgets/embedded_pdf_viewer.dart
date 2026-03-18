import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/paper.dart';
import '../providers/app_state.dart';

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

  // TODO: Remove in Task 9 — reference indexing removed (ReferenceService deleted)
  bool _isIndexing = false;
  OverlayEntry? _tooltipEntry;

  // Annotation mode
  bool _isHighlightMode = false;
  bool _isUnderlineMode = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(EmbeddedPdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _hideTooltip();
    _controller.dispose();
    super.dispose();
  }

  void _hideTooltip() {
    _tooltipEntry?.remove();
    _tooltipEntry = null;
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
            child: SfPdfViewer.file(
              File(context.read<AppState>().resolveFullPath(widget.paper)),
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
