import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/context_occupancy.dart';
import '../theme/hermes_theme.dart';

/// Server-reported context occupancy, independent of task progress.
class ContextRing extends StatelessWidget {
  const ContextRing({super.key, this.occupancy});

  final ContextOccupancy? occupancy;

  @override
  Widget build(BuildContext context) {
    final value = occupancy;
    final tokens = HermesTokens.of(context);
    final label = value == null
        ? 'Context usage unknown'
        : '${value.estimated ? 'Approximately ' : ''}${value.used} of ${value.max} tokens, ${value.percent.round()} percent used';
    final color = value == null
        ? tokens.muted
        : value.percent >= 85
        ? tokens.danger
        : value.percent >= 65
        ? tokens.warning
        : tokens.accent;

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: IconButton(
          key: const ValueKey('context-ring-details'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Context usage'),
              content: Text(label),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          icon: CustomPaint(
            key: const ValueKey('context-ring-paint'),
            size: const Size.square(18),
            painter: ContextRingPainter(
              progress: value == null
                  ? null
                  : value.percent.clamp(0, 100) / 100,
              color: color,
              track: tokens.muted.withValues(alpha: .5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Null occupancy is a broken neutral track, never a zero-percent arc.
class ContextRingPainter extends CustomPainter {
  const ContextRingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double? progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final ring = bounds.deflate(1.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = track;
    if (progress == null) {
      for (var i = 0; i < 3; i++) {
        canvas.drawArc(
          ring,
          -math.pi / 2 + i * math.pi * 2 / 3,
          math.pi / 2,
          false,
          paint,
        );
      }
      return;
    }
    canvas.drawOval(ring, paint);
    if (progress! > 0) {
      paint
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(ring, -math.pi / 2, math.pi * 2 * progress!, false, paint);
    }
  }

  @override
  bool shouldRepaint(ContextRingPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      track != oldDelegate.track;
}
