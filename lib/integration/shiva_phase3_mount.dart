// SHIVA_PHASE3_MOUNT_V1
import 'package:flutter/material.dart';
import 'shiva_phase3_controller.dart';
import 'shiva_phase3_widgets.dart';
import '../services/gemini_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';

class ShivaPhase3Mount {
  ShivaPhase3Mount._();

  static Widget build({
    required SpeechService speechService,
    required GeminiService geminiService,
    required TtsService ttsService,
  }) {
    return _ShivaPhase3MountHost(
      speechService: speechService,
      geminiService: geminiService,
      ttsService: ttsService,
    );
  }
}

class _ShivaPhase3MountHost extends StatefulWidget {
  const _ShivaPhase3MountHost({
    required this.speechService,
    required this.geminiService,
    required this.ttsService,
  });

  final SpeechService speechService;
  final GeminiService geminiService;
  final TtsService ttsService;

  @override
  State<_ShivaPhase3MountHost> createState() => _ShivaPhase3MountHostState();
}

class _ShivaPhase3MountHostState extends State<_ShivaPhase3MountHost> {
  late final ShivaPhase3Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShivaPhase3Controller(
      speechService: widget.speechService,
      geminiService: widget.geminiService,
      ttsService: widget.ttsService,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShivaPhase3Panel(controller: _controller);
  }
}
