// SHIVA_W2_AUDIO_INPUT
// Microphone -> 16 kHz, mono, 16-bit PCM chunks (the format Gemini Live expects).
// Echo cancellation, noise suppression and auto gain are requested from Android.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioInput {
  static const int sampleRate = 16000;

  AudioRecorder? _rec;
  AudioRecorder get _r => _rec ??= AudioRecorder();

  /// Asks for the microphone permission if needed.
  Future<bool> hasPermission() => _r.hasPermission();

  /// Starts the microphone and returns a stream of PCM16 chunks.
  Future<Stream<Uint8List>> start() {
    return _r.startStream(RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ));
  }

  Future<void> stop() async {
    final r = _rec;
    if (r == null) return;
    if (await r.isRecording()) await r.stop();
  }

  Future<void> dispose() async {
    final r = _rec;
    _rec = null;
    if (r != null) await r.dispose();
  }
}
