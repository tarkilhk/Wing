import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

/// Presentation-only geometry. Independent spring velocities survive a new
/// target; dragging changes position directly without an easing queue.
final class ConversationCardMotion extends ChangeNotifier {
  ConversationCardMotion(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }
  late final Ticker _ticker;
  double position = 0, lift = 0, zoom = 0;
  double positionVelocity = 0, liftVelocity = 0, zoomVelocity = 0;
  SpringSimulation? _position, _lift, _zoom;
  VoidCallback? _settled;
  bool get animating => _ticker.isActive;

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (_position case final spring?) {
      position = spring.x(t);
      positionVelocity = spring.dx(t);
    }
    if (_lift case final spring?) {
      lift = spring.x(t);
      liftVelocity = spring.dx(t);
    }
    if (_zoom case final spring?) {
      zoom = spring.x(t);
      zoomVelocity = spring.dx(t);
    }
    notifyListeners();
    if ([
      _position,
      _lift,
      _zoom,
    ].every((spring) => spring == null || spring.isDone(t))) {
      _ticker.stop();
      final callback = _settled;
      _settled = null;
      callback?.call();
    }
  }

  void stop() {
    _ticker.stop();
    _position = _lift = _zoom = null;
    _settled = null;
  }

  void drag(double value, double velocity) {
    position = value;
    positionVelocity = velocity;
    notifyListeners();
  }

  void pinch(double elevation, double amount) {
    lift = elevation;
    zoom = amount;
    liftVelocity = zoomVelocity = 0;
    notifyListeners();
  }

  void jump({
    required double position,
    required double lift,
    required double zoom,
  }) {
    stop();
    this.position = position;
    this.lift = lift;
    this.zoom = zoom;
    positionVelocity = liftVelocity = zoomVelocity = 0;
    notifyListeners();
  }

  void spring({
    double? position,
    required double lift,
    required double zoom,
    bool reducedMotion = false,
    VoidCallback? settled,
  }) {
    stop();
    if (reducedMotion) {
      jump(position: position ?? this.position, lift: lift, zoom: zoom);
      settled?.call();
      return;
    }
    SpringSimulation simulation(
      double from,
      double to,
      double velocity, {
      bool horizontal = false,
    }) => SpringSimulation(
      SpringDescription(
        mass: 1,
        stiffness: horizontal ? 500 : 560,
        damping: horizontal ? 29 : 31,
      ),
      from,
      to,
      velocity,
      tolerance: const Tolerance(distance: .0007, velocity: .012),
    );
    if (position != null) {
      _position = simulation(
        this.position,
        position,
        positionVelocity,
        horizontal: true,
      );
    }
    _lift = simulation(this.lift, lift, liftVelocity);
    _zoom = simulation(this.zoom, zoom, zoomVelocity);
    _settled = settled;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
