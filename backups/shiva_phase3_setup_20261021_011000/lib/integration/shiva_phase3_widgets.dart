// SHIVA_PHASE3_WIDGETS_v1
// Additive UI helpers. Drop into the HUD wherever convenient.
// These widgets assume a ShivaPhase3Controller is provided.

import 'package:flutter/material.dart';
import 'shiva_phase3_controller.dart';

class ShivaMicButton extends StatelessWidget {
  final ShivaPhase3Controller controller;
  const ShivaMicButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final listening = controller.state == ShivaPhase3State.listening;
        final processing = controller.state == ShivaPhase3State.processing;
        final speaking = controller.state == ShivaPhase3State.speaking;
        final icon = listening
            ? Icons.stop_circle
            : speaking
                ? Icons.volume_off
                : Icons.mic;
        final onTap = () async {
          if (listening) {
            await controller.stopListening();
          } else if (speaking) {
            await controller.stopSpeaking();
          } else if (!processing) {
            await controller.startListening();
          }
        };
        return FloatingActionButton(
          onPressed: processing ? null : onTap,
          tooltip: listening
              ? 'Stop listening'
              : speaking
                  ? 'Stop speaking'
                  : 'Start listening',
          child: Icon(icon),
        );
      },
    );
  }
}

class ShivaStatusBanner extends StatelessWidget {
  final ShivaPhase3Controller controller;
  const ShivaStatusBanner({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final s = controller.state;
        String label;
        switch (s) {
          case ShivaPhase3State.idle:       label = 'Idle';        break;
          case ShivaPhase3State.listening:  label = 'Listening…';  break;
          case ShivaPhase3State.processing: label = 'Thinking…';   break;
          case ShivaPhase3State.speaking:   label = 'Speaking…';   break;
          case ShivaPhase3State.error:      label = 'Error';       break;
        }
        final sub = s == ShivaPhase3State.error && controller.errorMessage.isNotEmpty
            ? controller.errorMessage
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            if (sub != null)
              Text(sub, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        );
      },
    );
  }
}

class ShivaTranscriptView extends StatelessWidget {
  final ShivaPhase3Controller controller;
  const ShivaTranscriptView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final partial = controller.partialTranscript;
        final finalText = controller.finalTranscript;
        final response = controller.response;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (partial.isNotEmpty) Text('You: $partial'),
            if (finalText.isNotEmpty && finalText != partial) Text('You: $finalText'),
            if (response.isNotEmpty) Text('Shiva: $response'),
          ],
        );
      },
    );
  }
}
