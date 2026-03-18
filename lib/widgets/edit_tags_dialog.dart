import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import '../providers/app_state.dart';

class EditTagsDialog extends StatefulWidget {
  final List<int> paperIds;

  const EditTagsDialog({super.key, required this.paperIds});

  @override
  State<EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends State<EditTagsDialog> {
  List<Tag> _allTags = [];
  Set<int> _selectedTagIds = {};
  Set<int> _partiallySelectedTagIds = {}; // For multi-selection
  bool _isLoading = true;
  final TextEditingController _newTagController = TextEditingController();
  List<Tag> _suggestedTags = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _newTagController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _newTagController.removeListener(_onSearchChanged);
    _newTagController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _newTagController.text.toLowerCase();
      _updateSuggestions();
    });
  }

  void _updateSuggestions() {
    if (_searchQuery.isEmpty) {
      // Show unselected tags, limited to first 15
      _suggestedTags = _allTags
          .where((tag) => !_selectedTagIds.contains(tag.id))
          .take(15)
          .toList();
    } else {
      // Fuzzy search: match tags containing the search query
      _suggestedTags = _allTags
          .where((tag) {
            final tagLower = tag.name.toLowerCase();
            return tagLower.contains(_searchQuery) &&
                !_selectedTagIds.contains(tag.id);
          })
          .take(15)
          .toList();
    }
  }

  Future<void> _loadData() async {
    final appState = context.read<AppState>();

    // Get all tags
    final allTags = await appState.getAllTags();

    // Get tags for each selected paper
    final tagsByPaper = <int, Set<int>>{};
    for (final paperId in widget.paperIds) {
      final tags = await appState.getTagsForPaper(paperId);
      tagsByPaper[paperId] = tags.map((t) => t.id!).toSet();
    }

    // Determine which tags are selected by all papers, some papers, or none
    if (widget.paperIds.length == 1) {
      // Single selection - simple case
      _selectedTagIds = tagsByPaper[widget.paperIds.first] ?? {};
    } else {
      // Multi-selection - need to find common tags
      final firstPaperTags = tagsByPaper[widget.paperIds.first] ?? {};
      final allPaperTags = tagsByPaper.values.toSet();

      for (final tagId in allTags.map((t) => t.id!)) {
        final papersWithTag = tagsByPaper.values
            .where((tags) => tags.contains(tagId))
            .length;

        if (papersWithTag == widget.paperIds.length) {
          // All papers have this tag
          _selectedTagIds.add(tagId);
        } else if (papersWithTag > 0) {
          // Some papers have this tag
          _partiallySelectedTagIds.add(tagId);
        }
      }
    }

    if (mounted) {
      setState(() {
        _allTags = allTags;
        _isLoading = false;
        _updateSuggestions();
      });
    }
  }

  Future<void> _createTag(String name) async {
    if (name.trim().isEmpty) return;

    final appState = context.read<AppState>();
    final newTag = await appState.createTag(name.trim());
    await _loadData();

    // Auto-select the newly created tag
    setState(() {
      _selectedTagIds.add(newTag.id!);
      _newTagController.clear();
    });
  }

  void _addExistingTag(Tag tag) {
    setState(() {
      _selectedTagIds.add(tag.id!);
      _partiallySelectedTagIds.remove(tag.id);
      _newTagController.clear();
      _updateSuggestions();
    });
  }

  void _toggleTag(int tagId) {
    setState(() {
      if (_selectedTagIds.contains(tagId)) {
        _selectedTagIds.remove(tagId);
      } else {
        _selectedTagIds.add(tagId);
        _partiallySelectedTagIds.remove(tagId); // Remove from partial if exists
      }
      _updateSuggestions();
    });
  }

  Future<void> _save() async {
    final appState = context.read<AppState>();

    // For each paper, set the selected tags
    for (final paperId in widget.paperIds) {
      await appState.setTagsForPaper(paperId, _selectedTagIds.toList());
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMultiSelect = widget.paperIds.length > 1;

    return AlertDialog(
      title: Text(
        isMultiSelect
            ? 'Edit Tags (${widget.paperIds.length} papers)'
            : 'Edit Tags',
      ),
      content: SizedBox(
        width: 500,
        height: 600,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add new tag field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newTagController,
                          decoration: const InputDecoration(
                            hintText: 'Search or create tag...',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (value) {
                            if (value.trim().isEmpty) return;
                            // Check if exact match exists
                            final existingTag = _allTags
                                .cast<Tag?>()
                                .firstWhere(
                                  (t) =>
                                      t?.name.toLowerCase() ==
                                      value.trim().toLowerCase(),
                                  orElse: () => null,
                                );
                            if (existingTag != null) {
                              _addExistingTag(existingTag);
                            } else {
                              _createTag(value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () {
                          final value = _newTagController.text.trim();
                          if (value.isEmpty) return;
                          // Check if exact match exists
                          final existingTag = _allTags.cast<Tag?>().firstWhere(
                            (t) => t?.name.toLowerCase() == value.toLowerCase(),
                            orElse: () => null,
                          );
                          if (existingTag != null) {
                            _addExistingTag(existingTag);
                          } else {
                            _createTag(value);
                          }
                        },
                        icon: const Icon(Icons.add, size: 20),
                        tooltip: 'Add tag',
                      ),
                    ],
                  ),

                  // Tag suggestions (up to 3 lines)
                  if (_suggestedTags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 100),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _suggestedTags.map((tag) {
                          final isPartial = _partiallySelectedTagIds.contains(
                            tag.id,
                          );
                          return ActionChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPartial) ...[
                                  Icon(
                                    Icons.remove,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(tag.name),
                              ],
                            ),
                            onPressed: () => _addExistingTag(tag),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  if (isMultiSelect) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tags checked with "-" are only on some papers',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Tags list
                  Text(
                    'Available Tags',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _allTags.isEmpty
                        ? Center(
                            child: Text(
                              'No tags yet. Create one above.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _allTags.length,
                            itemBuilder: (context, index) {
                              final tag = _allTags[index];
                              final isSelected = _selectedTagIds.contains(
                                tag.id,
                              );
                              final isPartial = _partiallySelectedTagIds
                                  .contains(tag.id);

                              return CheckboxListTile(
                                title: Text(tag.name),
                                value: isSelected,
                                tristate: isPartial && !isSelected,
                                onChanged: (_) => _toggleTag(tag.id!),
                                dense: true,
                                secondary: isPartial && !isSelected
                                    ? Icon(
                                        Icons.remove,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      )
                                    : null,
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
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
