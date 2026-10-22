// ============================================================================
// Shiva AI — Text-to-Speech service
// ============================================================================

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  Future<void> initialize() async {
    if (_initialized) return;
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _initialized = true;
  }

  Future<bool> isLocaleAvailable(String localeId) async {
    await initialize();
    try {
      final r = await _tts.isLanguageAvailable(localeId);
      return r == true || r == 1;
    } catch (_) {
      return false;
    }
  }

  Future<String?> pickSupportedLocale(List<String> preferred) async {
    for (final p in preferred) {
      if (await isLocaleAvailable(p)) return p;
    }
    return null;
  }

  Future<bool> speak({
    required String text,
    required String localeId,
    void Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    if (text.trim().isEmpty) return false;
    await initialize();

    if (!await isLocaleAvailable(localeId)) {
      onError?.call('TTS language $localeId unavailable.');
      return false;
    }

    try { await _tts.stop(); } catch (_) {}

    try {
      await _tts.setLanguage(localeId);
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(() {
        _speaking = false;
        onComplete?.call();
      });
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((m) {
        _speaking = false;
        onError?.call(m?.toString() ?? 'TTS playback error.');
      });

      final r = await _tts.speak(text);
      if (r != 1) {
        _speaking = false;
        onError?.call('Speech synthesis could not start.');
        return false;
      }
      return true;
    } catch (e) {
      _speaking = false;
      onError?.call('TTS error: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try { await _tts.stop(); } catch (_) {}
    _speaking = false;
  }

  void dispose() {
    _speaking = false;
    try { _tts.stop(); } catch (_) {}
  }
}
