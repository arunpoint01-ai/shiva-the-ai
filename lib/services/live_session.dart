// SHIVA_W3_LIVE_SESSION
// Thin wrapper over the gemini_live package: one voice-to-voice conversation.
//   mic PCM16 16 kHz  --sendAudio-->  Gemini Live
//   Gemini Live       --onAudio---->  PCM16 24 kHz chunks for the speaker
// The wrapper keeps package types out of the rest of the app.

import 'dart:convert';
import 'dart:typed_data';

import 'package:gemini_live/gemini_live.dart';

import '../config/ai_config.dart';

class ShivaLiveSession {
  ShivaLiveSession({
    this.onAudio,
    this.onInterrupted,
    this.onTurnComplete,
    this.onClosed,
    this.onError,
  });

  /// A chunk of the model's spoken answer (PCM16, 24 kHz, mono).
  final void Function(Uint8List pcm)? onAudio;

  /// The boss started talking over the model: stop playing immediately.
  final void Function()? onInterrupted;

  /// The model finished its answer.
  final void Function()? onTurnComplete;

  final void Function()? onClosed;
  final void Function(String message)? onError;

  LiveSession? _session;

  bool get isOpen => _session != null && !(_session!.isClosed);

  Future<void> connect() async {
    final genAI = GoogleGenAI(apiKey: AiConfig.geminiApiKey);
    _session = await genAI.live.connect(
      LiveConnectParameters(
        model: AiConfig.geminiLiveModel,
        config: GenerationConfig(responseModalities: [Modality.AUDIO]),
        callbacks: LiveCallbacks(
          onOpen: () {},
          onMessage: _onMessage,
          onError: (e, s) => onError?.call('$e'),
          onClose: (code, reason) {
            _session = null;
            onClosed?.call();
          },
        ),
      ),
    );
  }

  void _onMessage(LiveServerMessage m) {
    final content = m.serverContent;
    if (content?.interrupted ?? false) onInterrupted?.call();

    final b64 = m.data;
    if (b64 != null && b64.isNotEmpty) onAudio?.call(base64Decode(b64));

    if (content?.turnComplete ?? false) onTurnComplete?.call();
  }

  /// Sends one microphone chunk (PCM16, 16 kHz, mono).
  void sendAudio(Uint8List pcm) {
    final s = _session;
    if (s != null && !s.isClosed) s.sendAudio(pcm);
  }

  void sendText(String text) {
    final s = _session;
    if (s != null && !s.isClosed) s.sendText(text);
  }

  void close() {
    final s = _session;
    _session = null;
    if (s != null && !s.isClosed) s.close();
  }
}
