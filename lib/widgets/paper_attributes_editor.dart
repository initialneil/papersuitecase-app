import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/paper.dart';
import '../providers/app_state.dart';
import 'bibtex_import_dialog.dart';

class PaperAttributesEditor extends StatefulWidget {
  final Paper paper;

  const PaperAttributesEditor({super.key, required this.paper});

  @override
  State<PaperAttributesEditor> createState() => _PaperAttributesEditorState();
}

class _PaperAttributesEditorState extends State<PaperAttributesEditor> {
  late TextEditingController _titleController;
  late TextEditingController _authorsController;
  late TextEditingController _arxivUrlController;
  late TextEditingController _bibtexController;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _titleController = TextEditingController(text: widget.paper.title);
    _authorsController = TextEditingController(text: widget.paper.authors);
    _arxivUrlController = TextEditingController(text: widget.paper.arxivUrl);
    _bibtexController = TextEditingController(text: widget.paper.bibtex);

    _titleController.addListener(_onChanged);
    _authorsController.addListener(_onChanged);
    _arxivUrlController.addListener(_onChanged);
    _bibtexController.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(PaperAttributesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper.id != widget.paper.id) {
      _disposeControllers();
      _initControllers();
      setState(() {
        _isDirty = false;
      });
    }
  }

  void _disposeControllers() {
    _titleController.dispose();
    _authorsController.dispose();
    _arxivUrlController.dispose();
    _bibtexController.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Future<void> _showBibtexImportDialog() async {
    final newBibtex = await showDialog<String>(
      context: context,
      builder: (context) => BibtexImportDialog(
        paper: widget.paper,
        currentBibtex: _bibtexController.text,
      ),
    );

    if (newBibtex != null && newBibtex.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _bibtexController.text = newBibtex;
        _isDirty = true;
      });
      // Auto-save after importing BibTeX
      await _save();
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {
      _isDirty = true;
    });
  }

  Future<void> _save() async {
    final updatedPaper = widget.paper.copyWith(
      title: _titleController.text.trim(),
      authors: _authorsController.text.trim().isEmpty
          ? null
          : _authorsController.text.trim(),
      arxivUrl: _arxivUrlController.text.trim().isEmpty
          ? null
          : _arxivUrlController.text.trim(),
      bibtex: _bibtexController.text.trim().isEmpty
          ? null
          : _bibtexController.text.trim(),
    );

    await context.read<AppState>().updatePaper(updatedPaper);
    if (mounted) {
      setState(() {
        _isDirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attributes updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isDirty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _save,
                  child: const Text('Save'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildTextField('Title', _titleController, maxLines: 2),
              const SizedBox(height: 16),
              _buildTextField('Authors', _authorsController),
              const SizedBox(height: 16),
              _buildTextField('ArXiv URL', _arxivUrlController),
              const SizedBox(height: 16),
              _buildTextField(
                'BibTeX',
                _bibtexController,
                maxLines: 8,
                fontFamily: 'monospace',
                readOnly: true,
                headerAction: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        if (_bibtexController.text.isNotEmpty) {
                          Clipboard.setData(
                            ClipboardData(text: _bibtexController.text),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('BibTeX copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Copy to clipboard',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: _showBibtexImportDialog,
                      icon: const Icon(Icons.download, size: 14),
                      label: const Text('Import BibTex'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        // textStyle: const TextStyle(fontSize: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),

              if (widget.paper.isSymbolicLink) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.secondary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.link,
                        size: 20,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is a symbolic link to an external file.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.paper.filePath,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    String? fontFamily,
    Widget? headerAction,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (headerAction != null) headerAction,
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          minLines: 1,
          style: TextStyle(fontSize: 13, fontFamily: fontFamily),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
