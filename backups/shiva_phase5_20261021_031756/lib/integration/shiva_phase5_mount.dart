// SHIVA_PHASE5_MOUNT_V1
// Drop-in widget to mount Phase 5 controller with existing services.

import 'package:flutter/material.dart';
import 'shiva_phase5_controller.dart';

class ShivaPhase5Mount extends StatefulWidget {
  const ShivaPhase5Mount({super.key});
  @override
  State<ShivaPhase5Mount> createState() => _ShivaPhase5MountState();
}

class _ShivaPhase5MountState extends State<ShivaPhase5Mount> {
  late final ShivaPhase5Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShivaPhase5Controller();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Phase 5: ${_controller.state.name}'),
            if (_controller.lastAck.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_controller.lastAck),
              ),
          ],
        );
      },
    );
  }
}
