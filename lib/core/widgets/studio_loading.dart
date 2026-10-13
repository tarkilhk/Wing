import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Wing's three feathers keep their shape while a quiet highlight passes across.
class StudioLoading extends StatefulWidget {
  const StudioLoading({
    super.key,
    required this.label,
    this.size = 24,
    this.color,
  }) : _page = false;

  /// An unavailable content area uses the same upper trailing loading position.
  const StudioLoading.page({super.key, required this.label})
    : size = 18,
      color = null,
      _page = true;

  final String label;
  final double size;
  final Color? color;
  final bool _page;

  @override
  State<StudioLoading> createState() => _StudioLoadingState();
}

/// Confirmed active work shares the loading pulse; other states stay static.
/// Callers supply activity evidence, never refresh/freshness flags.
class StudioActivityIndicator extends StatelessWidget {
  const StudioActivityIndicator({
    super.key,
    required this.active,
    required this.label,
    required this.icon,
    required this.color,
    this.size = 18,
  });

  final bool active;
  final String label;
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: active
        ? StudioLoading(label: label, color: color, size: size)
        : Icon(icon, size: size, color: color),
  );
}

class _StudioLoadingState extends State<StudioLoading>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_animate) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glyph = Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: SizedBox.square(
              dimension: widget.size,
              child: CustomPaint(
                painter: _Feathers(
                  color: widget.color ?? Theme.of(context).colorScheme.primary,
                  pulse: _pulse,
                  animate: _animate,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return widget._page
        ? Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: glyph,
            ),
          )
        : glyph;
  }
}

class _Feathers extends CustomPainter {
  _Feathers({required this.color, required this.pulse, required this.animate})
    : super(repaint: animate ? pulse : null);

  final Color color;
  final Animation<double> pulse;
  final bool animate;
  static final _shapes = [
    Path()
      ..moveTo(3, 9)
      ..cubicTo(6, 3, 16, 8, 21, 2)
      ..cubicTo(20, 10, 8, 6, 3, 9)
      ..close(),
    Path()
      ..moveTo(3, 15)
      ..cubicTo(6, 9, 15, 13, 20, 8)
      ..cubicTo(19, 16, 8, 12, 3, 15)
      ..close(),
    Path()
      ..moveTo(3, 21)
      ..cubicTo(6, 15, 14, 18, 18, 14)
      ..cubicTo(17, 21, 8, 18, 3, 21)
      ..close(),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);
    for (var i = 0; i < _shapes.length; i++) {
      final opacity = animate
          ? .70 +
                .30 *
                    (.5 - .5 * math.cos(2 * math.pi * (pulse.value - i * .145)))
          : 1.0;
      canvas.drawPath(
        _shapes[i],
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Feathers oldDelegate) =>
      color != oldDelegate.color || animate != oldDelegate.animate;
}

/// Paints loading over a region, keeping its child and geometry in place.
class StudioLoadingRegion extends StatelessWidget {
  const StudioLoadingRegion({
    super.key,
    required this.busy,
    required this.available,
    required this.label,
    required this.child,
  });
  final bool busy;
  final bool available;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inherited = _LoadingScope.maybeOf(context);
    final blocked = busy && !available;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        _LoadingScope(active: blocked || inherited, child: child),
        if (blocked && !inherited) StudioLoadingOverlay(label: label),
      ],
    );
  }
}

/// The shared upper trailing position for content waiting inside a Stack.
class StudioLoadingOverlay extends StatelessWidget {
  const StudioLoadingOverlay({
    super.key,
    required this.label,
    this.topInset = 0,
  });
  final String label;
  final double topInset;
  @override
  Widget build(BuildContext context) => PositionedDirectional(
    top: topInset,
    end: 16,
    child: StudioLoading(label: label, size: 18),
  );
}

class _LoadingScope extends InheritedWidget {
  const _LoadingScope({required this.active, required super.child});
  final bool active;
  static bool maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LoadingScope>()?.active ??
      false;
  @override
  bool updateShouldNotify(_LoadingScope oldWidget) =>
      active != oldWidget.active;
}

/// Retains Android's refresh gesture; Wing owns its visible loading feedback.
class StudioRefresh extends StatefulWidget {
  const StudioRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    required this.available,
    this.label = 'Refreshing',
  });
  final RefreshCallback onRefresh;
  final Widget child;
  final String label;
  final bool available;
  @override
  State<StudioRefresh> createState() => _StudioRefreshState();
}

class _StudioRefreshState extends State<StudioRefresh> {
  RefreshIndicatorStatus? _status;
  @override
  Widget build(BuildContext context) => StudioLoadingRegion(
    available: widget.available,
    busy:
        _status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed ||
        _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.refresh,
    label: widget.label,
    child: RefreshIndicator.noSpinner(
      onRefresh: widget.onRefresh,
      onStatusChange: (status) {
        if (mounted) setState(() => _status = status);
      },
      child: widget.child,
    ),
  );
}
