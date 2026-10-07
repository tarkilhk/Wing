import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/chat_intelligence.dart';
import '../presentation/chat_model_labels.dart';
import '../theme/wing_theme.dart';

const _shortEfforts = {
  'none': 'Off',
  'minimal': 'Min',
  'low': 'Low',
  'medium': 'Med',
  'high': 'High',
  'xhigh': 'XHigh',
  'max': 'Max',
  'ultra': 'Ultra',
};
const _effortBadges = {
  'none': '0',
  'minimal': 'm',
  'low': 'L',
  'medium': 'M',
  'high': 'H',
  'xhigh': 'X',
  'max': '+',
  'ultra': 'U',
};

/// A small face inside a full touch target; the level menu appears only on intent.
class ChatReasoningControl extends StatelessWidget {
  const ChatReasoningControl({
    required this.effort,
    required this.onChanged,
    required this.canDisable,
    super.key,
  });
  final String effort;
  final bool canDisable;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    return Builder(
      builder: (anchor) => IconButton(
        key: const Key('chat-reasoning-control'),
        tooltip: 'Reasoning: ${chatReasoningEffortLabel(effort)}',
        onPressed: onChanged == null
            ? null
            : () async {
                final box = anchor.findRenderObject() as RenderBox;
                final origin = box.localToGlobal(Offset.zero);
                final size = MediaQuery.sizeOf(context);
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final width = math.min(
                  scale > 1.3 ? 272.0 : 218.0,
                  size.width - 16,
                );
                final height = math.max(108.0, 108 * scale / 1.5);
                final left = (origin.dx - 8).clamp(
                  8.0,
                  math.max(8.0, size.width - width - 8),
                );
                final top = origin.dy >= height + 8
                    ? origin.dy - height - 4
                    : origin.dy + box.size.height + 4;
                final value = await showDialog<String>(
                  context: context,
                  barrierColor: Colors.transparent,
                  builder: (menuContext) => Stack(
                    children: [
                      Positioned(
                        left: left.toDouble(),
                        top: top.toDouble().clamp(
                          8.0,
                          math.max(8.0, size.height - height - 8),
                        ),
                        width: width,
                        child: Material(
                          key: const Key('reasoning-menu'),
                          elevation: 0,
                          color: tokens.raised,
                          shape: RoundedRectangleBorder(
                            borderRadius: WingRadius.card,
                            side: BorderSide(color: tokens.border),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: FocusTraversalGroup(
                              child: Wrap(
                                children: [
                                  for (final entry in _shortEfforts.entries)
                                    if (canDisable || entry.key != 'none')
                                      SizedBox(
                                        width: (width - 8) / 4,
                                        height: (height - 8) / 2,
                                        child: Semantics(
                                          selected: entry.key == effort,
                                          label:
                                              'Reasoning ${chatReasoningEffortLabel(entry.key)}',
                                          child: Tooltip(
                                            message: chatReasoningEffortLabel(
                                              entry.key,
                                            ),
                                            child: TextButton(
                                              key: Key(
                                                'reasoning-${entry.key}',
                                              ),
                                              autofocus: entry.key == effort,
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                minimumSize: const Size(48, 48),
                                                foregroundColor:
                                                    entry.key == effort
                                                    ? tokens.accent
                                                    : tokens.onSurface,
                                                backgroundColor:
                                                    entry.key == effort
                                                    ? tokens.accent.withValues(
                                                        alpha: 0.12,
                                                      )
                                                    : Colors.transparent,
                                                textStyle:
                                                    tokens.typography.label,
                                              ),
                                              onPressed: () => Navigator.pop(
                                                menuContext,
                                                entry.key,
                                              ),
                                              child: Text(
                                                scale > 1.3 &&
                                                        entry.key == 'xhigh'
                                                    ? 'XHi'
                                                    : entry.value,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (value != null) onChanged?.call(value);
              },
        icon: SizedBox.square(
          dimension: 32,
          child: Stack(
            children: [
              Center(
                child: CircuitBrainIcon(
                  color: onChanged == null ? tokens.muted : tokens.accent,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: tokens.raised,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _effortBadges[effort] ?? '',
                    style: tokens.typography.label.copyWith(
                      fontSize: 10,
                      color: tokens.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatFastControl extends StatelessWidget {
  const ChatFastControl({
    required this.mode,
    required this.onChanged,
    this.showLabel = false,
    super.key,
  });
  final ChatFastMode mode;
  final ValueChanged<ChatFastMode>? onChanged;
  final bool showLabel;
  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final icon = Icon(
      mode.enabled ? Icons.bolt : Icons.bolt_outlined,
      size: 22,
    );
    void toggle() =>
        onChanged?.call(mode.enabled ? ChatFastMode.normal : ChatFastMode.fast);
    final style = TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: mode.enabled ? tokens.accent : tokens.muted,
      backgroundColor: mode.enabled
          ? tokens.accent.withValues(alpha: 0.12)
          : Colors.transparent,
    );
    return Tooltip(
      message: 'Fast: ${mode.enabled ? 'On' : 'Off'}',
      child: Semantics(
        toggled: mode.enabled,
        label: 'Fast mode',
        child: TextButton(
          key: const Key('chat-fast-control'),
          onPressed: onChanged == null ? null : toggle,
          style: style,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (showLabel)
                Text(
                  mode.enabled ? 'On' : 'Off',
                  style: tokens.typography.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circuit brain stroke artwork, following the existing Lucide icon language.
class CircuitBrainIcon extends StatelessWidget {
  const CircuitBrainIcon({required this.color, super.key});
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(22),
    painter: _CircuitBrainPainter(color),
  );
}

class _CircuitBrainPainter extends CustomPainter {
  _CircuitBrainPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(12, 5)
      ..cubicTo(12, 1, 6, 1, 6, 5.125)
      ..cubicTo(2, 5, 1, 8.5, 3.477, 10.896)
      ..cubicTo(0, 13, 1, 16, 4.033, 17.484)
      ..cubicTo(3, 23, 12, 24, 12, 18)
      ..close()
      ..moveTo(9, 13)
      ..cubicTo(11, 12.5, 12, 10.5, 12, 9)
      ..moveTo(6.003, 5.125)
      ..lineTo(6.401, 6.5)
      ..moveTo(3.477, 10.896)
      ..lineTo(4.062, 10.5)
      ..moveTo(6, 18)
      ..lineTo(4.033, 17.484)
      ..moveTo(12, 13)
      ..lineTo(16, 13)
      ..moveTo(12, 18)
      ..lineTo(18, 18)
      ..quadraticBezierTo(20, 18, 20, 20)
      ..lineTo(20, 21)
      ..moveTo(12, 8)
      ..lineTo(20, 8)
      ..moveTo(16, 8)
      ..lineTo(16, 5)
      ..quadraticBezierTo(16, 3, 18, 3);
    canvas.drawPath(path, pen);
    for (final point in [
      const Offset(16, 13),
      const Offset(18, 3),
      const Offset(20, 21),
      const Offset(20, 8),
    ]) {
      canvas.drawCircle(point, 0.5, pen);
    }
  }

  @override
  bool shouldRepaint(_CircuitBrainPainter oldDelegate) =>
      oldDelegate.color != color;
}
