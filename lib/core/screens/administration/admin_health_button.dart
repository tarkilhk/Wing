import 'package:flutter/material.dart';

import '../../services/administration_health.dart';
import '../../theme/wing_theme.dart';

Color administrationHealthColor(
  BuildContext context,
  AdministrationHealthStatus status,
) {
  final tokens = WingTokens.of(context);
  return switch (status) {
    AdministrationHealthStatus.healthy => tokens.success,
    AdministrationHealthStatus.warning => tokens.warning,
    AdministrationHealthStatus.failure => tokens.danger,
    AdministrationHealthStatus.unknown => Theme.of(context).colorScheme.outline,
  };
}

/// A quiet destination button; status belongs to the border, not the glyph.
class AdminHealthButton extends StatelessWidget {
  const AdminHealthButton({
    super.key,
    required this.health,
    required this.onPressed,
  });
  final AdministrationHealth health;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('administration-health'),
    tooltip: 'Health: ${health.statusLabel}',
    onPressed: onPressed,
    padding: const EdgeInsets.all(6),
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: WingRadius.control,
        border: Border.all(
          color: administrationHealthColor(context, health.status),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size(20, 20),
        painter: _HealthCross(Theme.of(context).colorScheme.onSurface),
      ),
    ),
  );
}

class _HealthCross extends CustomPainter {
  const _HealthCross(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawRect(const Rect.fromLTWH(7, 0, 6, 20), paint);
    canvas.drawRect(const Rect.fromLTWH(0, 7, 20, 6), paint);
  }

  @override
  bool shouldRepaint(_HealthCross oldDelegate) => oldDelegate.color != color;
}
