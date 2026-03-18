import 'paper.dart';

class PaperFolder {
  final int? id;
  final int? parentId;
  final String path;
  final String name;
  final bool isSymbolic; // True if it's an external linked folder
  final DateTime addedAt;
  List<PaperFolder> children; // For UI tree structure
  bool isExpanded; // Runtime UI state
  int paperCount;
  List<Paper> previewPapers;

  PaperFolder({
    this.id,
    this.parentId,
    required this.path,
    required this.name,
    this.isSymbolic = false,
    DateTime? addedAt,
    List<PaperFolder>? children,
    this.isExpanded = false,
    this.paperCount = 0,
    List<Paper>? previewPapers,
  }) : addedAt = addedAt ?? DateTime.now(),
       children = children ?? [],
       previewPapers = previewPapers ?? [];

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'parent_id': parentId,
      'path': path,
      'name': name,
      'is_symbolic': isSymbolic ? 1 : 0,
      'added_at': addedAt.toIso8601String(),
    };
  }

  factory PaperFolder.fromMap(Map<String, dynamic> map) {
    return PaperFolder(
      id: map['id'] as int?,
      parentId: map['parent_id'] as int?,
      path: map['path'] as String,
      name: map['name'] as String,
      isSymbolic: (map['is_symbolic'] as int?) == 1,
      addedAt: DateTime.parse(map['added_at'] as String),
    );
  }
}
