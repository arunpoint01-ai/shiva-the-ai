// SHIVA_PHASE5_CONTROLLER_V1
// Orchestrates wake word, intent routing, auth, streaming, TTS, cleanup.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'shiva_intent_router.dart';
import 'shiva_memory_flush_manager.dart';
import 'shiva_boss_auth_gate.dart';
import 'shiva_cloud_streamer.dart';

enum ShivaPhase5State { idle, wake, listening, processing, speaking, error }

class ShivaPhase5Controller extends ChangeNotifier {
  final ShivaMemoryFlushManager _flush = ShivaMemoryFlushManager();
  final ShivaBossAuthGate _authGate = ShivaBossAuthGate();
  ShivaCloudStreamer? _streamer;

  ShivaPhase5State _state = ShivaPhase5State.idle;
  ShivaPhase5State get state => _state;

  String _locale = 'en-IN';
  String get locale => _locale;

  String _lastAck = '';
  String get lastAck => _lastAck;

  bool _wakeActive = false;
  int _wakeSession = 0;
  bool _disposed = false;

  void _setState(ShivaPhase5State s) {
    if (_state == s) return;
    _state = s;
    if (!_disposed) notifyListeners();
  }

  void setLocale(String loc) {
    if (const {'mr-IN', 'hi-IN', 'en-IN'}.contains(loc)) {
      _locale = loc;
      notifyListeners();
    }
  }

  String _greeting() {
    if (_locale == 'mr-IN') return 'हाय बॉस, काय करू?';
    if (_locale == 'hi-IN') return 'हाय बॉस, क्या करूं?';
    return 'Hi Boss, what should I do?';
  }

  /// Called when wake word detected. Returns greeting text to speak.
  String onWakeWordDetected() {
    _wakeSession++;
    _wakeActive = true;
    _setState(ShivaPhase5State.wake);
    final greet = _greeting();
    _lastAck = greet;
    return greet;
  }

  Future<ShivaIntentResult?> processCommand(String rawText) async {
    final result = ShivaIntentRouter.route(rawText);

    switch (result.intent) {
      case ShivaIntent.stop:
        await stopAll();
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.cancel:
        await stopAll();
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.changeLanguage:
        if (result.targetLanguage != null) setLocale(result.targetLanguage!);
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.downloadMedia:
        // DENY: Guest cannot download. Boss auth required.
        final isBoss = await _authGate.authenticateBoss();
        if (!isBoss) {
          _lastAck = 'Download not authorized. Boss authentication required.';
          _setState(ShivaPhase5State.error);
          return result;
        }
        _lastAck = 'Download authorized.';
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.playMedia:
        _lastAck = 'Playing now...';
        _setState(ShivaPhase5State.processing);
        // Media discovery not wired to a provider in this phase.
        _lastAck = 'Media provider not configured.';
        _setState(ShivaPhase5State.error);
        return result;
      case ShivaIntent.spiritualQuestion:
        _lastAck = 'Looking that up...';
        _setState(ShivaPhase5State.processing);
        return result;
      case ShivaIntent.unknown:
        _lastAck = 'Command not recognized.';
        _setState(ShivaPhase5State.idle);
        return result;
    }
  }

  Future<void> connectCloudStreamer(String apiKey) async {
    if (apiKey.isEmpty) {
      _setState(ShivaPhase5State.error);
      return;
    }
    _streamer = ShivaCloudStreamer(apiKey: apiKey);
    final ok = await _streamer!.connect();
    if (!ok) _setState(ShivaPhase5State.error);
  }

  Future<void> stopAll() async {
    _flush.startNewSession();
    await _streamer?.disconnect();
    _wakeActive = false;
    _lastAck = '';
    _setState(ShivaPhase5State.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _flush.dispose();
    _streamer?.dispose();
    super.dispose();
  }
}
