import 'tag.dart';

/// Paper model representing a PDF document with metadata.
class Paper {
  final int? id;
  final String title;
  final String filePath;
  final String? arxivId;
  final String? authors;
  final String? abstract;
  final String? extractedText;
  final DateTime addedAt;
  final bool isSymbolicLink;
  final String? arxivUrl;
  final String? bibtex;
  final int? folderId;
  List<Tag> tags;

  Paper({
    this.id,
    required this.title,
    required this.filePath,
    this.arxivId,
    this.authors,
    this.abstract,
    this.extractedText,
    DateTime? addedAt,
    this.isSymbolicLink = false,
    this.arxivUrl,
    this.bibtex,
    this.folderId,
    List<Tag>? tags,
  }) : addedAt = addedAt ?? DateTime.now(),
       tags = tags ?? [];

  /// Get formatted date string
  String get formattedDate {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[addedAt.month - 1]} ${addedAt.day}, ${addedAt.year}';
  }

  /// Get truncated title for display
  String get displayTitle {
    if (title.length <= 60) return title;
    return '${title.substring(0, 57)}...';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'file_path': filePath,
      'arxiv_id': arxivId,
      'authors': authors,
      'abstract': abstract,
      'extracted_text': extractedText,
      'added_at': addedAt.toIso8601String(),
      'is_symbolic_link': isSymbolicLink ? 1 : 0,
      'arxiv_url': arxivUrl,
      'bibtex': bibtex,
      'folder_id': folderId,
    };
  }

  factory Paper.fromMap(Map<String, dynamic> map, {List<Tag>? tags}) {
    return Paper(
      id: map['id'] as int?,
      title: map['title'] as String,
      filePath: map['file_path'] as String,
      arxivId: map['arxiv_id'] as String?,
      authors: map['authors'] as String?,
      abstract: map['abstract'] as String?,
      extractedText: map['extracted_text'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
      isSymbolicLink: (map['is_symbolic_link'] as int?) == 1,
      arxivUrl: map['arxiv_url'] as String?,
      bibtex: map['bibtex'] as String?,
      folderId: map['folder_id'] as int?,
      tags: tags,
    );
  }

  Paper copyWith({
    int? id,
    String? title,
    String? filePath,
    String? arxivId,
    String? authors,
    String? abstract,
    String? extractedText,
    DateTime? addedAt,
    bool? isSymbolicLink,
    String? arxivUrl,
    String? bibtex,
    List<Tag>? tags,
  }) {
    return Paper(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      arxivId: arxivId ?? this.arxivId,
      authors: authors ?? this.authors,
      abstract: abstract ?? this.abstract,
      extractedText: extractedText ?? this.extractedText,
      addedAt: addedAt ?? this.addedAt,
      isSymbolicLink: isSymbolicLink ?? this.isSymbolicLink,
      arxivUrl: arxivUrl ?? this.arxivUrl,
      bibtex: bibtex ?? this.bibtex,
      tags: tags ?? this.tags,
    );
  }

  @override
  String toString() => 'Paper(id: $id, title: $title, tags: ${tags.length})';
}
