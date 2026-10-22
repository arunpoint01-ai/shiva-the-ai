// SHIVA_PHASE3_CONTROLLER_v1
// Phase 3 integration controller: wires SpeechService, GeminiService, TtsService
// to a single observable workflow. Additive-only; does not modify existing services.

import 'dart:async';
import 'package:flutter/foundation.dart';

// The concrete services live in the project. We import them relatively so the
// controller remains independent of absolute paths.
import '../services/speech_service.dart';
import '../services/gemini_service.dart';
import '../services/tts_service.dart';

enum ShivaPhase3State { idle, listening, processing, speaking, error }

class ShivaPhase3Controller extends ChangeNotifier {
  final SpeechService speechService;
  final GeminiService geminiService;
  final TtsService ttsService;

  ShivaPhase3Controller({
    required this.speechService,
    required this.geminiService,
    required this.ttsService,
  });

  ShivaPhase3State _state = ShivaPhase3State.idle;
  ShivaPhase3State get state => _state;

  String _partial = '';
  String get partialTranscript => _partial;

  String _finalText = '';
  String get finalTranscript => _finalText;

  String _response = '';
  String get response => _response;

  String _error = '';
  String get errorMessage => _error;

  String _locale = 'en-IN';
  String get locale => _locale;

  // Monotonic session id to invalidate stale async results.
  int _sessionId = 0;

  // Guards to prevent duplicate Gemini calls or duplicate TTS.
  bool _geminiInFlight = false;
  int _spokenForSession = -1;

  bool _disposed = false;

  StreamSubscription? _speechSub;

  @override
  void dispose() {
    _disposed = true;
    _speechSub?.cancel();
    _speechSub = null;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setLocale(String newLocale) async {
    if (!const {'mr-IN', 'hi-IN', 'en-IN'}.contains(newLocale)) {
      _error = 'Unsupported locale: $newLocale';
      _state = ShivaPhase3State.error;
      _safeNotify();
      return;
    }
    _locale = newLocale;
    _safeNotify();
  }

  Future<bool> _ensureMicPermission() async {
    // Delegate to existing SpeechService which is assumed to own the mic permission flow.
    try {
      // Best-effort: many implementations expose initialize(); if not, ignore.
      final dynamic s = speechService;
      // ignore: avoid_dynamic_calls
      final dynamic res = await Future.sync(() => s.initialize?.call());
      if (res is bool && !res) {
        _error = 'Microphone permission denied';
        _state = ShivaPhase3State.error;
        _safeNotify();
        return false;
      }
      return true;
    } catch (_) {
      // If the service does not expose initialize(), proceed; start() will surface errors.
      return true;
    }
  }

  Future<void> startListening() async {
    if (_state == ShivaPhase3State.listening) return;
    if (_geminiInFlight) return;

    _sessionId++;
    _partial = '';
    _finalText = '';
    _response = '';
    _error = '';
    _state = ShivaPhase3State.listening;
    _safeNotify();

    final ok = await _ensureMicPermission();
    if (!ok) return;

    try {
      final dynamic s = speechService;
      // Try streaming API first: 'Stream<String> transcripts' or similar.
      final dynamic maybeStream = _tryStream(s);
      if (maybeStream is Stream) {
        await _speechSub?.cancel();
        _speechSub = maybeStream.listen(
          (raw) {
            final text = raw?.toString() ?? '';
            if (_disposed) return;
            if (_state != ShivaPhase3State.listening) return;
            if (text.isEmpty) return;
            _partial = text;
            _safeNotify();
          },
          onDone: () => _onSpeechDone(_sessionId),
          onError: (e) => _onSpeechError('Speech recognition error: $e'),
          cancelOnError: false,
        );
      } else {
        // Fallback: assume start(listenFor:, localeId:) + onResult callback.
        // ignore: avoid_dynamic_calls
        await Future.sync(() => s.start?.call(localeId: _locale));
      }
    } catch (e) {
      _onSpeechError('Failed to start speech recognition: $e');
    }
  }

  // Best-effort introspection of a stream-returning API on the concrete service.
  dynamic _tryStream(dynamic service) {
    // Common names: transcriptStream, partialStream, results, transcripts
    for (final name in const ['transcriptStream', 'partialStream', 'results', 'transcripts']) {
      try {
        final dynamic v = (service as dynamic).noSuchMethod(Invocation.getter(Symbol(name)));
        if (v is Stream) return v;
      } catch (_) {/* ignore */}
    }
    return null;
  }

  Future<void> stopListening({bool submit = true}) async {
    if (_state != ShivaPhase3State.listening) return;
    try {
      final dynamic s = speechService;
      // ignore: avoid_dynamic_calls
      await Future.sync(() => s.stop?.call());
    } catch (_) {/* ignore */}
    await _speechSub?.cancel();
    _speechSub = null;
    if (submit) {
      await _submitFinal(_sessionId);
    } else {
      _state = ShivaPhase3State.idle;
      _safeNotify();
    }
  }

  void _onSpeechDone(int sid) {
    if (sid != _sessionId) return;
    _submitFinal(sid);
  }

  void _onSpeechError(String msg) {
    _error = msg;
    _state = ShivaPhase3State.error;
    _safeNotify();
  }

  Future<void> _submitFinal(int sid) async {
    if (sid != _sessionId) return;
    final text = _partial.trim();
    if (text.isEmpty) {
      _state = ShivaPhase3State.idle;
      _safeNotify();
      return;
    }
    _finalText = text;
    _state = ShivaPhase3State.processing;
    _safeNotify();
    await _runGemini(sid, text);
  }

  Future<void> _runGemini(int sid, String prompt) async {
    if (_geminiInFlight) return;
    _geminiInFlight = true;
    try {
      final dynamic g = geminiService;
      dynamic result;
      try {
        // Preferred call per spec.
        // ignore: avoid_dynamic_calls
        result = await g.generateResponse(prompt);
      } catch (e) {
        // Fallback: try positional/keyword variants
        // ignore: avoid_dynamic_calls
        result = await g.generateResponse(prompt: prompt);
      }
      if (sid != _sessionId) return; // stale
      final text = (result?.toString() ?? '').trim();
      if (text.isEmpty) {
        _error = 'Empty response from Gemini';
        _state = ShivaPhase3State.error;
        _safeNotify();
        return;
      }
      _response = text;
      _state = ShivaPhase3State.speaking;
      _safeNotify();
      await _speakOnce(sid, text);
    } catch (e) {
      if (sid != _sessionId) return;
      _error = 'Gemini request failed: $e';
      _state = ShivaPhase3State.error;
      _safeNotify();
    } finally {
      _geminiInFlight = false;
    }
  }

  Future<void> _speakOnce(int sid, String text) async {
    if (_spokenForSession == sid) return;
    _spokenForSession = sid;
    try {
      final dynamic t = ttsService;
      // ignore: avoid_dynamic_calls
      await Future.sync(() => t.speak(text, locale: _locale));
    } catch (e) {
      _error = 'TTS failed: $e';
      // Keep response visible; downgrade to idle-with-error state.
      _state = ShivaPhase3State.error;
      _safeNotify();
      return;
    }
    if (sid == _sessionId && _state == ShivaPhase3State.speaking) {
      _state = ShivaPhase3State.idle;
      _safeNotify();
    }
  }

  Future<void> stopSpeaking() async {
    try {
      final dynamic t = ttsService;
      // ignore: avoid_dynamic_calls
      await Future.sync(() => t.stop?.call());
    } catch (_) {/* ignore */}
    if (_state == ShivaPhase3State.speaking) {
      _state = ShivaPhase3State.idle;
      _safeNotify();
    }
  }

  Future<void> cancelAll() async {
    _sessionId++; // invalidate in-flight
    await _speechSub?.cancel();
    _speechSub = null;
    try {
      final dynamic s = speechService;
      // ignore: avoid_dynamic_calls
      await Future.sync(() => s.stop?.call());
    } catch (_) {/* ignore */}
    try {
      final dynamic t = ttsService;
      // ignore: avoid_dynamic_calls
      await Future.sync(() => t.stop?.call());
    } catch (_) {/* ignore */}
    _state = ShivaPhase3State.idle;
    _safeNotify();
  }
}
