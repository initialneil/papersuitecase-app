import 'package:flutter/material.dart';
import '../models/paper.dart';
import '../services/bibtex_service.dart';

class BibtexImportDialog extends StatefulWidget {
  final Paper paper;
  final String? currentBibtex;

  const BibtexImportDialog({
    super.key,
    required this.paper,
    this.currentBibtex,
  });

  @override
  State<BibtexImportDialog> createState() => _BibtexImportDialogState();
}

class _BibtexImportDialogState extends State<BibtexImportDialog> {
  late TextEditingController _searchController;
  final TextEditingController _fetchedController = TextEditingController();
  String _source = 'DBLP';
  List<BibResult> _results = [];
  bool _isLoading = false;
  bool _isFetchingBibtex = false;
  String? _error;

  bool _keepCitationKey = true;
  BibResult? _selectedResult;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.paper.title);
    // Auto-search on open?
    // _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fetchedController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _results = [];
      _selectedResult = null;
      _fetchedController.clear();
    });

    try {
      final results = await BibtexService.search(query, _source);
      if (mounted) {
        setState(() {
          _results = results;
          if (results.isEmpty) {
            _error = "No results found.";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchBibtex(BibResult result) async {
    setState(() {
      _selectedResult = result;
      _isFetchingBibtex = true;
      _fetchedController.clear();
    });

    try {
      final bibtex = await BibtexService.fetchBibtexFor(result);
      if (mounted) {
        setState(() {
          _fetchedController.text = bibtex;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to fetch BibTeX: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingBibtex = false;
        });
      }
    }
  }

  String _processBibtex(String newBibtex) {
    if (!_keepCitationKey ||
        widget.currentBibtex == null ||
        widget.currentBibtex!.isEmpty) {
      return newBibtex;
    }

    // Extract existing key
    // Pattern: @type{KEY,
    final keyPattern = RegExp(r'@\w+\{([^,]+),');
    final match = keyPattern.firstMatch(widget.currentBibtex!);
    if (match == null) return newBibtex; // Couldn't find existing key

    final existingKey = match.group(1)?.trim();
    if (existingKey == null || existingKey.isEmpty) return newBibtex;

    // Replace key in new bibtex
    return newBibtex.replaceFirstMapped(keyPattern, (m) {
      return '${m.group(0)!.substring(0, m.group(0)!.indexOf('{') + 1)}$existingKey,';
    });
  }

  void _apply() {
    if (_fetchedController.text.isEmpty) return;

    final finalBibtex = _processBibtex(_fetchedController.text);
    Navigator.of(context).pop(finalBibtex);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import BibTeX'),
      content: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            // Search Bar
            Row(
              children: [
                // Source dropdown
                SizedBox(
                  width: 150,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      isDense: true,
                      labelText: 'Source',
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _source,
                        items: BibtexService.bibSources
                            .map(
                              (s) => DropdownMenuItem<String>(
                                value: s,
                                child: Text(s),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _source = val;
                            _results = [];
                            _selectedResult = null;
                            _error = null;
                            _fetchedController.clear();
                          });
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search by title...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _search,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content Area
            Expanded(
              child: Row(
                children: [
                  // Left: Results List
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search Results',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.3),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _error != null
                                ? Center(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _results.length,
                                    itemBuilder: (context, index) {
                                      final result = _results[index];
                                      final isSelected =
                                          _selectedResult == result;
                                      return ListTile(
                                        title: Text(
                                          result.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          '${result.authors.isEmpty ? 'Unknown authors' : result.authors} - ${result.venue} ${result.year}',
                                        ),
                                        selected: isSelected,
                                        selectedTileColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withOpacity(0.3),
                                        onTap: () => _fetchBibtex(result),
                                        dense: true,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Right: Comparison / Preview
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        // Existing BibTeX
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current BibTeX',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: TextField(
                                  controller: TextEditingController(
                                    text: widget.currentBibtex,
                                  ),
                                  readOnly: true,
                                  maxLines: null,
                                  expands: true,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.grey.withOpacity(0.1),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Fetched BibTeX
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Fetched BibTeX',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  if (_isFetchingBibtex) ...[
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: TextField(
                                  controller: _fetchedController,
                                  readOnly: false,
                                  maxLines: null,
                                  expands: true,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText:
                                        'Fetched BibTeX will appear here (editable)',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _keepCitationKey,
                  onChanged: (val) =>
                      setState(() => _keepCitationKey = val ?? true),
                ),
                const Text('Keep existing citation key (name)'),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _fetchedController.text.isNotEmpty ? _apply : null,
                  child: const Text('Update BibTeX'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
