import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/tag.dart';

enum FolderDropAction { linkSymbolic, importFiles }

class FolderDropResult {
  final FolderDropAction action;
  final bool importAsLink; // for ImportFiles
  final bool useFolderTags; // for ImportFiles
  final Tag? assignTag; // for ImportFiles

  FolderDropResult({
    required this.action,
    this.importAsLink = true,
    this.useFolderTags = true,
    this.assignTag,
  });
}

class FolderDropDialog extends StatefulWidget {
  final String folderPath;
  final Tag? currentTag;

  const FolderDropDialog({
    super.key,
    required this.folderPath,
    this.currentTag,
  });

  @override
  State<FolderDropDialog> createState() => _FolderDropDialogState();
}

class _FolderDropDialogState extends State<FolderDropDialog> {
  FolderDropAction _selectedAction = FolderDropAction.linkSymbolic;
  bool _importAsLink = true;
  // bool _useFolderTags = true; // "keep folder struction" imply this? Yes.
  Tag? _selectedTag;

  @override
  void initState() {
    super.initState();
    // Default tag to current selection if available
    _selectedTag = widget.currentTag;

    // If we are in "Others" (untagged), maybe don't default?
    // User said "default drop down to current selection tag if has (selecting tag now, not select folder)"
    if (_selectedTag != null && _selectedTag!.isOthers) {
      _selectedTag = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();

    return AlertDialog(
      title: const Text('Drop Folder'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Folder: ${widget.folderPath}'),
            const SizedBox(height: 20),

            // Option 1: Link Symbolic Folder
            RadioListTile<FolderDropAction>(
              title: const Text('Link Symbolic Folder'),
              subtitle: const Text(
                'Create a virtual link to this folder. Files remain in original location. No tags created.',
              ),
              value: FolderDropAction.linkSymbolic,
              groupValue: _selectedAction,
              onChanged: (value) => setState(() => _selectedAction = value!),
            ),

            // Option 2: Import Files
            RadioListTile<FolderDropAction>(
              title: const Text('Import Files'),
              subtitle: const Text(
                'Import all PDF files from this folder into the library.',
              ),
              value: FolderDropAction.importFiles,
              groupValue: _selectedAction,
              onChanged: (value) => setState(() => _selectedAction = value!),
            ),

            if (_selectedAction == FolderDropAction.importFiles) ...[
              Padding(
                padding: const EdgeInsets.only(left: 40, right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 8),

                    // Copy vs Link
                    Row(
                      children: [
                        const Text('File Storage:'),
                        const SizedBox(width: 16),
                        ChoiceChip(
                          label: const Text('Link (Reference)'),
                          selected: _importAsLink,
                          onSelected: (selected) =>
                              setState(() => _importAsLink = true),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Copy to App'),
                          selected: !_importAsLink,
                          onSelected: (selected) =>
                              setState(() => _importAsLink = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Tag Selection
                    Row(
                      children: [
                        const Text('Assign Tag:'),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<Tag?>(
                            value: _selectedTag,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<Tag?>(
                                value: null,
                                child: Text('None (Root)'),
                              ),
                              ...appState.tagTree
                                  .expand((t) => [t, ...t.children])
                                  .map((tag) {
                                    return DropdownMenuItem<Tag?>(
                                      value: tag,
                                      child: Text(tag.name),
                                    );
                                  }),
                            ],
                            onChanged: (Tag? value) {
                              setState(() {
                                _selectedTag = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              FolderDropResult(
                action: _selectedAction,
                importAsLink: _importAsLink,
                useFolderTags: true, // Implied "Keep folder structure"
                assignTag: _selectedTag,
              ),
            );
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
