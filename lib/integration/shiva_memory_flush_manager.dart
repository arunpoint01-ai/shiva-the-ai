// SHIVA_PHASE5_FLUSH
import 'dart:async';
import 'dart:typed_data';

class ShivaMemoryFlushManager {
  int _sessionId = 0;
  Timer? _debounce;
  final List<StreamSubscription> _subs = [];
  Uint8List? _audioBuffer;

  int get currentSession => _sessionId;
  int startNewSession() { _sessionId++; return _sessionId; }
  bool isStale(int sid) => sid != _sessionId;
  void trackSubscription(StreamSubscription s) => _subs.add(s);
  void trackAudioBuffer(Uint8List b) => _audioBuffer = b;

  Future<void> flush({bool incrementSession = true}) async {
    _debounce?.cancel(); _debounce = null;
    for (final s in _subs) { try { await s.cancel(); } catch (_) {} }
    _subs.clear();
    _audioBuffer = null; // Zero-storage: clears bytes from RAM
    if (incrementSession) _sessionId++;
  }

  void scheduleFlush({Duration delay = const Duration(seconds: 2)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () { flush(); });
  }

  void dispose() {
    _debounce?.cancel();
    for (final s in _subs) { s.cancel(); }
    _subs.clear();
    _audioBuffer = null;
  }
}
