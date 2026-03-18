import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html_unescape/html_unescape_small.dart';

class DblpResult {
  final String title;
  final String authors;
  final String venue;
  final String year;
  final String url; // DBLP record URL

  DblpResult({
    required this.title,
    required this.authors,
    required this.venue,
    required this.year,
    required this.url,
  });
}

/// Unified search result for any source
/// `url` should be a resolvable record page for the source.
class BibResult {
  final String title;
  final String authors;
  final String venue;
  final String year;
  final String url; // Record URL (DBLP or ACM DOI page)
  final String source; // 'DBLP' or 'ACM.org'

  BibResult({
    required this.title,
    required this.authors,
    required this.venue,
    required this.year,
    required this.url,
    required this.source,
  });
}

class BibtexService {
  static const String _dblpApiUrl = 'https://dblp.org/search/publ/api';
  static const String _acmSearchUrl = 'https://dl.acm.org/action/doSearch';

  /// Source options for BibTeX import
  static const bibSources = ['DBLP', 'ACM.org'];

  /// Search DBLP for papers
  static Future<List<DblpResult>> searchDblp(String query) async {
    try {
      final uri = Uri.parse(_dblpApiUrl).replace(
        queryParameters: {
          'q': query,
          'h': '10', // limit to 10 hits
          'format': 'json',
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Failed to search DBLP: ${response.statusCode}');
      }

      final data = json.decode(response.body);
      final result = data['result'];

      if (result['hits'] == null || result['hits']['hit'] == null) {
        return [];
      }

      final hits = result['hits']['hit'] as List;
      final unescape = HtmlUnescape();

      return hits.map<DblpResult>((hit) {
        final info = hit['info'];

        // Parse authors (can be list or single object)
        String authorsStr = '';
        if (info['authors'] != null && info['authors']['author'] != null) {
          final authorsData = info['authors']['author'];
          if (authorsData is List) {
            authorsStr = authorsData
                .map((a) => a['text'].toString())
                .join(', ');
          } else if (authorsData is Map) {
            authorsStr = authorsData['text'].toString();
          } else {
            authorsStr = authorsData.toString();
          }
        }

        return DblpResult(
          title: unescape.convert(info['title'] ?? ''),
          authors: unescape.convert(authorsStr),
          venue: unescape.convert(info['venue'] ?? ''),
          year: info['year']?.toString() ?? '',
          url: info['url'] ?? '',
        );
      }).toList();
    } catch (e) {
      print('DBLP Search Error: $e');
      rethrow;
    }
  }

  /// Fetch BibTeX for a DBLP record URL
  static Future<String> fetchBibtex(String dblpUrl) async {
    // dblpUrl example: https://dblp.org/rec/conf/icse/AuthorTitle
    // We want: https://dblp.org/rec/conf/icse/AuthorTitle.bib?param=1

    // Check if it ends with .html or similar, strip it?
    // DBLP API usually returns the record URL (rec/...)

    try {
      String bibUrl = dblpUrl;
      // Ensure we have the base record URL
      // If it's already a .bib link, fine. If it's the record page, append .bib
      if (!bibUrl.endsWith('.bib')) {
        bibUrl = '$bibUrl.bib';
      }

      final uri = Uri.parse(bibUrl).replace(
        queryParameters: {
          'param': '1', // 1 = standard format
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch BibTeX: ${response.statusCode}');
      }

      return response.body.trim();
    } catch (e) {
      print('BibTeX Fetch Error: $e');
      rethrow;
    }
  }

  /// Generic search by source returning unified `BibResult` objects.
  static Future<List<BibResult>> search(String query, String source) async {
    if (source == 'DBLP') {
      final dblp = await searchDblp(query);
      return dblp
          .map(
            (d) => BibResult(
              title: d.title,
              authors: d.authors,
              venue: d.venue,
              year: d.year,
              url: d.url,
              source: 'DBLP',
            ),
          )
          .toList();
    }
    if (source == 'ACM.org') {
      return await _searchAcm(query);
    }
    throw UnsupportedError('Unknown source: $source');
  }

  /// Fetch BibTeX for a unified `BibResult` based on its source
  static Future<String> fetchBibtexFor(BibResult result) async {
    if (result.source == 'DBLP') {
      return fetchBibtex(result.url);
    }
    if (result.source == 'ACM.org') {
      return _fetchBibtexFromAcm(result.url);
    }
    throw UnsupportedError('Unknown source: ${result.source}');
  }

  /// Search ACM.org (Digital Library) for papers.
  /// This uses a simple HTML parse to extract DOI links and titles.
  static Future<List<BibResult>> _searchAcm(String query) async {
    try {
      final uri = Uri.parse(
        _acmSearchUrl,
      ).replace(queryParameters: {'AllField': query});

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Failed to search ACM.org: ${response.statusCode}');
      }

      final body = response.body;
      final unescape = HtmlUnescape();

      // Find anchors that link to /doi/10.... and capture the title
      final reg = RegExp(
        r'<a[^>]*href="\/doi\/10\.[^"\s]+"[^>]*>([^<]+)<\/a>',
        caseSensitive: false,
      );

      final matches = reg.allMatches(body).toList();
      if (matches.isEmpty) {
        return [];
      }

      // Also capture the DOI from the href
      final hrefReg = RegExp(
        r'href="(\/doi\/10\.[^"\s]+)"',
        caseSensitive: false,
      );

      final results = <BibResult>[];
      for (final m in matches) {
        final title = unescape.convert(m.group(1)!.trim());

        // Extract href (search within the matched substring vicinity)
        final snippetStart = m.start > 200 ? m.start - 200 : 0;
        final snippetEnd = m.end + 200 < body.length
            ? m.end + 200
            : body.length;
        final snippet = body.substring(snippetStart, snippetEnd);
        final hrefMatch = hrefReg.firstMatch(snippet);
        if (hrefMatch == null) continue;
        final href = hrefMatch.group(1)!;
        final url = 'https://dl.acm.org$href';

        results.add(
          BibResult(
            title: title,
            authors: '', // Not trivially available in simple parse
            venue: 'ACM DL',
            year: '',
            url: url,
            source: 'ACM.org',
          ),
        );
      }

      // Deduplicate by URL
      final seen = <String>{};
      final deduped = <BibResult>[];
      for (final r in results) {
        if (seen.add(r.url)) deduped.add(r);
      }
      return deduped;
    } catch (e) {
      print('ACM Search Error: $e');
      rethrow;
    }
  }

  /// Fetch BibTeX from ACM using a DOI page URL or DOI.
  /// Tries to build the export URL: /action/exportCit?doi=<doi>&format=bibtex
  static Future<String> _fetchBibtexFromAcm(String doiOrUrl) async {
    try {
      // Extract DOI if a full URL was provided
      String doi = doiOrUrl;
      final doiReg = RegExp(r'10\.[^\s/]+/[^\s/]+');
      final m = doiReg.firstMatch(doiOrUrl);
      if (m != null) {
        doi = m.group(0)!;
      }

      final exportUri = Uri.parse(
        'https://dl.acm.org/action/exportCit',
      ).replace(queryParameters: {'doi': doi, 'format': 'bibtex'});

      final response = await http.get(exportUri);
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch ACM BibTeX: ${response.statusCode}');
      }

      final content = response.body.trim();
      // Some ACM responses may wrap content; attempt to extract BibTeX block
      final bibReg = RegExp(r'@\w+\{[\s\S]*?\n\}', multiLine: true);
      final bibMatch = bibReg.firstMatch(content);
      if (bibMatch != null) {
        return bibMatch.group(0)!.trim();
      }
      // Fallback to raw content
      return content;
    } catch (e) {
      print('ACM BibTeX Fetch Error: $e');
      rethrow;
    }
  }
}
