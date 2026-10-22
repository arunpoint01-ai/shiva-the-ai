// SHIVA_PHASE5_ROUTER
enum ShivaIntent { playMedia, spiritualQuestion, stop, cancel, changeLanguage, downloadMedia, unknown }

class ShivaIntentResult {
  final ShivaIntent intent;
  final String originalText;
  final String? targetLanguage;
  final String? mediaQuery;
  const ShivaIntentResult({required this.intent, required this.originalText, this.targetLanguage, this.mediaQuery});
}

class ShivaIntentRouter {
  static final RegExp _wakeEn = RegExp(r'\bhey\s+shiva\b', caseSensitive: false);
  static final RegExp _wakeMr = RegExp(r'हे\s+शिवा');
  
  static bool containsWakeWord(String t) => _wakeEn.hasMatch(t) || _wakeMr.hasMatch(t);
  static String stripWakeWord(String t) => t.replaceAll(_wakeEn, '').replaceAll(_wakeMr, '').trim();

  static ShivaIntentResult route(String raw) {
    final text = stripWakeWord(raw);
    final lower = text.toLowerCase();
    
    if (text.isEmpty) return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: raw);
    
    // Interruption Handling (Stop/Cancel)
    if (RegExp(r'\b(stop|band|थांब|बंद)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.stop, originalText: raw);
    if (RegExp(r'\b(cancel|रद्द)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.cancel, originalText: raw);
    
    // Language Switch
    if (RegExp(r'\b(marathi|मराठी)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: raw, targetLanguage: 'mr-IN');
    if (RegExp(r'\b(hindi|हिंदी)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: raw, targetLanguage: 'hi-IN');
    
    // Boss Secure Download
    if (RegExp(r'\b(download|डाउनलोड)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.downloadMedia, originalText: raw, mediaQuery: text);
    
    // Cloud Knowledge
    if (RegExp(r'\b(gita|गीता|bhagavad|karma|yoga|श्लोक|verse|अर्थ|meaning)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.spiritualQuestion, originalText: raw);
    
    // Media Play
    if (RegExp(r'\b(play|लाव|लगा|चालू|सुरू|aarti|आरती|bhajan|भजन|song|गाणं)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.playMedia, originalText: raw, mediaQuery: text);
    
    return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: raw);
  }
}
