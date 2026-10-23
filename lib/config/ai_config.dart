// ============================================================================
// Shiva AI — Centralized AI configuration
//
// Override at build time:
//   flutter build apk --dart-define=GEMINI_API_KEY=xxx \
//                     --dart-define=GEMINI_MODEL=gemini-3.8-flash \
//                     --dart-define=GEMINI_LIVE_MODEL=gemini-3.1-flash-live-preview
//
// SECURITY: Compile-time defines are embedded in the APK and are extractable.
// For production-grade protection, route requests through an authenticated
// backend proxy that holds the key server-side. Do NOT expose an
// unauthenticated public proxy.
//
// MODELS: "gemini-3.8-flash" is a published Flash model id (text replies).
// The Live (voice) model id comes from the gemini_live package docs; Google
// renames preview models often, so confirm it in Google AI Studio and
// override with GEMINI_LIVE_MODEL if the connection is refused.
// ============================================================================

class AiConfig {
  AiConfig._();

  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.8-flash');

  static const String geminiLiveModel = String.fromEnvironment(
      'GEMINI_LIVE_MODEL',
      defaultValue: 'gemini-3.1-flash-live-preview');

  static const Duration requestTimeout = Duration(seconds: 30);
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static bool get hasApiKey => geminiApiKey.isNotEmpty;
}
