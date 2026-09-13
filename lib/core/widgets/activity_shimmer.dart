import 'package:flutter/material.dart';

/// A quiet highlight across live status text, with a steady readable base.
class ActivityShimmer extends StatefulWidget {
  const ActivityShimmer({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<ActivityShimmer> createState() => _ActivityShimmerState();
}

class _ActivityShimmerState extends State<ActivityShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(ActivityShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    _animate =
        widget.active &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_animate) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop();
      _animation.value = 0;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final band = (bounds.width * .55).clamp(40.0, 180.0);
            final center = -band + (bounds.width + 2 * band) * _animation.value;
            return LinearGradient(
              colors: [
                colors.onSurfaceVariant,
                colors.onSurface,
                colors.onSurfaceVariant,
              ],
            ).createShader(
              Rect.fromLTWH(center - band / 2, 0, band, bounds.height),
            );
          },
          child: child,
        ),
      ),
    );
  }
}
