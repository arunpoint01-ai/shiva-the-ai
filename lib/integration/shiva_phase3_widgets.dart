// SHIVA_PHASE3_WIDGETS_V1
// Phase 3 UI widgets for Shiva AI assistant (JARVIS-inspired).
// Additive: does NOT create a second main() and does NOT alter global theme.

import 'package:flutter/material.dart';
import 'shiva_phase3_controller.dart';

class ShivaPhase3Palette {
  static const Color bg      = Color(0xFF060A18);
  static const Color panel   = Color(0xFF0E1530);
  static const Color accent  = Color(0xFF00E5FF);
  static const Color accent2 = Color(0xFF3D7BFF);
  static const Color text    = Color(0xFFE6F1FF);
  static const Color muted   = Color(0xFF8FA3C7);
  static const Color error   = Color(0xFFFF4D6D);
}

class ShivaStatusIndicator extends StatelessWidget {
  const ShivaStatusIndicator({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  String _label() {
    switch (controller.state) {
      case ShivaAssistantState.idle:       return 'IDLE';
      case ShivaAssistantState.listening:  return 'LISTENING';
      case ShivaAssistantState.processing: return 'PROCESSING';
      case ShivaAssistantState.speaking:   return 'SPEAKING';
      case ShivaAssistantState.error:      return 'ERROR';
    }
  }

  Color _color() {
    switch (controller.state) {
      case ShivaAssistantState.error:      return ShivaPhase3Palette.error;
      case ShivaAssistantState.idle:       return ShivaPhase3Palette.muted;
      default:                             return ShivaPhase3Palette.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _color(),
                boxShadow: [
                  BoxShadow(color: _color().withOpacity(0.7), blurRadius: 12, spreadRadius: 2),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _label(),
              style: TextStyle(
                color: _color(),
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ShivaLanguageSelector extends StatelessWidget {
  const ShivaLanguageSelector({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: ShivaPhase3Palette.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ShivaPhase3Palette.accent2.withOpacity(0.4)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: controller.locale,
              isDense: true,
              dropdownColor: ShivaPhase3Palette.panel,
              iconEnabledColor: ShivaPhase3Palette.accent,
              style: const TextStyle(color: ShivaPhase3Palette.text, fontSize: 13),
              items: ShivaPhase3Controller.supportedLocales.entries
                  .map((e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text('${e.value} (${e.key})'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) controller.setLocale(v);
              },
            ),
          ),
        );
      },
    );
  }
}

class ShivaVoiceOrb extends StatelessWidget {
  const ShivaVoiceOrb({super.key, required this.controller, this.size = 96});
  final ShivaPhase3Controller controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final s = controller.state;
        final active = s == ShivaAssistantState.listening || s == ShivaAssistantState.speaking;
        final isError = s == ShivaAssistantState.error;
        final color = isError
            ? ShivaPhase3Palette.error
            : (active ? ShivaPhase3Palette.accent : ShivaPhase3Palette.accent2);
        final icon = (s == ShivaAssistantState.listening)
            ? Icons.mic
            : (s == ShivaAssistantState.speaking
                ? Icons.volume_up
                : (s == ShivaAssistantState.processing
                    ? Icons.autorenew
                    : Icons.graphic_eq));
        return SizedBox(
          width: size, height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    color.withOpacity(0.28),
                    color.withOpacity(0.05),
                  ]),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.5), blurRadius: active ? 26 : 12, spreadRadius: active ? 4 : 1),
                  ],
                ),
              ),
              Container(
                width: size * 0.72, height: size * 0.72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ShivaPhase3Palette.panel,
                  border: Border.all(color: color, width: 1.6),
                ),
                child: Icon(icon, color: color, size: size * 0.36),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ShivaTranscriptCard extends StatelessWidget {
  const ShivaTranscriptCard({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final partial = controller.partialTranscript;
        final finalText = controller.finalTranscript;
        final response = controller.response;
        final err = controller.errorMessage;
        if (partial.isEmpty && finalText.isEmpty && response.isEmpty && err.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _panelDecoration(),
            child: const Text(
              'Say "Shiva" or tap the microphone to begin.',
              style: TextStyle(color: ShivaPhase3Palette.muted),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (partial.isNotEmpty && finalText.isEmpty)
                _line('YOU (partial)', partial, ShivaPhase3Palette.accent),
              if (finalText.isNotEmpty)
                _line('YOU', finalText, ShivaPhase3Palette.accent),
              if (response.isNotEmpty) ...[
                const SizedBox(height: 8),
                _line('SHIVA', response, ShivaPhase3Palette.text),
              ],
              if (err.isNotEmpty) ...[
                const SizedBox(height: 8),
                _line('ERROR', err, ShivaPhase3Palette.error),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _line(String label, String text, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: ShivaPhase3Palette.text, height: 1.35)),
      ],
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: ShivaPhase3Palette.panel.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ShivaPhase3Palette.accent2.withOpacity(0.35)),
      );
}

class ShivaQuickActionsRow extends StatelessWidget {
  const ShivaQuickActionsRow({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final listening = controller.state == ShivaAssistantState.listening;
        final speaking = controller.state == ShivaAssistantState.speaking;
        final processing = controller.state == ShivaAssistantState.processing;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _action(
              icon: listening ? Icons.stop : Icons.mic,
              label: listening ? 'STOP' : 'LISTEN',
              onTap: processing ? null : () async {
                if (listening) {
                  await controller.stopListening();
                } else {
                  await controller.beginListening();
                }
              },
            ),
            _action(
              icon: Icons.volume_off,
              label: 'MUTE',
              onTap: speaking ? () async => controller.stopSpeaking() : null,
            ),
            _action(
              icon: Icons.cancel,
              label: 'CANCEL',
              onTap: () async => controller.cancelAll(),
            ),
          ],
        );
      },
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Future<void> Function()? onTap,
  }) {
    final enabled = onTap != null;
    final color = enabled ? ShivaPhase3Palette.accent : ShivaPhase3Palette.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: ShivaPhase3Palette.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShivaPhase3Panel extends StatelessWidget {
  const ShivaPhase3Panel({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ShivaPhase3Palette.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShivaStatusIndicator(controller: controller),
              ShivaLanguageSelector(controller: controller),
            ],
          ),
          const SizedBox(height: 24),
          Center(child: ShivaVoiceOrb(controller: controller)),
          const SizedBox(height: 24),
          ShivaTranscriptCard(controller: controller),
          const SizedBox(height: 20),
          ShivaQuickActionsRow(controller: controller),
        ],
      ),
    );
  }
}
