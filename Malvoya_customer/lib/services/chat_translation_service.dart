import 'dart:convert';
import 'package:http/http.dart' as http;

/**
 * Real-Time Dynamic In-Flight Chat Translation Service
 * Translates customer-to-courier messages, dietary notes, and special instructions
 * with graceful fallback to raw text on transient network degradation.
 */
class ChatTranslationService {
  final String _endpoint = "https://translation.googleapis.com/language/translate/v2";
  final String? _apiKey;

  ChatTranslationService([this._apiKey]);

  Future<String> translateMessage({
    required String rawText,
    required String targetLanguageCode,
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) return rawText;
    try {
      final response = await http.post(
        Uri.parse('$_endpoint?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': rawText,
          'target': targetLanguageCode,
          'format': 'text',
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']['translations'][0]['translatedText'] as String;
      }
      return rawText;
    } catch (_) {
      return rawText; // Fallback to raw text gracefully
    }
  }
}
