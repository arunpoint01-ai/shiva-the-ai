// SHIVA_W2_AUDIO_OUTPUT
// Plays raw PCM16 mono chunks straight from RAM (no file is ever written).
// interrupt() stops playback immediately, which is what barge-in needs.

import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

class AudioOutput {
  AudioSource? _source;
  SoundHandle? _handle;
  int _rate = 24000;

  Future<void> _ensureInit() async {
    if (!SoLoud.instance.isInitialized) await SoLoud.instance.init();
  }

  /// Opens a fresh stream. [sampleRate] must match the PCM you push
  /// (24000 for Gemini Live replies, 16000 for the microphone test).
  Future<void> start({int sampleRate = 24000}) async {
    await interrupt();
    await _ensureInit();
    _rate = sampleRate;
    _source = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      sampleRate: _rate,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
  }

  /// Adds one PCM16 little-endian chunk. Playback starts with the first chunk.
  Future<void> push(Uint8List pcm) async {
    final src = _source;
    if (src == null || pcm.isEmpty) return;
    SoLoud.instance.addAudioDataStream(src, pcm);
    _handle ??= await SoLoud.instance.play(src);
  }

  /// No more chunks will come; the stream ends after the buffered audio plays.
  void finish() {
    final src = _source;
    if (src != null) SoLoud.instance.setDataIsEnded(src);
  }

  /// Stops playback now and frees the stream.
  Future<void> interrupt() async {
    final h = _handle;
    final s = _source;
    _handle = null;
    _source = null;
    if (!SoLoud.instance.isInitialized) return;
    if (h != null) {
      try {
        await SoLoud.instance.stop(h);
      } catch (_) {}
    }
    if (s != null) {
      try {
        await SoLoud.instance.disposeSource(s);
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await interrupt();
  }
}
