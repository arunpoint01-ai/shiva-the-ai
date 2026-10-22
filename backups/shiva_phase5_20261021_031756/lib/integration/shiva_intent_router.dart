// SHIVA_PHASE5_ROUTER_V1
// Deterministic intent router. No network, no side effects, testable.

enum ShivaIntent {
  playMedia,
  spiritualQuestion,
  stop,
  cancel,
  changeLanguage,
  downloadMedia,
  unknown,
}

class ShivaIntentResult {
  final ShivaIntent intent;
  final String originalText;
  final String? targetLanguage;
  final String? mediaQuery;

  const ShivaIntentResult({
    required this.intent,
    required this.originalText,
    this.targetLanguage,
    this.mediaQuery,
  });
}

class ShivaIntentRouter {
  static final RegExp _wakeEn = RegExp(r'\bhey\s+shiva\b', caseSensitive: false);
  static final RegExp _wakeMr = RegExp(r'हे\s+शिवा');

  static bool containsWakeWord(String text) {
    return _wakeEn.hasMatch(text) || _wakeMr.hasMatch(text);
  }

  static String stripWakeWord(String text) {
    return text
        .replaceAll(_wakeEn, '')
        .replaceAll(_wakeMr, '')
        .trim();
  }

  static ShivaIntentResult route(String rawText) {
    final text = stripWakeWord(rawText);
    final lower = text.toLowerCase();

    if (text.isEmpty) {
      return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: rawText);
    }

    if (RegExp(r'\b(stop|band|थांब|बंद)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.stop, originalText: rawText);
    }
    if (RegExp(r'\b(cancel|रद्द)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.cancel, originalText: rawText);
    }

    // Language change
    if (RegExp(r'\b(marathi|मराठी)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: rawText, targetLanguage: 'mr-IN');
    }
    if (RegExp(r'\b(hindi|हिंदी)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: rawText, targetLanguage: 'hi-IN');
    }
    if (RegExp(r'\b(english|इंग्रजी)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: rawText, targetLanguage: 'en-IN');
    }

    // Download (privileged)
    if (RegExp(r'\b(download|डाउनलोड)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.downloadMedia, originalText: rawText, mediaQuery: text);
    }

    // Spiritual knowledge
    if (RegExp(r'\b(gita|गीता|bhagavad|karma|yoga|श्लोक|verse|अर्थ|meaning)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.spiritualQuestion, originalText: rawText);
    }

    // Play media (aarti, bhajan, song, etc.)
    if (RegExp(r'\b(play|लाव|लगा|चालू|सुरू|aarti|आरती|bhajan|भजन|song|गाणं)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.playMedia, originalText: rawText, mediaQuery: text);
    }

    return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: rawText);
  }
}
