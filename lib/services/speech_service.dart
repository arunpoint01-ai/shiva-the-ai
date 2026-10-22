// ============================================================================
// Shiva AI — Speech-to-Text service
// ============================================================================

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _listening = false;

  bool get isListening => _listening && _speech.isListening;

  Future<bool> initialize({void Function(String error)? onError}) async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (e) => onError?.call(e.errorMsg),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') _listening = false;
        },
      );
      return _initialized;
    } catch (e) {
      _initialized = false;
      onError?.call('Speech initialization failed: $e');
      return false;
    }
  }

  Future<List<String>> availableLocaleIds() async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return const [];
    }
    try {
      final locales = await _speech.locales();
      return locales.map((l) => l.localeId).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isLocaleAvailable(String localeId) async {
    final ids = await availableLocaleIds();
    return ids.contains(localeId);
  }

  Future<String?> pickSupportedLocale(List<String> preferred) async {
    final ids = await availableLocaleIds();
    for (final p in preferred) {
      if (ids.contains(p)) return p;
    }
    for (final p in preferred) {
      final lang = p.split('-').first;
      for (final id in ids) {
        if (id.startsWith(lang)) return id;
      }
    }
    return null;
  }

  Future<void> startListening({
    required String localeId,
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
    required void Function(String error) onError,
  }) async {
    if (_listening) {
      onError('Already listening.');
      return;
    }
    if (!await initialize(onError: onError)) {
      onError('Speech recognition unavailable.');
      return;
    }
    if (!await isLocaleAvailable(localeId)) {
      onError('Language $localeId unavailable for input.');
      return;
    }

    _listening = true;
    try {
      await _speech.listen(
        localeId: localeId,
        onResult: (SpeechRecognitionResult r) {
          if (r.finalResult) {
            _listening = false;
            final t = r.recognizedWords.trim();
            t.isEmpty ? onError('No speech detected.') : onFinal(t);
          } else {
            onPartial(r.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _listening = false;
      onError('Could not start listening: $e');
    }
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      try { await _speech.stop(); } catch (_) {}
    }
    _listening = false;
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      try { await _speech.cancel(); } catch (_) {}
    }
    _listening = false;
  }
}
