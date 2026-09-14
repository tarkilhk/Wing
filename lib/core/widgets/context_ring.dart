import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/context_occupancy.dart';
import '../theme/hermes_theme.dart';

/// Server-reported context occupancy, independent of task progress.
class ContextRing extends StatefulWidget {
  const ContextRing({super.key, this.occupancy});

  final ContextOccupancy? occupancy;

  @override
  State<ContextRing> createState() => _ContextRingState();
}

class _ContextRingState extends State<ContextRing>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _buttonFocus = FocusNode(canRequestFocus: false);
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: HermesMotion.fast)
      ..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) _portal.hide();
      });
  }

  @override
  void dispose() {
    _animation.dispose();
    _buttonFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    _animation.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : HermesMotion.fast;
    if (_portal.isShowing && _animation.status != AnimationStatus.reverse) {
      _animation.reverse();
    } else {
      _portal.show();
      _animation.forward();
    }
  }

  Widget _details(BuildContext context, String label, Color color) {
    final tokens = HermesTokens.of(context);
    final media = MediaQuery.of(context);
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return const SizedBox.shrink();
    final origin = box.localToGlobal(Offset.zero);
    final width = math.min(
      260.0,
      math.max(180.0, media.size.width - origin.dx - 12),
    );
    final shift = math.min(0.0, media.size.width - 12 - origin.dx - width);
    final value = widget.occupancy;
    final numbers = MaterialLocalizations.of(context);
    return Positioned.fill(
      child: Stack(
        children: [
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: Offset(shift, -8),
            child: TextFieldTapRegion(
              child: TapRegion(
                groupId: _link,
                onTapOutside: (_) => _animation.reverse(),
                child: FadeTransition(
                  opacity: _animation,
                  child: ScaleTransition(
                    alignment: Alignment.bottomLeft,
                    scale: _animation
                        .drive(CurveTween(curve: HermesMotion.curve))
                        .drive(Tween(begin: .92, end: 1.0)),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: math.max(
                          0,
                          origin.dy - media.padding.top - 16,
                        ),
                      ),
                      child: SizedBox(
                        width: width,
                        child: Material(
                          key: const ValueKey('context-usage-popover'),
                          color: tokens.raised,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: HermesRadius.card,
                            side: BorderSide(color: tokens.border),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(HermesSpacing.md),
                            child: Semantics(
                              label: label,
                              liveRegion: true,
                              excludeSemantics: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Context usage',
                                          style: tokens.typography.label
                                              .copyWith(color: tokens.muted),
                                        ),
                                      ),
                                      if (value != null)
                                        Text(
                                          '${value.percent.round()}%',
                                          style: tokens.typography.label
                                              .copyWith(color: color),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: HermesSpacing.xs),
                                  Text(
                                    value == null
                                        ? label
                                        : '${value.estimated ? '≈ ' : ''}${numbers.formatDecimal(value.used)} / ${numbers.formatDecimal(value.max)} tokens',
                                    style: tokens.typography.body.copyWith(
                                      color: tokens.onSurface,
                                    ),
                                  ),
                                  if (value != null) ...[
                                    const SizedBox(height: HermesSpacing.sm),
                                    LinearProgressIndicator(
                                      value: value.percent.clamp(0, 100) / 100,
                                      minHeight: 3,
                                      color: color,
                                      backgroundColor: tokens.border,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.occupancy;
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

    return TextFieldTapRegion(
      child: TapRegion(
        groupId: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => _details(context, label, color),
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Semantics(
              label: label,
              child: IconButton(
                key: const ValueKey('context-ring-details'),
                focusNode: _buttonFocus,
                onPressed: _toggle,
                icon: CompositedTransformTarget(
                  key: _anchor,
                  link: _link,
                  child: CustomPaint(
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
