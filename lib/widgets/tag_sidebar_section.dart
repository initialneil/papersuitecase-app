import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../models/tag.dart';

/// Sidebar section displaying hierarchical tag tree with Untagged item.
class TagSidebarSection extends StatelessWidget {
  const TagSidebarSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final tagTree = appState.tagTree;

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
                  'TAGS',
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
                  tooltip: 'New Tag',
                  onPressed: () => _showAddTagDialog(context, appState),
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

        // Tag tree
        ...tagTree.map(
          (tag) => _TagTreeItem(
            tag: tag,
            level: 0,
            selectedTag: appState.selectedTag,
            onTap: () => appState.selectTag(tag),
            onToggleExpand: () => appState.toggleTagExpansion(tag),
          ),
        ),

        // Untagged item
        _UntaggedItem(
          count: appState.untaggedCount,
          isSelected: appState.selectedTag?.isUntagged == true,
          onTap: () => appState.selectTag(Tag.untagged(
            paperCount: appState.untaggedCount,
          )),
        ),
      ],
    );
  }

  void _showAddTagDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tag name',
            hintText: 'Enter tag name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              appState.createTag(value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                appState.createTag(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Untagged papers item at the bottom of the tag section.
class _UntaggedItem extends StatelessWidget {
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _UntaggedItem({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 8,
            top: 8,
            bottom: 8,
          ),
          child: Row(
            children: [
              const SizedBox(width: 22), // align with tree items
              const SizedBox(width: 4),
              Icon(
                Icons.label_off_outlined,
                size: 18,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Untagged',
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count > 0)
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
                    '$count',
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
    );
  }
}

/// Single tag tree item with expand/collapse, context menu, and drag target.
class _TagTreeItem extends StatelessWidget {
  final Tag tag;
  final int level;
  final Tag? selectedTag;
  final VoidCallback onTap;
  final VoidCallback onToggleExpand;

  const _TagTreeItem({
    required this.tag,
    required this.level,
    required this.selectedTag,
    required this.onTap,
    required this.onToggleExpand,
  });

  bool get isSelected => selectedTag?.id == tag.id;
  bool get hasChildren => tag.children.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();

    // Wrap in DragTarget to accept paper drops
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => tag.id != null,
      onAcceptWithDetails: (details) {
        appState.addTagToSelectedPapers(tag);
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: isDropTarget
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.15)
                  : isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3)
                      : Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (hasChildren) {
                    if (isSelected && tag.isExpanded) {
                      onToggleExpand();
                    } else {
                      onTap();
                      if (!tag.isExpanded) {
                        onToggleExpand();
                      }
                    }
                  } else {
                    onTap();
                  }
                },
                onSecondaryTapUp: (details) =>
                    _showContextMenu(context, appState, details.globalPosition),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16.0 + (level * 16),
                    right: 8,
                    top: 8,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      // Expand/collapse button
                      if (hasChildren)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onToggleExpand,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              tag.isExpanded
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

                      // Tag icon
                      Icon(
                        Icons.label_outline,
                        size: 18,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                      ),

                      const SizedBox(width: 8),

                      // Tag name
                      Expanded(
                        child: Text(
                          tag.name,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Paper count
                      if (tag.paperCount > 0)
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
                            '${tag.paperCount}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
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

            // Children
            if (tag.isExpanded && hasChildren)
              ...tag.children.map(
                (child) => _TagTreeItem(
                  tag: child,
                  level: level + 1,
                  selectedTag: selectedTag,
                  onTap: () => appState.selectTag(child),
                  onToggleExpand: () => appState.toggleTagExpansion(child),
                ),
              ),
          ],
        );
      },
    );
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
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showRenameDialog(context, appState);
              }
            });
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Add child tag'),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showAddChildDialog(context, appState);
              }
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
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showDeleteConfirmation(context, appState);
              }
            });
          },
        ),
      ],
    );
  }

  void _showRenameDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController(text: tag.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              appState.renameTag(tag.id!, value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                appState.renameTag(tag.id!, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showAddChildDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add child to "${tag.name}"'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tag name',
            hintText: 'Enter child tag name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              appState.createTag(value.trim(), parentId: tag.id);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                appState.createTag(controller.text.trim(), parentId: tag.id);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tag'),
        content: Text(
          'Are you sure you want to delete "${tag.name}"? '
          'Papers with this tag will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.deleteTag(tag.id!);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
