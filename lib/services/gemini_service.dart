// ============================================================================
// Shiva AI — Gemini REST client
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ai_config.dart';

class GeminiException implements Exception {
  final String userMessage;
  final String? technicalDetail;
  final int? statusCode;

  const GeminiException(this.userMessage, {this.technicalDetail, this.statusCode});

  @override
  String toString() =>
      'GeminiException($statusCode): $userMessage'
      '${technicalDetail != null ? ' [$technicalDetail]' : ''}';
}

class GeminiService {
  final http.Client _client;
  final String _apiKey;
  final String _model;

  GeminiService({http.Client? client, String? apiKey, String? model})
      : _client = client ?? http.Client(),
        _apiKey = apiKey ?? AiConfig.geminiApiKey,
        _model = model ?? AiConfig.geminiModel;

  Future<String> generateResponse(String prompt) async {
    if (prompt.trim().isEmpty) throw const GeminiException('Prompt is empty.');
    if (_apiKey.isEmpty) {
      throw const GeminiException(
        'Gemini API key is not configured. Rebuild with --dart-define=GEMINI_API_KEY=...',
      );
    }

    final uri = Uri.parse(
      '${AiConfig.geminiBaseUrl}/models/$_model:generateContent?key=$_apiKey',
    );
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    });

    http.Response response;
    try {
      response = await _client
          .post(uri,
              headers: const {'Content-Type': 'application/json'}, body: body)
          .timeout(AiConfig.requestTimeout);
    } on TimeoutException {
      throw const GeminiException('Request timed out. Check your connection.');
    } on http.ClientException catch (e) {
      throw GeminiException('Network error.', technicalDetail: e.message);
    } catch (e) {
      throw GeminiException('Unexpected network failure.', technicalDetail: e.toString());
    }

    if (response.statusCode != 200) {
      throw _mapHttpError(response.statusCode, response.body);
    }
    return _parse(response.body);
  }

  String _parse(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw GeminiException('Invalid response from AI service.', technicalDetail: e.toString());
    }
    if (decoded is! Map<String, dynamic>) {
      throw const GeminiException('Unexpected response shape.');
    }

    final feedback = decoded['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw const GeminiException('Request blocked by safety filters. Rephrase.');
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GeminiException('The AI returned an empty response.');
    }

    final first = candidates.first;
    if (first is! Map) throw const GeminiException('Malformed candidate.');

    final finish = first['finishReason'];
    if (finish is String && finish.isNotEmpty && finish != 'STOP') {
      if (finish == 'SAFETY' || finish == 'RECITATION' || finish == 'BLOCKLIST') {
        throw GeminiException('Response blocked ($finish). Try a different prompt.');
      }
    }

    final parts = first['content']?['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const GeminiException('AI response incomplete.');
    }

    final buffer = StringBuffer();
    for (final p in parts) {
      if (p is Map && p['text'] is String) buffer.write(p['text']);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw const GeminiException('AI response empty.');
    return text;
  }

  GeminiException _mapHttpError(int status, String body) {
    String? detail;
    try {
      final d = jsonDecode(body);
      if (d is Map && d['error'] is Map) detail = d['error']['message']?.toString();
    } catch (_) {}
    switch (status) {
      case 400:
        return GeminiException('Invalid request to Gemini.', technicalDetail: detail, statusCode: status);
      case 401:
      case 403:
        return GeminiException('API key invalid or lacks permission.', technicalDetail: detail, statusCode: status);
      case 404:
        return GeminiException('Configured Gemini model is unavailable.', technicalDetail: detail, statusCode: status);
      case 429:
        return GeminiException('Rate limit reached. Wait and retry.', technicalDetail: detail, statusCode: status);
      default:
        if (status >= 500) {
          return GeminiException('Gemini server error ($status). Retry later.', technicalDetail: detail, statusCode: status);
        }
        return GeminiException('Unexpected Gemini error (HTTP $status).', technicalDetail: detail, statusCode: status);
    }
  }

  void dispose() => _client.close();
}
