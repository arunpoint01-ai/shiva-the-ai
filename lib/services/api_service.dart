const String apiKey = String.fromEnvironment('GEMINI_API_KEY');
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Google AI Studio वरील 'Shiva The AI System' ची थेट API Key

  static Future<String> getAIResponse(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": "You are Shiva, a high-performance JARVIS-inspired AI system. Answer concisely: $prompt"}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        return "Shiva Error: Connection Failed (${response.statusCode})";
      }
    } catch (e) {
      return "Shiva Connection Error: $e";
    }
  }
}
0
0


const String apiKey = String.fromEnvironment("GEMINI_API_KEY");
+0
+
