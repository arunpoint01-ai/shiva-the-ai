// SHIVA_CORE_V1
// The single "brain" of Shiva. The UI owns the microphone/speaker
// (VoiceEngine); ShivaCore decides what a command means and what to answer.
//
// Rules enforced here:
//  * every new command starts a new session; older in-flight work is dropped
//  * interrupt() / finishCommand() flush temporary state (zero-bloat rule)
//  * sensitive actions go through the boss auth gate (deny-by-default)

import 'dart:typed_data';

import '../config/ai_config.dart';
import '../integration/shiva_boss_auth_gate.dart';
import '../integration/shiva_intent_router.dart';
import '../integration/shiva_memory_flush_manager.dart';
import '../services/audio_input.dart';
import '../services/audio_output.dart';
import '../services/gemini_service.dart';
import '../voice_engine.dart' show VoiceLanguage;

class ShivaReply {
  const ShivaReply(this.text, this.intent, {this.switchTo, this.stopAudio = false});

  final String text;
  final ShivaIntent intent;
  final VoiceLanguage? switchTo;
  final bool stopAudio;
}

class ShivaCore {
  ShivaCore({GeminiService? gemini, ShivaBossAuthGate? auth, ShivaMemoryFlushManager? flush})
      : _gemini = gemini,
        _auth = auth ?? ShivaBossAuthGate(),
        _flush = flush ?? ShivaMemoryFlushManager();

  GeminiService? _gemini;
  AudioInput? _input;
  AudioOutput? _output;
  final ShivaBossAuthGate _auth;
  final ShivaMemoryFlushManager _flush;

  GeminiService get _ai => _gemini ??= GeminiService();

  /// Handles one spoken command. Returns null if a newer command or an
  /// interruption made this one stale (nothing should be spoken then).
  Future<ShivaReply?> handle(
    String raw,
    VoiceLanguage lang, {
    String? Function(String raw)? quickReply,
  }) async {
    final sid = _flush.startNewSession();
    final result = ShivaIntentRouter.route(raw);

    switch (result.intent) {
      case ShivaIntent.stop:
      case ShivaIntent.cancel:
        return ShivaReply(_t(lang, 'stopped'), result.intent, stopAudio: true);

      case ShivaIntent.changeLanguage:
        final target = _langFor(result.targetLanguage) ?? lang;
        return ShivaReply(_t(target, 'lang_switched'), result.intent, switchTo: target);

      case ShivaIntent.playMedia:
        // Real media playback arrives in step W6. Be honest until then.
        return ShivaReply(_t(lang, 'media_pending'), result.intent);

      case ShivaIntent.downloadMedia:
        final ok = await _auth.authenticateBoss();
        if (_flush.isStale(sid)) return null;
        return ShivaReply(_t(lang, ok ? 'download_pending' : 'download_denied'), result.intent);

      case ShivaIntent.audioTest:
        return _audioTest(sid, lang, result.intent);

      case ShivaIntent.spiritualQuestion:
      case ShivaIntent.unknown:
        final quick = result.intent == ShivaIntent.unknown ? quickReply?.call(raw) : null;
        if (quick != null) return ShivaReply(quick, result.intent);
        return _askAi(sid, raw, lang, result.intent);
    }
  }

  Future<ShivaReply?> _askAi(int sid, String raw, VoiceLanguage lang, ShivaIntent intent) async {
    if (!AiConfig.hasApiKey) return ShivaReply(_t(lang, 'ai_unavailable'), intent);

    final question = ShivaIntentRouter.stripWakeWord(raw);
    final prompt = 'You are Shiva, a calm voice assistant speaking to your boss. '
        'Answer in ${_langName(lang)} in at most three short sentences. '
        'Plain text only: no markdown, lists or emojis. '
        'If asked about a scripture, give the verse idea and its meaning.\n\n'
        'Boss: $question';
    try {
      final answer = await _ai.generateResponse(prompt);
      if (_flush.isStale(sid)) return null;
      return ShivaReply(answer, intent);
    } catch (_) {
      if (_flush.isStale(sid)) return null;
      return ShivaReply(_t(lang, 'ai_error'), intent);
    }
  }

  /// Records 3 seconds from the microphone, plays it back and reports the level.
  /// Proves the W2 audio path: permission -> 16 kHz PCM in -> PCM out.
  Future<ShivaReply?> _audioTest(int sid, VoiceLanguage lang, ShivaIntent intent) async {
    final input = _input ??= AudioInput();
    final output = _output ??= AudioOutput();
    final chunks = <Uint8List>[];
    try {
      if (!await input.hasPermission()) return ShivaReply(_t(lang, 'mic_denied'), intent);

      final stream = await input.start();
      final sub = stream.listen(chunks.add);
      _flush.trackSubscription(sub);
      await Future<void>.delayed(const Duration(seconds: 3));
      await input.stop();
      await sub.cancel();
      if (_flush.isStale(sid)) return null;

      var peak = 0;
      var bytes = 0;
      for (final c in chunks) {
        bytes += c.length;
        final view = ByteData.sublistView(c);
        for (var i = 0; i + 1 < c.length; i += 2) {
          final v = view.getInt16(i, Endian.little).abs();
          if (v > peak) peak = v;
        }
      }
      final level = (peak * 100 / 32768).round();
      if (peak < 300) return ShivaReply(_t(lang, 'audio_test_silent'), intent);

      await output.start(sampleRate: AudioInput.sampleRate);
      for (final c in chunks) {
        await output.push(c);
      }
      output.finish();
      final playMs = bytes * 1000 ~/ (AudioInput.sampleRate * 2);
      await Future<void>.delayed(Duration(milliseconds: playMs + 400));
      await output.interrupt();
      if (_flush.isStale(sid)) return null;
      return ShivaReply(_t(lang, 'audio_test_done').replaceFirst('{p}', '$level'), intent);
    } catch (_) {
      await output.interrupt();
      if (_flush.isStale(sid)) return null;
      return ShivaReply(_t(lang, 'audio_test_failed'), intent);
    } finally {
      chunks.clear();
    }
  }

  /// User stopped Shiva or left the app: drop in-flight work and clear temp state.
  Future<void> interrupt() async {
    await _flush.flush();
    await _output?.interrupt();
    await _input?.stop();
  }

  /// The reply finished speaking: clear temp buffers (zero-bloat rule).
  Future<void> finishCommand() => _flush.flush(incrementSession: false);

  void dispose() {
    _flush.dispose();
    _gemini?.dispose();
    _input?.dispose();
    _output?.dispose();
  }

  static VoiceLanguage? _langFor(String? code) {
    switch (code) {
      case 'mr-IN':
        return VoiceLanguage.marathi;
      case 'hi-IN':
        return VoiceLanguage.hindi;
      case 'en-IN':
        return VoiceLanguage.english;
    }
    return null;
  }

  static String _langName(VoiceLanguage l) {
    switch (l) {
      case VoiceLanguage.marathi:
        return 'Marathi';
      case VoiceLanguage.hindi:
        return 'Hindi';
      case VoiceLanguage.english:
        return 'English';
    }
  }

  static String _t(VoiceLanguage lang, String key) =>
      _strings[lang]?[key] ?? _strings[VoiceLanguage.english]![key]!;

  static const Map<VoiceLanguage, Map<String, String>> _strings = {
    VoiceLanguage.marathi: {
      'mic_denied': 'मायक्रोफोन परवानगी नाही. Android सेटिंग्जमध्ये ती सुरू करा.',
      'audio_test_done': 'ऑडिओ टेस्ट पूर्ण. आवाजाची पातळी {p} टक्के.',
      'audio_test_silent': 'काही आवाज मिळाला नाही. मायक्रोफोन तपासा.',
      'audio_test_failed': 'ऑडिओ टेस्ट अयशस्वी झाली.',
      'stopped': 'ठीक आहे, थांबवले.',
      'lang_switched': 'ठीक आहे, आता मराठीत बोलतो.',
      'media_pending': 'मीडिया प्लेअर अजून तयार नाही. तो पुढील टप्प्यात जोडला जाईल.',
      'download_denied': 'क्षमस्व, डाऊनलोडसाठी फक्त बॉसची परवानगी आहे.',
      'download_pending': 'ओळख पटली. डाऊनलोड सुविधा अजून तयार नाही.',
      'ai_unavailable': 'हा आदेश मला अजून समजत नाही. संवादासाठी AI की जोडलेली नाही.',
      'ai_error': 'AI शी संपर्क होऊ शकला नाही. थोड्या वेळाने पुन्हा प्रयत्न करा.',
    },
    VoiceLanguage.hindi: {
      'mic_denied': 'माइक्रोफोन की अनुमति नहीं है। Android सेटिंग्स में उसे चालू करें।',
      'audio_test_done': 'ऑडियो टेस्ट पूरा हुआ। आवाज़ का स्तर {p} प्रतिशत।',
      'audio_test_silent': 'कोई आवाज़ नहीं मिली। माइक्रोफोन जाँचें।',
      'audio_test_failed': 'ऑडियो टेस्ट विफल रहा।',
      'stopped': 'ठीक है, रोक दिया।',
      'lang_switched': 'ठीक है, अब हिंदी में बोलूँगा।',
      'media_pending': 'मीडिया प्लेयर अभी तैयार नहीं है। वह अगले चरण में जुड़ेगा।',
      'download_denied': 'क्षमा करें, डाउनलोड के लिए केवल बॉस की अनुमति है।',
      'download_pending': 'पहचान हो गई। डाउनलोड सुविधा अभी तैयार नहीं है।',
      'ai_unavailable': 'यह आदेश मुझे अभी समझ नहीं आया। बातचीत के लिए AI कुंजी नहीं जुड़ी है।',
      'ai_error': 'AI से संपर्क नहीं हो सका। थोड़ी देर बाद फिर कोशिश करें।',
    },
    VoiceLanguage.english: {
      'mic_denied': 'Microphone permission is not granted. Enable it in Android settings.',
      'audio_test_done': 'Audio test done. Voice level {p} percent.',
      'audio_test_silent': 'I did not pick up any sound. Check the microphone.',
      'audio_test_failed': 'The audio test failed.',
      'stopped': 'Okay, stopped.',
      'lang_switched': 'Okay, switching to English.',
      'media_pending': 'The media player is not ready yet. It will be added in a later step.',
      'download_denied': 'Sorry, downloads are allowed for the boss only.',
      'download_pending': 'Verified. The download feature is not ready yet.',
      'ai_unavailable': 'I do not understand that yet. The AI key is not configured.',
      'ai_error': 'I could not reach the AI service. Please try again shortly.',
    },
  };
}
