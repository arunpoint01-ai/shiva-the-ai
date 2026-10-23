// SHIVA_PHASE5_ROUTER (W1: Unicode-safe word matching for Devanagari)
enum ShivaIntent { playMedia, spiritualQuestion, stop, cancel, changeLanguage, downloadMedia, audioTest, unknown }

class ShivaIntentResult {
  final ShivaIntent intent;
  final String originalText;
  final String? targetLanguage;
  final String? mediaQuery;
  const ShivaIntentResult({required this.intent, required this.originalText, this.targetLanguage, this.mediaQuery});
}

class ShivaIntentRouter {
  // Dart's \b only understands ASCII word characters, so it never matches
  // Devanagari words. These helpers use Unicode letter/mark/digit classes.
  static const String _before = r'(?<![\p{L}\p{M}\p{N}_])';
  static const String _after = r'(?![\p{L}\p{M}\p{N}_])';

  /// Whole word match.
  static RegExp _exact(String alternatives) =>
      RegExp('$_before(?:$alternatives)$_after', unicode: true);

  /// Word that starts with one of the stems (handles Marathi/Hindi suffixes,
  /// e.g. मराठीत, आरतीचे, कर्मयोगाबद्दल).
  static RegExp _prefix(String alternatives) =>
      RegExp('$_before(?:$alternatives)', unicode: true);

  static final RegExp _wakeEn = RegExp(r'\bhey\s+shiva\b', caseSensitive: false);
  static final RegExp _wakeMr = RegExp(r'हे\s+शिवा');

  static final RegExp _stop = _exact('stop|band|थांब|बंद|रुक|रुको');
  static final RegExp _cancel = _exact('cancel|रद्द');
  static final RegExp _audioTest = _prefix('mic test|audio test|sound test|माईक टेस्ट|माइक टेस्ट|मायक्रोफोन टेस्ट|ऑडिओ टेस्ट|ऑडियो टेस्ट|आवाज टेस्ट');
  static final RegExp _download = _prefix('download|डाउनलोड|डाऊनलोड');
  static final List<RegExp> _spiritual = [
    _prefix('gita|गीता|गीते|bhagavad|karmayoga|कर्मयोग|karma|श्लोक|verse|meaning'),
    _exact('अर्थ'),
  ];
  static final List<RegExp> _play = [
    _exact('play|song|songs|लगा|लगाओ|बजाओ|चला'),
    _prefix('आरती|aarti|arti|भजन|bhajan|गाण|गीत|लाव|वाजव|मंत्र|mantra|कथा|katha|स्तोत्र'),
  ];
  static final RegExp _marathi = _prefix('marathi|मराठी');
  static final RegExp _hindi = _prefix('hindi|हिंदी|हिन्दी');

  static bool _any(List<RegExp> list, String s) => list.any((r) => r.hasMatch(s));

  static bool containsWakeWord(String t) => _wakeEn.hasMatch(t) || _wakeMr.hasMatch(t);
  static String stripWakeWord(String t) => t.replaceAll(_wakeEn, '').replaceAll(_wakeMr, '').trim();

  static ShivaIntentResult route(String raw) {
    final text = stripWakeWord(raw);
    final lower = text.toLowerCase();

    if (text.isEmpty) return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: raw);

    // Interruption (stop / cancel) always wins.
    if (_stop.hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.stop, originalText: raw);
    if (_cancel.hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.cancel, originalText: raw);

    // Microphone / speaker self-test.
    if (_audioTest.hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.audioTest, originalText: raw);
    }

    // Boss secure download.
    if (_download.hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.downloadMedia, originalText: raw, mediaQuery: text);
    }

    // Cloud knowledge (scriptures).
    if (_any(_spiritual, lower)) {
      return ShivaIntentResult(intent: ShivaIntent.spiritualQuestion, originalText: raw);
    }

    // Media play (checked before language so "मराठी गाणी लाव" plays music).
    if (_any(_play, lower)) {
      return ShivaIntentResult(intent: ShivaIntent.playMedia, originalText: raw, mediaQuery: text);
    }

    // Language switch.
    if (_marathi.hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: raw, targetLanguage: 'mr-IN');
    }
    if (_hindi.hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: raw, targetLanguage: 'hi-IN');
    }

    return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: raw);
  }
}
