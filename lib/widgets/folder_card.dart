import 'package:flutter/material.dart';
import 'dart:io';
import '../models/paper_folder.dart';
import '../models/paper.dart';
import '../services/pdf_service.dart';

class FolderCard extends StatelessWidget {
  final PaperFolder folder;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const FolderCard({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Folder Visual
              SizedBox(
                width: 70,
                height: 60,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (folder.previewPapers.isEmpty)
                      // Empty state
                      Icon(
                        folder.isSymbolic
                            ? Icons.folder_shared_outlined
                            : Icons.folder_outlined,
                        size: 48,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.4),
                      )
                    else ...[
                      // Papers sticking out (Back to Front)
                      if (folder.previewPapers.length >= 3)
                        Positioned(
                          top: 4,
                          right: 14,
                          child: Transform.rotate(
                            angle: 0.15,
                            child: _TinyPaperPreview(
                              paper: folder.previewPapers[2],
                              size: 44,
                              opacity: 0.8,
                            ),
                          ),
                        ),
                      if (folder.previewPapers.length >= 2)
                        Positioned(
                          top: 6,
                          child: Transform.rotate(
                            angle: -0.05,
                            child: _TinyPaperPreview(
                              paper: folder.previewPapers[1],
                              size: 46,
                              opacity: 0.9,
                            ),
                          ),
                        ),
                      if (folder.previewPapers.isNotEmpty)
                        Positioned(
                          top: 8,
                          left: 14,
                          child: Transform.rotate(
                            angle: -0.2,
                            child: _TinyPaperPreview(
                              paper: folder.previewPapers[0],
                              size: 48,
                              opacity: 1.0,
                            ),
                          ),
                        ),

                      // Folder Icon Overlay (Front)
                      Positioned(
                        bottom: -2,
                        child: Icon(
                          folder.isSymbolic
                              ? Icons.folder_shared
                              : Icons.folder,
                          size: 60,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${folder.paperCount} papers',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyPaperPreview extends StatefulWidget {
  final Paper paper;
  final double size;
  final double opacity;

  const _TinyPaperPreview({
    required this.paper,
    required this.size,
    this.opacity = 1.0,
  });

  @override
  State<_TinyPaperPreview> createState() => _TinyPaperPreviewState();
}

class _TinyPaperPreviewState extends State<_TinyPaperPreview> {
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (widget.paper.id == null) return;

    // Use the service to check/generate thumbnail
    // This assumes PdfService handles caching/checking existence efficiently
    Future.microtask(() async {
      if (!mounted) return;
      // We don't want to force generate if not exists for tiny preview to save perf?
      // Or just try. PdfService usually returns existing path.
      final path = await PdfService.generateThumbnail(
        widget.paper.filePath,
        widget.paper.id!,
      );
      if (mounted && path != null) {
        setState(() => _thumbnailPath = path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size * 0.77, // A4 ratio
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: widget.opacity),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        image: _thumbnailPath != null
            ? DecorationImage(
                image: FileImage(File(_thumbnailPath!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: _thumbnailPath == null
          ? Center(
              child: Icon(
                Icons.article,
                size: widget.size * 0.6,
                color: Colors.grey.withValues(alpha: 0.5),
              ),
            )
          : null,
    );
  }
}
