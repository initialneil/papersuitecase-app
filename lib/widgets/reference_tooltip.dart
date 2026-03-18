import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/paper.dart';
import '../providers/app_state.dart';
import '../services/pdf_service.dart';

class ReferenceTooltip extends StatelessWidget {
  final String title;
  final String? authors;
  final Function(Paper?)? onPaperTapped;

  const ReferenceTooltip({
    super.key,
    required this.title,
    this.authors,
    this.onPaperTapped,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paper?>(
      future: context.read<AppState>().getPaperByTitle(title),
      builder: (context, snapshot) {
        final paper = snapshot.data;
        final hasPaper = paper != null;

        final content = Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasPaper) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _PaperPreview(paper: paper),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (authors != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    authors!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (hasPaper) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            onPaperTapped != null
                                ? 'Click to open'
                                : 'In Suitecase',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

        // If we have a paper and a callback, make it clickable
        if (hasPaper && onPaperTapped != null) {
          return GestureDetector(
            onTap: () => onPaperTapped!(paper),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: content,
            ),
          );
        }

        return content;
      },
    );
  }
}

class _PaperPreview extends StatelessWidget {
  final Paper paper;

  const _PaperPreview({required this.paper});

  @override
  Widget build(BuildContext context) {
    // We try to find the thumbnail
    return FutureBuilder<String?>(
      future: _getThumbnail(paper.id!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 150,
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final thumbPath = snapshot.data;
        if (thumbPath != null && File(thumbPath).existsSync()) {
          return Image.file(
            File(thumbPath),
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
          );
        }

        return Container(
          height: 150,
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.article_outlined,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        );
      },
    );
  }

  Future<String?> _getThumbnail(int paperId) async {
    final thumbDir = await PdfService.thumbnailDirectory;
    final path = '$thumbDir/$paperId.png';
    if (await File(path).exists()) return path;
    return null;
  }
}
