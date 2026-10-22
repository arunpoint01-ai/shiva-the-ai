// SHIVA_PHASE5_STREAM
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:gemini_live/gemini_live.dart';

enum ShivaCloudState { disconnected, connecting, connected, streaming, failed, closed }

class ShivaCloudStreamer {
  final String apiKey;
  GoogleGenAI? _genAI;
  LiveSession? _session;
  ShivaCloudState _state = ShivaCloudState.disconnected;
  final _audioCtrl = StreamController<Uint8List>.broadcast(); // RAM only
  int _sessionId = 0;

  ShivaCloudStreamer({required this.apiKey});

  Stream<Uint8List> get audioStream => _audioCtrl.stream;
  ShivaCloudState get state => _state;

  Future<bool> connect({String model = 'gemini-3.8-live'}) async {
    if (apiKey.isEmpty) { _state = ShivaCloudState.failed; return false; }
    _sessionId++;
    final sid = _sessionId;
    _state = ShivaCloudState.connecting;
    
    try {
      _genAI = GoogleGenAI(apiKey: apiKey);
      _session = await _genAI!.live.connect(
        LiveConnectParameters(
          model: model,
          config: GenerationConfig(responseModalities: [Modality.AUDIO]),
          callbacks: LiveCallbacks(
            onOpen: () { if (sid == _sessionId) _state = ShivaCloudState.connected; },
            onMessage: (msg) {
              if (sid != _sessionId) return;
              final parts = msg.serverContent?.modelTurn?.parts ?? [];
              for (final p in parts) {
                final data = p.inlineData?.data;
                if (data != null && data.isNotEmpty) {
                  _state = ShivaCloudState.streaming;
                  // Stream directly to audio player (no disk write)
                  _audioCtrl.add(base64Decode(data));
                }
              }
            },
            onError: (e, _) { if (sid == _sessionId) _state = ShivaCloudState.failed; },
            onClose: (_, __) { if (sid == _sessionId) _state = ShivaCloudState.closed; },
          ),
        ),
      );
      return true;
    } catch (_) { _state = ShivaCloudState.failed; return false; }
  }

  void sendAudio(Uint8List pcm16k) {
    if (_session == null || _state == ShivaCloudState.failed) return;
    _session!.sendRealtimeAudio(base64Encode(pcm16k));
  }

  Future<void> disconnect() async {
    _sessionId++;
    try { await _session?.close(); } catch (_) {}
    _session = null;
    _state = ShivaCloudState.disconnected;
  }
}
