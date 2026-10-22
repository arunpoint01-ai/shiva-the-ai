// SHIVA_PHASE3_CONTROLLER_V1
// Phase 3 controller - manages UI state for Shiva AI assistant.
// Additive: does NOT replace any existing services.

import 'package:flutter/foundation.dart';

enum ShivaAssistantState { idle, listening, processing, speaking, error }

class ShivaPhase3Controller extends ChangeNotifier {
  ShivaPhase3Controller({
    this.speechService,
    this.geminiService,
    this.ttsService,
  });

  // Injected services (typed as Object? to avoid hard dependency on class names,
  // but concrete services in lib/services/ are used by name at call time).
  final Object? speechService;
  final Object? geminiService;
  final Object? ttsService;

  static const supportedLocales = <String, String>{
    'mr-IN': 'Marathi',
    'hi-IN': 'Hindi',
    'en-IN': 'English (India)',
  };

  ShivaAssistantState _state = ShivaAssistantState.idle;
  ShivaAssistantState get state => _state;

  String _locale = 'en-IN';
  String get locale => _locale;
  String get localeLabel => supportedLocales[_locale] ?? _locale;

  String _partialTranscript = '';
  String get partialTranscript => _partialTranscript;

  String _finalTranscript = '';
  String get finalTranscript => _finalTranscript;

  String _response = '';
  String get response => _response;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  // Session token to invalidate stale async results.
  int _sessionId = 0;
  bool _speakingForSession = false;
  bool _geminiInFlight = false;
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool setLocale(String newLocale) {
    if (!supportedLocales.containsKey(newLocale)) {
      _errorMessage = 'Unsupported locale: $newLocale';
      _state = ShivaAssistantState.error;
      _safeNotify();
      return false;
    }
    if (_locale == newLocale) return true;
    _locale = newLocale;
    _safeNotify();
    return true;
  }

  void updatePartialTranscript(String text) {
    if (_state != ShivaAssistantState.listening) return;
    if (text == _partialTranscript) return;
    _partialTranscript = text;
    _safeNotify();
  }

  Future<void> beginListening() async {
    if (_state == ShivaAssistantState.listening) return;
    if (_geminiInFlight) return;
    _sessionId++;
    _partialTranscript = '';
    _finalTranscript = '';
    _response = '';
    _errorMessage = '';
    _speakingForSession = false;
    _state = ShivaAssistantState.listening;
    _safeNotify();
  }

  Future<void> submitFinalTranscript(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _state = ShivaAssistantState.idle;
      _safeNotify();
      return;
    }
    _finalTranscript = trimmed;
    final sid = _sessionId;
    _state = ShivaAssistantState.processing;
    _safeNotify();
    await _runGemini(sid, trimmed);
  }

  Future<void> _runGemini(int sid, String prompt) async {
    if (_geminiInFlight) return;
    _geminiInFlight = true;
    try {
      if (geminiService == null) {
        _setError('GeminiService not wired; please provide an instance.');
        return;
      }
      dynamic result;
      try {
        result = await (geminiService as dynamic).generateResponse(prompt);
      } catch (_) {
        try {
          result = await (geminiService as dynamic).generateResponse(prompt: prompt);
        } catch (e) {
          _setError('Gemini request failed.');
          return;
        }
      }
      if (sid != _sessionId) return;
      final text = (result?.toString() ?? '').trim();
      if (text.isEmpty) {
        _setError('Empty response from Gemini.');
        return;
      }
      _response = text;
      _state = ShivaAssistantState.speaking;
      _safeNotify();
      await _speak(sid, text);
    } finally {
      _geminiInFlight = false;
    }
  }

  Future<void> _speak(int sid, String text) async {
    if (_speakingForSession) return;
    _speakingForSession = true;
    try {
      if (ttsService == null) {
        _state = ShivaAssistantState.idle;
        _safeNotify();
        return;
      }
      try {
        await (ttsService as dynamic).speak(text);
      } catch (_) {
        try {
          await (ttsService as dynamic).speak(text, locale: _locale);
        } catch (e) {
          _setError('TTS failed.');
          return;
        }
      }
    } finally {
      if (sid == _sessionId && _state == ShivaAssistantState.speaking) {
        _state = ShivaAssistantState.idle;
        _safeNotify();
      }
    }
  }

  Future<void> stopListening() async {
    if (_state != ShivaAssistantState.listening) return;
    try {
      await (speechService as dynamic)?.stop?.call();
    } catch (_) {/* ignore */}
    _state = ShivaAssistantState.idle;
    _safeNotify();
  }

  Future<void> stopSpeaking() async {
    try {
      await (ttsService as dynamic)?.stop?.call();
    } catch (_) {/* ignore */}
    if (_state == ShivaAssistantState.speaking) {
      _state = ShivaAssistantState.idle;
      _safeNotify();
    }
  }

  Future<void> cancelAll() async {
    _sessionId++;
    try { await (speechService as dynamic)?.stop?.call(); } catch (_) {/* ignore */}
    try { await (ttsService as dynamic)?.stop?.call(); } catch (_) {/* ignore */}
    _state = ShivaAssistantState.idle;
    _safeNotify();
  }

  void reset() {
    _sessionId++;
    _partialTranscript = '';
    _finalTranscript = '';
    _response = '';
    _errorMessage = '';
    _speakingForSession = false;
    _state = ShivaAssistantState.idle;
    _safeNotify();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _state = ShivaAssistantState.error;
    _safeNotify();
  }
}
