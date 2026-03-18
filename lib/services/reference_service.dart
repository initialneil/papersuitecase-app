import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

class ReferenceInfo {
  final String marker; // e.g., "[1]"
  final String title;
  final String? authors;

  ReferenceInfo({required this.marker, required this.title, this.authors});

  Map<String, dynamic> toMap() => {
    'marker': marker,
    'title': title,
    'authors': authors,
  };

  factory ReferenceInfo.fromMap(Map<String, dynamic> map) => ReferenceInfo(
    marker: map['marker'] as String,
    title: map['title'] as String,
    authors: map['authors'] as String?,
  );
}

class ReferenceMarker {
  final String marker;
  final int pageIndex;
  final Rect bounds;

  ReferenceMarker({
    required this.marker,
    required this.pageIndex,
    required this.bounds,
  });

  Map<String, dynamic> toMap() => {
    'marker': marker,
    'pageIndex': pageIndex,
    'bounds': [bounds.left, bounds.top, bounds.width, bounds.height],
  };

  factory ReferenceMarker.fromMap(Map<String, dynamic> map) {
    final b = map['bounds'] as List<dynamic>;
    return ReferenceMarker(
      marker: map['marker'] as String,
      pageIndex: map['pageIndex'] as int,
      bounds: Rect.fromLTWH(
        (b[0] as num).toDouble(),
        (b[1] as num).toDouble(),
        (b[2] as num).toDouble(),
        (b[3] as num).toDouble(),
      ),
    );
  }
}

class ReferenceService {
  /// Extracts the bibliography from a PDF and maps markers to titles.
  /// This is an approximation based on common paper formats.
  static Future<List<ReferenceInfo>> extractReferences(String filePath) async {
    final List<dynamic> result = await compute(
      _extractReferencesInternal,
      filePath,
    );
    return result
        .map((e) => ReferenceInfo.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<Map<String, dynamic>> _extractReferencesInternal(
    String filePath,
  ) {
    try {
      final bytes = File(filePath).readAsBytesSync();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);

      // 1. Find the References/Bibliography section
      int refStartPage = -1;

      for (int i = document.pages.count - 1; i >= 0; i--) {
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        // Debug: print a snippet of each page's text
        // debugPrint(
        //   'Page $i text snippet: ${pageText.substring(0, pageText.length > 200 ? 200 : pageText.length).replaceAll('\n', ' ')}',
        // );

        if (pageText.contains(
          RegExp(r'References|Bibliography', caseSensitive: false),
        )) {
          refStartPage = i;
          // debugPrint('Found references section on page $i');
          break;
        }
      }

      if (refStartPage == -1) {
        // debugPrint('REFERENCES NOT FOUND in document.');
        document.dispose();
        return [];
      }

      // Collect text from the references section to the end
      StringBuffer refBuffer = StringBuffer();
      for (int i = refStartPage; i < document.pages.count; i++) {
        refBuffer.writeln(
          extractor.extractText(startPageIndex: i, endPageIndex: i),
        );
      }

      final refText = refBuffer.toString();
      final List<Map<String, dynamic>> references = [];

      // 2. Parse references (e.g., "[1] Author. Title. Journal...")
      // Relaxed regex: don't strictly require space after ]
      final markerRegex = RegExp(r'\[(\d+)\]\s*([^\[]+)');
      final matches = markerRegex.allMatches(refText);

      for (final match in matches) {
        final marker = "[${match.group(1)}]";
        final content = match.group(2)?.trim() ?? "";

        if (content.isEmpty) continue;

        // Improved heuristic for title extraction
        String title = "";
        String? authors;

        // Normalize whitespace first
        String cleanedContent = content
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll('\n', ' ')
            .trim();

        // De-smushing: Add spaces before capital letters if missing
        String fixedContent = cleanedContent.replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        );

        // Heuristic 1: Look for quoted text as the title
        final quoteRegex = RegExp(r'[""]([^""]{10,}?)[""]');
        final quoteMatch = quoteRegex.firstMatch(fixedContent);
        if (quoteMatch != null && quoteMatch.group(1)!.length > 10) {
          title = quoteMatch.group(1)!;
          // Authors are everything before the quote
          authors = fixedContent.split(quoteMatch.group(0)!).first.trim();
        } else {
          // Heuristic 2: Split by periods - simpler approach
          final parts = fixedContent.split(RegExp(r'\.\s+'));
          if (parts.length >= 2) {
            authors = parts[0].trim();
            title = parts[1].trim();

            // If authors is very short, it might be part of a number/abbreviation
            if (authors.length < 5 && parts.length >= 3) {
              authors = '${parts[0]}. ${parts[1]}'.trim();
              title = parts[2].trim();
            }
          } else if (parts.isNotEmpty) {
            title = parts[0].trim();
          }
        }

        // Clean up title - remove journal info and trailing punctuation
        title = title
            .split(RegExp(r'\s+In\s+[A-Z]', caseSensitive: false))
            .first
            .trim();
        title = title
            .split(RegExp(r'\s+vol\.\s+|\s+volume\s+', caseSensitive: false))
            .first
            .trim();
        title = title.replaceAll(RegExp(r'[.,:;]+$'), '').trim();

        // Limit title length to avoid capturing too much text if parsing fails
        if (title.length > 200) {
          title = '${title.substring(0, 197)}...';
        }

        // Clean up authors
        if (authors != null) {
          authors = authors
              .replaceAll(RegExp(r'\s+'), ' ')
              .replaceAll(RegExp(r'[.,:;]+$'), '')
              .replaceAll(RegExp(r'\(\d{4}\).*$'), '')
              .trim();

          if (authors.length > 100) {
            authors = '${authors.substring(0, 97)}...';
          }
        }

        // Skip if title is too short to be useful
        if (title.isEmpty || title.length < 5) {
          continue;
        }

        references.add(
          ReferenceInfo(marker: marker, title: title, authors: authors).toMap(),
        );
      }

      // for (final ref in references) {
      //   debugPrint('Extracted ref: ${ref.marker} -> ${ref.title}');
      // }
      document.dispose();
      return references;
    } catch (e) {
      // print('Error extracting references: $e');
      return [];
    }
  }

  /// Locates the coordinates of reference markers throughout the document.
  static Future<List<ReferenceMarker>> findReferenceMarkers(
    String filePath,
    List<String> markersToFind,
  ) async {
    if (markersToFind.isEmpty) return [];
    final List<dynamic> result = await compute(_findMarkersInternal, {
      'filePath': filePath,
      'markers': markersToFind,
    });
    return result
        .map((e) => ReferenceMarker.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<Map<String, dynamic>> _findMarkersInternal(
    Map<String, dynamic> args,
  ) {
    try {
      final String filePath = args['filePath'];
      final List<String> markersToFind = List<String>.from(args['markers']);
      final bytes = File(filePath).readAsBytesSync();
      final document = PdfDocument(inputBytes: bytes);
      final List<Map<String, dynamic>> detectedMarkers = [];
      final extractor = PdfTextExtractor(document);

      for (int i = 0; i < document.pages.count; i++) {
        // Find all text matches for all markers on this page in one go
        final List<MatchedItem> matches = extractor.findText(
          markersToFind,
          startPageIndex: i,
          endPageIndex: i,
        );

        for (final match in matches) {
          final cleanedMarker = match.text.trim();
          // Safety: ensure it's actually one of our markers
          if (markersToFind.contains(cleanedMarker)) {
            detectedMarkers.add(
              ReferenceMarker(
                marker: cleanedMarker,
                pageIndex: i,
                bounds: match.bounds,
              ).toMap(),
            );
          }
        }
      }

      // for (final m in detectedMarkers) {
      //   debugPrint(
      //     'Found marker ${m.marker} on page ${m.pageIndex} at ${m.bounds}',
      //   );
      // }
      // debugPrint('Found ${detectedMarkers.length} markers in text.');
      document.dispose();
      return detectedMarkers;
    } catch (e) {
      // debugPrint('Error in _findMarkersInternal: $e');
      return [];
    }
  }
}
