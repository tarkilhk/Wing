import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Wing's three feathers keep their shape while a quiet highlight passes across.
class StudioLoading extends StatefulWidget {
  const StudioLoading({
    super.key,
    required this.label,
    this.size = 24,
    this.color,
  });

  final String label;
  final double size;
  final Color? color;

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
    return glyph;
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

/// The presentation belongs to a page Scaffold or an explicit modal frame.
/// Weak Scaffold keys keep independent pages isolated without an app-wide ledger.
final _pagePresentations = Expando<_LoadingPresentation>();

class _LoadingPresentation extends ValueNotifier<String?> {
  _LoadingPresentation() : super(null);
  final _operations = <Object, String>{};
  bool _queued = false, _disposed = false;

  static _LoadingPresentation of(BuildContext context) {
    final frame = context
        .dependOnInheritedWidgetOfExactType<_LoadingFrameScope>();
    if (frame != null) return frame.presentation;
    final page = Scaffold.of(context);
    return _pagePresentations[page] ??= _LoadingPresentation();
  }

  void report(Object operation, String? label) {
    if (_disposed) return;
    if (label == null) {
      _operations.remove(operation);
    } else {
      _operations[operation] = label;
    }
    if (_queued) return;
    _queued = true;
    // Body and header are siblings; never rebuild the header during body build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!_disposed) value = _operations.values.firstOrNull;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _operations.clear();
    super.dispose();
  }
}

/// Gives a modal or an immersive page its own loading lifetime and header slot.
class StudioLoadingFrame extends StatefulWidget {
  const StudioLoadingFrame({super.key, required this.child});
  final Widget child;
  @override
  State<StudioLoadingFrame> createState() => _StudioLoadingFrameState();
}

class _StudioLoadingFrameState extends State<StudioLoadingFrame> {
  final _presentation = _LoadingPresentation();
  @override
  void dispose() {
    _presentation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LoadingFrameScope(
    presentation: _presentation,
    child: _LoadingScope(active: false, child: widget.child),
  );
}

class _LoadingFrameScope extends InheritedWidget {
  const _LoadingFrameScope({required this.presentation, required super.child});
  final _LoadingPresentation presentation;
  @override
  bool updateShouldNotify(_LoadingFrameScope oldWidget) =>
      presentation != oldWidget.presentation;
}

/// A fixed header compartment; its width stays reserved when the page is ready.
class StudioLoadingSlot extends StatelessWidget {
  const StudioLoadingSlot({super.key, this.height = 48});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('studio-loading-slot'),
    width: 32,
    height: height,
    child: Center(
      child: ValueListenableBuilder<String?>(
        valueListenable: _LoadingPresentation.of(context),
        builder: (_, label, _) => label == null
            ? const SizedBox.shrink()
            : StudioLoading(label: label, size: 18),
      ),
    ),
  );
}

/// Reports page loading to its header without painting over or moving content.
class StudioPageLoading extends StatefulWidget {
  const StudioPageLoading({
    super.key,
    required this.active,
    required this.label,
    required this.child,
  });
  const StudioPageLoading.waiting({super.key, required this.label})
    : active = true,
      child = const SizedBox.shrink();
  final bool active;
  final String label;
  final Widget child;
  @override
  State<StudioPageLoading> createState() => _StudioPageLoadingState();
}

class _StudioPageLoadingState extends State<StudioPageLoading> {
  final _operation = Object();
  _LoadingPresentation? _presentation;
  void _report() {
    if (!widget.active) {
      _presentation?.report(_operation, null);
      _presentation = null;
      return;
    }
    final next = _LoadingPresentation.of(context);
    if (!identical(next, _presentation)) {
      _presentation?.report(_operation, null);
      _presentation = next;
    }
    _presentation!.report(_operation, widget.label);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _report();
  }

  @override
  void didUpdateWidget(StudioPageLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    _report();
  }

  @override
  void dispose() {
    _presentation?.report(_operation, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Availability admits a page pulse; nested regions share the outer operation.
class StudioLoadingRegion extends StatelessWidget {
  const StudioLoadingRegion({
    super.key,
    required this.busy,
    required this.available,
    required this.label,
    required this.child,
  });
  final bool busy, available;
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final inherited = _LoadingScope.maybeOf(context);
    final blocked = busy && !available;
    return StudioPageLoading(
      active: blocked && !inherited,
      label: label,
      child: _LoadingScope(active: blocked || inherited, child: child),
    );
  }
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
