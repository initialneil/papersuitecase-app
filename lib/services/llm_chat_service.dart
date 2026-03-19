import 'dart:convert';
import '../models/chat_message.dart';
import 'supabase_service.dart';

class LlmChatService {
  /// Send a chat message about a paper. Returns the assistant's response.
  Future<String> chat({
    required String paperTitle,
    String? authors,
    String? abstract,
    String? bibtex,
    required String question,
    required List<ChatMessage> history,
  }) async {
    final session = SupabaseService.currentSession;
    if (session == null) throw Exception('Not logged in');

    final truncatedHistory = history.length > 10
        ? history.sublist(history.length - 10)
        : history;

    final response = await SupabaseService.client.functions.invoke(
      'chat-with-paper',
      body: {
        'paper_title': paperTitle,
        'authors': authors,
        'abstract': abstract,
        'bibtex': bibtex,
        'user_question': question,
        'conversation_history':
            truncatedHistory.map((m) => m.toJson()).toList(),
      },
    );

    if (response.status != 200) {
      final body = response.data;
      if (response.status == 429) {
        final data = body is String ? jsonDecode(body) : body;
        throw RateLimitException(
          data['limit'] as int? ?? 30,
          data['used'] as int? ?? 0,
        );
      }
      final data = body is String ? jsonDecode(body) : body;
      throw Exception(data['error'] ?? 'Chat failed');
    }

    // Parse response — could be streamed SSE or plain text
    final data = response.data;
    if (data is String) {
      return _parseStreamedResponse(data);
    }
    return data.toString();
  }

  String _parseStreamedResponse(String sseData) {
    final buffer = StringBuffer();
    for (final line in sseData.split('\n')) {
      if (line.startsWith('data: ')) {
        final jsonStr = line.substring(6).trim();
        if (jsonStr == '[DONE]') break;
        try {
          final json = jsonDecode(jsonStr);
          final delta = json['choices']?[0]?['delta']?['content'];
          if (delta != null) buffer.write(delta);
        } catch (_) {
          // Skip malformed lines
        }
      }
    }
    final result = buffer.toString();
    return result.isNotEmpty
        ? result
        : sseData; // Fallback to raw if no SSE detected
  }
}

class RateLimitException implements Exception {
  final int limit;
  final int used;
  RateLimitException(this.limit, this.used);

  @override
  String toString() =>
      'Rate limit exceeded: $used/$limit calls used this month';
}
