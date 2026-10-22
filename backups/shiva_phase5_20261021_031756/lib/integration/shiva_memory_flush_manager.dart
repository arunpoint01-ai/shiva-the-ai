// SHIVA_PHASE5_FLUSH_V1
// Manages cleanup of application-owned temporary state. Zero persistent media.

import 'dart:async';
import 'dart:typed_data';

class ShivaMemoryFlushManager {
  int _sessionId = 0;
  Timer? _debounceTimer;
  final List<StreamSubscription> _subscriptions = [];
  Uint8List? _audioBuffer;

  int get currentSession => _sessionId;

  int startNewSession() {
    _sessionId++;
    return _sessionId;
  }

  bool isStale(int sessionId) => sessionId != _sessionId;

  void trackSubscription(StreamSubscription sub) {
    _subscriptions.add(sub);
  }

  void trackAudioBuffer(Uint8List buf) {
    _audioBuffer = buf;
  }

  /// Flush all temporary state. Idempotent and safe under concurrency.
  /// Note: Dart GC does not guarantee immediate physical RAM erasure.
  Future<void> flush({bool incrementSession = true}) async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    for (final sub in _subscriptions) {
      try { await sub.cancel(); } catch (_) {}
    }
    _subscriptions.clear();

    _audioBuffer = null;

    if (incrementSession) _sessionId++;
  }

  void scheduleFlush({Duration delay = const Duration(seconds: 2)}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () { flush(); });
  }

  void dispose() {
    _debounceTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _audioBuffer = null;
  }
}
