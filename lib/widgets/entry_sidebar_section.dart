import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';

import '../providers/app_state.dart';
import '../models/entry.dart';
import '../services/pdf_service.dart';

/// Sidebar section displaying entries (folder references) with subfolder trees.
class EntrySidebarSection extends StatelessWidget {
  const EntrySidebarSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final entries = appState.entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'ENTRIES',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'Add Entry',
                  onPressed: () => _addEntry(context, appState),
                  icon: Icon(
                    Icons.add,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Entry list
        ...entries.map(
          (entry) => _EntryTreeItem(
            entry: entry,
            selectedEntry: appState.selectedEntry,
            selectedSubfolder: appState.selectedSubfolder,
          ),
        ),

        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No entries yet',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _addEntry(BuildContext context, AppState appState) async {
    final directoryPath = await getDirectoryPath(
      confirmButtonText: 'Add Entry',
    );
    if (directoryPath != null) {
      await appState.addEntry(directoryPath);
    }
  }
}

/// A single entry item with expandable subfolder tree.
class _EntryTreeItem extends StatelessWidget {
  final Entry entry;
  final Entry? selectedEntry;
  final String? selectedSubfolder;

  const _EntryTreeItem({
    required this.entry,
    required this.selectedEntry,
    required this.selectedSubfolder,
  });

  bool get isSelected =>
      selectedEntry?.id == entry.id && selectedSubfolder == null;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final hasSubfolders = entry.subfolderCounts.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Entry row
        GestureDetector(
          onSecondaryTapUp: (details) =>
              _showContextMenu(context, appState, details.globalPosition),
          child: Material(
            color: isSelected
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3)
                : Colors.transparent,
            child: InkWell(
              onTap: () {
                if (hasSubfolders) {
                  if (isSelected && entry.isExpanded) {
                    appState.toggleEntryExpansion(entry);
                  } else {
                    appState.selectEntry(entry);
                    if (!entry.isExpanded) {
                      appState.toggleEntryExpansion(entry);
                    }
                  }
                } else {
                  appState.selectEntry(entry);
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 8,
                  top: 8,
                  bottom: 8,
                ),
                child: Row(
                  children: [
                    // Expand/collapse
                    if (hasSubfolders)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => appState.toggleEntryExpansion(entry),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            entry.isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 22),

                    const SizedBox(width: 4),

                    // Folder icon (with warning if inaccessible)
                    if (!entry.isAccessible)
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      )
                    else
                      Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                      ),

                    const SizedBox(width: 8),

                    // Entry name
                    Expanded(
                      child: Text(
                        entry.name,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                          color: !entry.isAccessible
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.4)
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Paper count
                    if (entry.paperCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.2)
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${entry.paperCount}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Subfolder children (when expanded)
        if (entry.isExpanded && hasSubfolders)
          ..._buildSubfolderItems(context, appState),
      ],
    );
  }

  List<Widget> _buildSubfolderItems(BuildContext context, AppState appState) {
    final sortedSubfolders = entry.subfolderCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return sortedSubfolders.map((subfolder) {
      final isSubfolderSelected = selectedEntry?.id == entry.id &&
          selectedSubfolder == subfolder.key;

      return Material(
        color: isSubfolderSelected
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3)
            : Colors.transparent,
        child: InkWell(
          onTap: () =>
              appState.selectEntry(entry, subfolder: subfolder.key),
          child: Padding(
            padding: const EdgeInsets.only(
              left: 48, // indent for subfolder
              right: 8,
              top: 6,
              bottom: 6,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right,
                  size: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: isSubfolderSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subfolder.key,
                    style: TextStyle(
                      fontWeight: isSubfolderSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subfolder.value > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isSubfolderSelected
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.2)
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${subfolder.value}',
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: isSubfolderSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  void _showContextMenu(
    BuildContext context,
    AppState appState,
    Offset position,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 8),
              Text('Refresh'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              appState.refreshEntry(entry);
            });
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder_open_outlined, size: 18),
              SizedBox(width: 8),
              Text('Reveal in Finder'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              PdfService.revealInFinder(entry.path);
            });
          },
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Remove Entry',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showRemoveConfirmation(context, appState);
              }
            });
          },
        ),
      ],
    );
  }

  void _showRemoveConfirmation(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Entry'),
        content: Text(
          'Remove "${entry.name}" from the library? '
          'The original files on disk will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.removeEntry(entry.id!);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
