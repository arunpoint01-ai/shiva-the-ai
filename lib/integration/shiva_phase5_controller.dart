// SHIVA_PHASE5_CONTROLLER
import 'package:flutter/foundation.dart';
import 'shiva_intent_router.dart';
import 'shiva_memory_flush_manager.dart';
import 'shiva_boss_auth_gate.dart';
import 'shiva_cloud_streamer.dart';

enum ShivaPhase5State { idle, wake, listening, processing, speaking, streaming, error }

class ShivaPhase5Controller extends ChangeNotifier {
  final ShivaMemoryFlushManager _flush = ShivaMemoryFlushManager();
  final ShivaBossAuthGate _authGate = ShivaBossAuthGate();
  ShivaCloudStreamer? _streamer;
  ShivaPhase5State _state = ShivaPhase5State.idle;
  String _locale = 'mr-IN';
  String _lastAck = '';
  bool _disposed = false;

  ShivaPhase5State get state => _state;
  String get lastAck => _lastAck;

  void _setState(ShivaPhase5State s) {
    if (_state == s) return;
    _state = s;
    if (!_disposed) notifyListeners();
  }

  // 1. Wake Word Trigger
  String onWakeWordDetected() {
    _flush.startNewSession();
    _setState(ShivaPhase5State.wake);
    if (_locale == 'mr-IN') _lastAck = 'हाय बॉस, काय करू?';
    else if (_locale == 'hi-IN') _lastAck = 'हाय बॉस, क्या करूं?';
    else _lastAck = 'Hi Boss, what should I do?';
    return _lastAck;
  }

  // 2. Process Commands
  Future<ShivaIntentResult?> processCommand(String raw) async {
    final result = ShivaIntentRouter.route(raw);
    
    switch (result.intent) {
      case ShivaIntent.stop:
      case ShivaIntent.cancel:
        await stopAll();
        return result;

      case ShivaIntent.playMedia:
        // 2 & 3. Acknowledge immediately & stream in background
        _lastAck = 'गणपती आरती लावत आहे...';
        _setState(ShivaPhase5State.processing);
        // In real app, trigger ShivaCloudStreamer or MediaPlayer here
        return result;

      case ShivaIntent.spiritualQuestion:
        // 5. Cloud Religious Knowledge
        _lastAck = 'श्लोक शोधत आहे...';
        _setState(ShivaPhase5State.processing);
        return result;

      case ShivaIntent.downloadMedia:
        // 6. Boss-Only Auth Gate
        final isBoss = await _authGate.authenticateBoss();
        if (!isBoss) {
          _lastAck = 'क्षमस्व, डाऊनलोडसाठी फक्त बॉसची परवानगी आहे.';
          _setState(ShivaPhase5State.error);
        } else {
          _lastAck = 'डाऊनलोड सुरू करत आहे...';
          _setState(ShivaPhase5State.idle);
        }
        return result;

      default:
        _lastAck = 'कमांड समजली नाही.';
        _setState(ShivaPhase5State.idle);
        return result;
    }
  }

  // Interruption Handling
  Future<void> stopAll() async {
    _flush.startNewSession(); // 4. Auto Cleanup
    await _streamer?.disconnect(); // Stop live audio
    _lastAck = 'थांबवले.';
    _setState(ShivaPhase5State.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _flush.dispose();
    _streamer?.disconnect();
    super.dispose();
  }
}
