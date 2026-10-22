import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceLanguage {
  marathi('mr_IN', 'mr-IN', 'मराठी'),
  hindi('hi_IN', 'hi-IN', 'हिन्दी'),
  english('en_IN', 'en-IN', 'English');

  const VoiceLanguage(this.sttLocale, this.ttsLocale, this.nativeName);

  final String sttLocale;
  final String ttsLocale;
  final String nativeName;
}

enum VoiceState { idle, listening, processing, speaking, error }

enum VoiceErrorType {
  permissionDenied,
  recognitionUnavailable,
  localeUnavailable,
  noSpeech,
  ttsLanguageMissing,
  platform,
}

class VoiceError {
  const VoiceError(this.type, [this.detail = '']);

  final VoiceErrorType type;
  final String detail;
}

class VoiceEngine {
  VoiceEngine({
    this.onStateChanged,
    this.onTranscript,
    this.onError,
    this.onSoundLevel,
  });

  final void Function(VoiceState state)? onStateChanged;
  final void Function(String text, bool isFinal)? onTranscript;
  final void Function(VoiceError error)? onError;
  final void Function(double level)? onSoundLevel;

  VoiceLanguage language = VoiceLanguage.english;

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  Future<void>? _initFuture;
  Future<void>? _ttsInitFuture;
  List<LocaleName> _locales = const [];

  bool _sttReady = false;
  bool _ttsReady = false;
  bool _disposed = false;
  bool _starting = false;
  bool _speaking = false;
  bool _finalDelivered = true;
  int _speakToken = 0;
  String _lastWords = '';
  VoiceState _state = VoiceState.idle;

  VoiceState get state => _state;
  bool get isListening => _state == VoiceState.listening;
  bool get isSpeaking => _speaking;
  bool get isRecognitionReady => _sttReady;

  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    return _initFuture ??= _runInit().whenComplete(() => _initFuture = null);
  }

  Future<void> _runInit() async {
    await _ensureTts();
    if (!_sttReady) await _initStt();
  }

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    await (_ttsInitFuture ??=
        _initTts().whenComplete(() => _ttsInitFuture = null));
  }

  Future<void> _initTts() async {
    try {
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _tts.setStartHandler(() {
        if (_disposed || _state == VoiceState.listening) return;
        _speaking = true;
        _setState(VoiceState.speaking);
      });
      _tts.setCompletionHandler(_onTtsFinished);
      _tts.setCancelHandler(_onTtsFinished);
      _tts.setErrorHandler((dynamic message) {
        _speaking = false;
        _fail(VoiceErrorType.platform, 'TTS: $message');
      });
      _ttsReady = true;
    } catch (e) {
      _fail(VoiceErrorType.platform, 'TTS init: $e');
    }
  }

  Future<void> _initStt() async {
    try {
      _sttReady = await _stt.initialize(
        onError: _onSttError,
        onStatus: _onSttStatus,
      );
      if (!_sttReady) {
        final hasPermission = await _stt.hasPermission;
        _fail(hasPermission
            ? VoiceErrorType.recognitionUnavailable
            : VoiceErrorType.permissionDenied);
        return;
      }
      _locales = await _stt.locales();
    } catch (e) {
      _sttReady = false;
      _fail(VoiceErrorType.platform, 'STT init: $e');
    }
  }

  Future<void> startListening() async {
    if (_disposed || _starting || _state == VoiceState.listening) return;
    _starting = true;
    try {
      if (_speaking) await stopSpeaking();
      await initialize();
      if (!_sttReady) return;

      final localeId = _resolveLocale(language);
      if (localeId == null) {
        _fail(VoiceErrorType.localeUnavailable, language.sttLocale);
        return;
      }
      if (_stt.isListening) await _stt.cancel();

      _finalDelivered = false;
      _lastWords = '';
      _setState(VoiceState.listening);
      await _stt.listen(
        onResult: _onResult,
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        onSoundLevelChange: (double level) {
          if (!_disposed) onSoundLevel?.call(level);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _finalDelivered = true;
      _fail(VoiceErrorType.platform, '$e');
    } finally {
      _starting = false;
    }
  }

  Future<void> stopListening() async {
    if (_disposed || _state != VoiceState.listening) return;
    _setState(VoiceState.processing);
    try {
      await _stt.stop();
    } catch (e) {
      _finalDelivered = true;
      _fail(VoiceErrorType.platform, '$e');
    }
  }

  Future<void> cancelListening() async {
    if (_disposed) return;
    _finalDelivered = true;
    try {
      await _stt.cancel();
    } catch (_) {
      // Cancelling an inactive recognizer is harmless.
    }
    if (_state == VoiceState.listening || _state == VoiceState.processing) {
      _setState(VoiceState.idle);
    }
  }

  Future<void> speak(String text, {required String languageCode}) async {
    if (_disposed || text.trim().isEmpty) return;
    final token = ++_speakToken;
    try {
      await _ensureTts();
      if (!_ttsReady || token != _speakToken) return;
      if (_state == VoiceState.listening || _state == VoiceState.processing) {
        await cancelListening();
      }
      if (_speaking) await _tts.stop();

      final available = await _tts.isLanguageAvailable(languageCode);
      if (token != _speakToken) return;
      if (!(available == true || available == 1)) {
        _fail(VoiceErrorType.ttsLanguageMissing, languageCode);
        return;
      }
      await _tts.setLanguage(languageCode);
      if (token != _speakToken) return;
      await _tts.speak(text);
    } catch (e) {
      _fail(VoiceErrorType.platform, '$e');
    }
  }

  Future<void> stopSpeaking() async {
    if (_disposed) return;
    _speakToken++;
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop.
    }
    if (_state == VoiceState.speaking) _setState(VoiceState.idle);
  }

  void clearError() {
    if (_state == VoiceState.error) _setState(VoiceState.idle);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _finalDelivered = true;
    _speakToken++;
    try {
      await _stt.cancel();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  String? _resolveLocale(VoiceLanguage lang) {
    String norm(String s) => s.replaceAll('-', '_').toLowerCase();
    final wanted = norm(lang.sttLocale);
    for (final locale in _locales) {
      if (norm(locale.localeId) == wanted) return locale.localeId;
    }
    return null;
  }

  void _onResult(SpeechRecognitionResult result) {
    if (_disposed || _finalDelivered) return;
    _lastWords = result.recognizedWords;
    if (result.finalResult) {
      _finalDelivered = true;
      onTranscript?.call(_lastWords, true);
      if (_state == VoiceState.listening || _state == VoiceState.processing) {
        _setState(VoiceState.idle);
      }
    } else {
      onTranscript?.call(_lastWords, false);
    }
  }

  void _onSttStatus(String status) {
    if (_disposed) return;
    if (status == SpeechToText.notListeningStatus) {
      if (_state == VoiceState.listening) _setState(VoiceState.processing);
    } else if (status == SpeechToText.doneStatus) {
      if (!_finalDelivered) {
        _finalDelivered = true;
        if (_lastWords.trim().isNotEmpty) onTranscript?.call(_lastWords, true);
      }
      if (_state == VoiceState.listening || _state == VoiceState.processing) {
        _setState(VoiceState.idle);
      }
    }
  }

  void _onSttError(SpeechRecognitionError error) {
    if (_disposed) return;
    _finalDelivered = true;
    switch (error.errorMsg) {
      case 'error_no_match':
      case 'error_speech_timeout':
        _fail(VoiceErrorType.noSpeech, error.errorMsg);
      case 'error_permission':
        _fail(VoiceErrorType.permissionDenied, error.errorMsg);
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        _fail(VoiceErrorType.localeUnavailable, error.errorMsg);
      default:
        _fail(VoiceErrorType.platform, error.errorMsg);
    }
  }

  void _onTtsFinished() {
    _speaking = false;
    if (_state == VoiceState.speaking) _setState(VoiceState.idle);
  }

  void _fail(VoiceErrorType type, [String detail = '']) {
    if (_disposed) return;
    _setState(VoiceState.error);
    onError?.call(VoiceError(type, detail));
  }

  void _setState(VoiceState next) {
    if (_disposed || _state == next) return;
    _state = next;
    onStateChanged?.call(next);
  }
}
