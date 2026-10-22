// ============================================================================
// Shiva AI — Centralized AI configuration
//
// Override at build time:
//   flutter build apk --dart-define=GEMINI_API_KEY=xxx \
//                     --dart-define=GEMINI_MODEL=gemini-3.8-flash
//
// SECURITY: Compile-time defines are embedded in the APK and are extractable.
// For production-grade protection, route requests through an authenticated
// backend proxy that holds the key server-side. Do NOT expose an
// unauthenticated public proxy.
//
// MODEL: "gemini-3.8-flash" is the assumed current Flash-tier model.
// Verify against the provider's live documentation before release.
// ============================================================================

class AiConfig {
  AiConfig._();

  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.8-flash');

  static const Duration requestTimeout = Duration(seconds: 30);
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static bool get hasApiKey => geminiApiKey.isNotEmpty;
}
