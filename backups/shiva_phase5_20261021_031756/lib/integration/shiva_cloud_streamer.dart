// SHIVA_PHASE5_STREAM_V1
// Gemini Live cloud streaming with WebSocket PCM audio.
// Requires GEMINI_API_KEY via --dart-define. Never hardcode keys.

import 'dart:async';
import 'dart:typed_data';
import 'package:gemini_live/gemini_live.dart';

enum ShivaCloudState {
  disconnected,
  connecting,
  connected,
  streaming,
  reconnecting,
  failed,
  closed,
}

class ShivaCloudStreamer {
  final String apiKey;
  GoogleGenAI? _genAI;
  LiveSession? _session;
  ShivaCloudState _state = ShivaCloudState.disconnected;
  final _audioController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<ShivaCloudState>.broadcast();
  int _sessionId = 0;

  ShivaCloudStreamer({required this.apiKey});

  Stream<Uint8List> get audioStream => _audioController.stream;
  Stream<ShivaCloudState> get stateStream => _stateController.stream;
  ShivaCloudState get state => _state;

  void _setState(ShivaCloudState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<bool> connect({String model = 'gemini-3.8-live'}) async {
    if (apiKey.isEmpty) {
      _setState(ShivaCloudState.failed);
      return false;
    }
    _sessionId++;
    final sid = _sessionId;
    _setState(ShivaCloudState.connecting);

    try {
      _genAI = GoogleGenAI(apiKey: apiKey);
      _session = await _genAI!.live.connect(
        LiveConnectParameters(
          model: model,
          config: GenerationConfig(responseModalities: [Modality.AUDIO]),
          callbacks: LiveCallbacks(
            onOpen: () {
              if (sid == _sessionId) _setState(ShivaCloudState.connected);
            },
            onMessage: (message) {
              if (sid != _sessionId) return;
              if (message.serverContent?.interrupted == true) {
                _setState(ShivaCloudState.connected);
                return;
              }
              final parts = message.serverContent?.modelTurn?.parts ?? [];
              for (final p in parts) {
                final data = p.inlineData?.data;
                if (data != null && data.isNotEmpty) {
                  _setState(ShivaCloudState.streaming);
                  _audioController.add(base64Decode(data));
                }
              }
            },
            onError: (e, _) {
              if (sid == _sessionId) _setState(ShivaCloudState.failed);
            },
            onClose: (_, __) {
              if (sid == _sessionId) _setState(ShivaCloudState.closed);
            },
          ),
        ),
      );
      return true;
    } catch (_) {
      _setState(ShivaCloudState.failed);
      return false;
    }
  }

  void sendAudio(Uint8List pcm16k) {
    if (_session == null || _state == ShivaCloudState.failed) return;
    _session!.sendRealtimeAudio(base64Encode(pcm16k));
  }

  Future<void> disconnect() async {
    _sessionId++;
    try { await _session?.close(); } catch (_) {}
    _session = null;
    _setState(ShivaCloudState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _audioController.close();
    await _stateController.close();
  }
}
