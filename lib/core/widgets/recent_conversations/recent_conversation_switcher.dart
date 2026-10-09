import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../models/profile_session_key.dart';
import '../../models/recent_conversation.dart';
import '../../services/recent_conversation_session.dart';
import '../studio_error.dart';
import 'conversation_card_motion.dart';
import 'conversation_gestures.dart';

/// A transient layer over the real chat. It owns only input, card geometry,
/// bounded ephemeral raster captures and nudge paint. The session owns reads
/// and selection; the normal conversation remains mounted underneath.
class RecentConversationSwitcher extends StatefulWidget {
  const RecentConversationSwitcher({
    super.key,
    required this.session,
    required this.chatKey,
    required this.child,
    required this.previewBuilder,
    required this.gesturesEnabled,
    required this.nudgesEnabled,
    required this.onPresentationChanged,
  });
  final RecentConversationSession session;
  final ProfileSessionKey chatKey;
  final Widget child;
  final Widget Function(RecentConversationCard) previewBuilder;
  final bool gesturesEnabled, nudgesEnabled;
  final void Function(bool obscured, bool stack) onPresentationChanged;

  @override
  RecentConversationSwitcherState createState() =>
      RecentConversationSwitcherState();
}

class RecentConversationSwitcherState extends State<RecentConversationSwitcher>
    with TickerProviderStateMixin {
  late final ConversationCardMotion _motion = ConversationCardMotion(this);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  final _liveBoundary = GlobalKey();
  final _captures = <ProfileSessionKey, ui.Image>{};
  int _captureGeneration = 0;
  bool _active = false, _stack = false, _selecting = false;
  bool _preparedFrame = false;
  int _base = 0, _preparedIndex = -1;
  double _startPosition = 0, _pinchPosition = 0, _pinchLift = 0;
  ConversationGestureKind? _gesture;
  double _lastPosition = 0, _velocity = 0;
  Duration? _lastMove;
  Size _size = Size.zero;
  ConversationNudge? _cue;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  bool get _canGesture =>
      widget.gesturesEnabled &&
      widget.session.active &&
      widget.session.entries.length > 1 &&
      !_selecting &&
      !MediaQuery.accessibleNavigationOf(context);
  int get _focusedIndex => _base - _motion.position.round();
  int _indexOf(ProfileSessionKey key) =>
      widget.session.entries.indexWhere((entry) => entry.key == key);

  @override
  void initState() {
    super.initState();
    _base = math.max(0, _indexOf(widget.chatKey));
    _motion.addListener(_motionChanged);
    widget.session.addListener(_sessionChanged);
    widget.session.nudges.addListener(_nudgeChanged);
    _syncCueAdmission();
  }

  @override
  void didUpdateWidget(RecentConversationSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      oldWidget.session.nudges.removeListener(_nudgeChanged);
      widget.session.addListener(_sessionChanged);
      widget.session.nudges.addListener(_nudgeChanged);
      _clearCaptures();
      _active = _stack = _selecting = false;
      _base = math.max(0, _indexOf(widget.chatKey));
      _motion.jump(position: 0, lift: 0, zoom: 0);
    } else if (oldWidget.chatKey != widget.chatKey && !_selecting) {
      _base = math.max(0, _indexOf(widget.chatKey));
      _active = _stack = false;
      _motion.jump(position: 0, lift: 0, zoom: 0);
    }
    if (!widget.gesturesEnabled && _gesture != null) _cancel();
    _syncCueAdmission();
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (!widget.session.active) {
      _active = _stack = false;
      _motion.stop();
      _notifyPresentation();
    }
    setState(() {});
  }

  void _syncCueAdmission() {
    final enabled =
        widget.nudgesEnabled &&
        !_selecting &&
        _gesture == null &&
        !_motion.animating &&
        (!_active || _stack);
    widget.session.setInteractive(
      enabled,
      origin: _active && _stack
          ? widget.session.entryAt(_focusedIndex).key
          : widget.chatKey,
    );
    if (!enabled) {
      _pulse.stop();
      _cue = null;
    }
  }

  void _nudgeChanged() {
    if (!mounted ||
        !widget.nudgesEnabled ||
        _active && !_stack ||
        _gesture != null ||
        _motion.animating ||
        _reduced) {
      return;
    }
    setState(() => _cue = widget.session.nudges.value);
    _pulse.forward(from: 0);
  }

  void _motionChanged() {
    if (!mounted) return;
    if (_active) _prepareVisible();
    setState(() {});
  }

  void _prepareVisible() {
    final index = _focusedIndex;
    if (_preparedIndex == index || _preparedFrame) return;
    _preparedFrame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preparedFrame = false;
      if (!mounted || !_active || !widget.session.active) return;
      _preparedIndex = _focusedIndex;
      widget.session.prepareAround(_preparedIndex);
      final wanted = <ProfileSessionKey>{
        widget.chatKey,
        for (final offset in [-1, 0, 1])
          widget.session.entryAt(_preparedIndex + offset).key,
      };
      for (final key in _captures.keys.toList()) {
        if (!wanted.contains(key)) _captures.remove(key)!.dispose();
      }
    });
  }

  Future<void> _capture() async {
    final key = widget.chatKey, generation = ++_captureGeneration;
    final boundary = _liveBoundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    if (boundary.debugNeedsPaint) await SchedulerBinding.instance.endOfFrame;
    if (!mounted ||
        generation != _captureGeneration ||
        widget.chatKey != key ||
        !boundary.attached ||
        boundary.debugNeedsPaint) {
      return;
    }
    ui.Image image;
    try {
      image = await boundary.toImage(
        pixelRatio: math.min(MediaQuery.devicePixelRatioOf(context), 2),
      );
    } catch (_) {
      return;
    }
    if (!mounted || generation != _captureGeneration) {
      image.dispose();
      return;
    }
    _captures.remove(key)?.dispose();
    _captures[key] = image;
    setState(() {});
  }

  void _clearCaptures() {
    ++_captureGeneration;
    for (final image in _captures.values) {
      image.dispose();
    }
    _captures.clear();
  }

  void _notifyPresentation() {
    widget.onPresentationChanged(_active, _stack);
    _syncCueAdmission();
  }

  void _start(ConversationGestureSample sample) {
    if (!_canGesture) return;
    unawaited(_capture());
    final origin = _active
        ? _focusedIndex
        : math.max(0, widget.session.selectedIndex);
    _motion.stop();
    _motion.position += origin - _base;
    _base = origin;
    _startPosition = _lastPosition = _motion.position;
    _velocity = 0;
    _lastMove = sample.timeStamp;
    _gesture = sample.kind;
    _pinchPosition = _motion.position;
    _pinchLift = _motion.lift.clamp(0.0, 1.0);
    _active = true;
    _preparedIndex = -1;
    if (sample.kind != ConversationGestureKind.pinch) {
      _motion.spring(lift: 1, zoom: 0, reducedMotion: _reduced);
    }
    _notifyPresentation();
    _prepareVisible();
    _update(sample);
  }

  void _update(ConversationGestureSample sample) {
    if (_gesture == null || !_active) return;
    if (sample.kind == ConversationGestureKind.pinch) {
      if (_gesture != sample.kind) {
        _pinchPosition = _motion.position;
        _pinchLift = _motion.lift.clamp(0.0, 1.0);
      }
      _gesture = sample.kind;
      _motion.stop();
      final progress = ((1 - sample.scale) / .42).clamp(0.0, 1.12);
      _motion.position = _pinchPosition + sample.delta.dx / _size.width * .1;
      _motion.pinch(_pinchLift + (1 - _pinchLift) * progress, progress);
      return;
    }
    final unit =
        _size.width * (sample.kind == ConversationGestureKind.scrub ? .5 : .77);
    var position = _startPosition + sample.delta.dx / unit;
    if (sample.kind == ConversationGestureKind.slide) {
      position = position.clamp(-1.0, 1.0);
    }
    _track(position, sample.timeStamp);
  }

  void _track(double position, Duration? timeStamp) {
    final last = _lastMove;
    final dt = timeStamp != null && last != null
        ? (timeStamp - last).inMicroseconds / 1000000
        : 0.0;
    if (dt > .002) {
      final sample = ((position - _lastPosition) / dt).clamp(-8.0, 8.0);
      _velocity = dt > .1 ? sample : _velocity * .55 + sample * .45;
    }
    _lastMove = timeStamp;
    _lastPosition = position;
    _motion.drag(position, _velocity);
  }

  void _end() {
    final kind = _gesture;
    if (kind == null) return;
    _gesture = null;
    if (kind == ConversationGestureKind.pinch) {
      if (_motion.zoom > .42) {
        openStack();
      } else {
        _returnToChat();
      }
      return;
    }
    final offset = -_motion.position.round();
    final index = kind == ConversationGestureKind.scrub
        ? _base + offset
        : _motion.position.abs() > .22 / .77 ||
              (_motion.position.abs() > .08 / .77 && _velocity.abs() > 1.2)
        ? _base + (_motion.position.isNegative ? 1 : -1)
        : _base;
    if (index == _base) {
      _returnToChat();
    } else {
      unawaited(_select(index));
    }
  }

  void _cancel() {
    _gesture = null;
    if (_stack) {
      _settleStack(_motion.position.roundToDouble());
    } else {
      _returnToChat();
    }
  }

  /// Used by the existing overflow menu and accessible alternatives.
  void openStack() {
    if (_selecting ||
        !widget.session.active ||
        widget.session.entries.length < 2) {
      return;
    }
    if (!_active) {
      _base = math.max(0, widget.session.selectedIndex);
      _motion.jump(position: 0, lift: 0, zoom: 0);
      unawaited(_capture());
    }
    setState(() {
      _active = _stack = true;
      _gesture = null;
    });
    _preparedIndex = -1;
    _prepareVisible();
    _notifyPresentation();
    _settleStack(_motion.position.roundToDouble());
  }

  void _settleStack(double position) {
    _motion.spring(
      position: position,
      lift: 1,
      zoom: 1,
      reducedMotion: _reduced,
      settled: _syncCueAdmission,
    );
    _syncCueAdmission();
  }

  bool dismissStack() {
    if (!_stack) return false;
    if (!_selecting) _returnToChat();
    return true;
  }

  void _returnToChat({int? cardIndex}) {
    if (!mounted) return;
    _gesture = null;
    final selected = math.max(0, widget.session.selectedIndex);
    final count = widget.session.entries.length;
    final target =
        cardIndex ??
        selected +
            ((_base - _motion.position - selected) / count).round() * count;
    // Circular copies represent the same chat. Expand the tapped copy, or the
    // nearest copy on Back, rather than rewinding every lap the user browsed.
    _motion.position += target - _base;
    _base = target;
    _motion.spring(
      position: 0,
      lift: 0,
      zoom: 0,
      reducedMotion: _reduced,
      settled: _finishPresentation,
    );
    _syncCueAdmission();
  }

  void _finishPresentation() {
    if (!mounted) return;
    setState(() {
      _active = _stack = _selecting = false;
      _base = math.max(0, widget.session.selectedIndex);
      _preparedIndex = -1;
    });
    _motion.jump(position: 0, lift: 0, zoom: 0);
    _notifyPresentation();
  }

  Future<void> selectAdjacent(int delta) =>
      _select(math.max(0, widget.session.selectedIndex) + delta);

  Future<void> _select(int index) async {
    if (_selecting || !widget.session.active) return;
    final key = widget.session.entryAt(index).key;
    if (key == widget.session.selected) {
      _returnToChat(cardIndex: index);
      return;
    }
    _selecting = true;
    if (!_active) {
      _base = math.max(0, widget.session.selectedIndex);
      _active = true;
      unawaited(_capture());
      _notifyPresentation();
    }
    _motion.spring(
      position: (_base - index).toDouble(),
      lift: 1,
      zoom: _stack ? 1 : 0,
      reducedMotion: _reduced,
    );
    _syncCueAdmission();
    final opened = await widget.session.select(key);
    if (!mounted) return;
    if (!opened) {
      _selecting = false;
      if (!_stack && widget.session.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: StudioError(widget.session.error!)));
      }
      if (_stack) {
        _settleStack(_motion.position.roundToDouble());
      } else {
        _returnToChat();
      }
      return;
    }
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return;
    await _capture();
    if (!mounted) return;
    // The command and new capture are settled. A new gesture may now interrupt
    // expansion without starting overlapping navigation or exposing stale text.
    _selecting = _stack = false;
    _notifyPresentation();
    _motion.spring(
      position: (_base - index).toDouble(),
      lift: 0,
      zoom: 0,
      reducedMotion: _reduced,
      settled: () {
        if (!mounted) return;
        _base = math.max(0, widget.session.selectedIndex);
        _finishPresentation();
      },
    );
  }

  Offset? _browseStart;
  double _browsePosition = 0;
  void _browseDown(DragDownDetails details) {
    if (_selecting) return;
    _motion.stop();
    _browseStart = details.localPosition;
    _browsePosition = _lastPosition = _motion.position;
    _velocity = 0;
    _lastMove = null;
    _gesture = ConversationGestureKind.slide;
    _syncCueAdmission();
  }

  void _browseUpdate(DragUpdateDetails details) {
    final start = _browseStart;
    if (start == null || _selecting) return;
    final dx = details.localPosition.dx - start.dx;
    _track(_browsePosition + dx / (_size.width * .67), details.sourceTimeStamp);
  }

  void _browseEnd(DragEndDetails details) {
    if (_browseStart == null || _selecting) return;
    _browseStart = null;
    _gesture = null;
    _motion.positionVelocity =
        (details.velocity.pixelsPerSecond.dx / (_size.width * .67)).clamp(
          -8.0,
          8.0,
        );
    final target =
        (_motion.position + (_motion.positionVelocity * .13).clamp(-.55, .55))
            .roundToDouble();
    _settleStack(target);
  }

  int? _hitCard(Offset point) {
    final candidates = <({int index, double distance, Matrix4 transform})>[];
    final step = -_motion.position.round(), fraction = _motion.position + step;
    for (final offset in [-1, 0, 1]) {
      final relative = offset + fraction;
      candidates.add((
        index: _base + step + offset,
        distance: relative.abs(),
        transform: _cardTransform(relative),
      ));
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    final centered = point - Offset(_size.width / 2, _size.height / 2);
    for (final candidate in candidates) {
      final inverse = Matrix4.copy(candidate.transform);
      if (inverse.invert() == 0) continue;
      final local = MatrixUtils.transformPoint(inverse, centered);
      if (local.dx.abs() <= _size.width / 2 &&
          local.dy.abs() <= _size.height / 2) {
        return candidate.index;
      }
    }
    return null;
  }

  Matrix4 _cardTransform(double relative) {
    final distance = relative.abs().clamp(0.0, 1.5);
    final scale =
        1 -
        _motion.lift * (.14 + .055 * math.min(distance, 1)) -
        _motion.zoom * (.14 + .015 * math.min(distance, 1));
    final pitch = _size.width * (1 - .23 * _motion.lift - .10 * _motion.zoom);
    return Matrix4.identity()
      ..translateByDouble(
        relative * pitch,
        _motion.lift * (distance * 8 - 3) +
            _motion.zoom *
                (distance * 7 -
                    5 -
                    (MediaQuery.accessibleNavigationOf(context) ? 28 : 0)),
        0,
        1,
      )
      ..rotateZ(
        _motion.lift * (relative * 1.3).clamp(-1.4, 1.4) * math.pi / 180,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  Widget _cards() {
    final step = -_motion.position.round(), fraction = _motion.position + step;
    final slots = [-1, 0, 1]
      ..sort((a, b) => (b + fraction).abs().compareTo((a + fraction).abs()));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final offset in slots)
          Positioned.fill(
            child: Transform(
              alignment: Alignment.center,
              transform: _cardTransform(offset + fraction),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    24 * _motion.lift.clamp(0.0, 1.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: .30 * _motion.lift.clamp(0.0, 1.0),
                      ),
                      offset: const Offset(0, 14),
                      blurRadius: 32,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    24 * _motion.lift.clamp(0.0, 1.0),
                  ),
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: _cardContent(_base + step + offset),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardContent(int index) {
    final key = widget.session.entryAt(index).key;
    final capture = _captures[key];
    return capture == null
        ? widget.previewBuilder(widget.session.cardAt(index))
        : RawImage(image: capture, fit: BoxFit.fill);
  }

  Widget _nudge() {
    final cue = _cue;
    if (cue == null || _reduced) return const SizedBox.shrink();
    final light = Theme.of(context).brightness == Brightness.light;
    final color = cue.kind == ConversationActivityKind.inputNeeded
        ? const Color(0xffefaa5b)
        : light
        ? const Color(0xff3b3b3b)
        : const Color(0xffe9efef);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_pulse.value);
        final opacity = t < .18 ? t / .18 * .68 : .68 * (1 - (t - .18) / .82);
        return Positioned(
          left: cue.direction == ConversationDirection.left ? -8 : null,
          right: cue.direction == ConversationDirection.right ? -8 : null,
          top: _size.height * .22,
          height: _size.height * .44,
          width: 15,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0.0, .68),
              child: ImageFiltered(
                key: const ValueKey('recent-conversation-nudge'),
                imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      return RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          ConversationGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                ConversationGestureRecognizer
              >(ConversationGestureRecognizer.new, (recognizer) {
                recognizer.admits = (event) =>
                    _canGesture &&
                    !_stack &&
                    event.position.dx > 24 &&
                    event.position.dx < MediaQuery.sizeOf(context).width - 24 &&
                    (_active || admitsConversationGesture(event));
                recognizer.admitsScrub = (event) =>
                    _active ||
                    admitsConversationGesture(event, textAllowed: false);
                recognizer.onStart = _start;
                recognizer.onUpdate = _update;
                recognizer.onEnd = _end;
                recognizer.onCancel = _cancel;
              }),
        },
        child: Stack(
          children: [
            RepaintBoundary(
              key: _liveBoundary,
              child: ExcludeSemantics(
                excluding: _active,
                child: ExcludeFocus(
                  excluding: _active,
                  child: IgnorePointer(ignoring: _active, child: widget.child),
                ),
              ),
            ),
            if (_active)
              Positioned.fill(
                child: Material(
                  color: Theme.of(context).brightness == Brightness.light
                      ? const Color(0xffbccac7)
                      : const Color(0xff202c33),
                  child: ClipRect(
                    child: Stack(
                      children: [
                        _cards(),
                        if (_stack)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragDown: _browseDown,
                              onHorizontalDragUpdate: _browseUpdate,
                              onHorizontalDragEnd: _browseEnd,
                              onHorizontalDragCancel: () {
                                _browseStart = null;
                                _gesture = null;
                                _settleStack(_motion.position.roundToDouble());
                              },
                              onTapUp: (details) {
                                final index = _hitCard(details.localPosition);
                                _gesture = null;
                                _browseStart = null;
                                if (index != null && !_selecting) {
                                  unawaited(_select(index));
                                }
                              },
                            ),
                          ),
                        if (_stack)
                          Positioned(
                            top: MediaQuery.paddingOf(context).top + 8,
                            left: 8,
                            child: IconButton.filledTonal(
                              tooltip: 'Return to conversation',
                              onPressed: _selecting ? null : _returnToChat,
                              icon: const Icon(Icons.arrow_back),
                            ),
                          ),
                        if (_stack)
                          Positioned(
                            bottom: MediaQuery.paddingOf(context).bottom + 16,
                            left: 16,
                            right: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_selecting && widget.session.error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: StudioError(widget.session.error!),
                                  ),
                                if (!_selecting)
                                  Semantics(
                                    liveRegion: _stack,
                                    label:
                                        '${widget.session.entryAt(_focusedIndex).title}, conversation ${_focusedIndex % widget.session.entries.length + 1} of ${widget.session.entries.length}',
                                    child: Text(
                                      MediaQuery.accessibleNavigationOf(context)
                                          ? 'Choose a conversation'
                                          : 'Swipe to browse · tap to open',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                if (_selecting) const LinearProgressIndicator(),
                                if (MediaQuery.accessibleNavigationOf(context))
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    children: [
                                      IconButton(
                                        tooltip: 'Previous conversation',
                                        onPressed: _selecting
                                            ? null
                                            : () => _settleStack(
                                                _motion.position
                                                        .roundToDouble() +
                                                    1,
                                              ),
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      IconButton(
                                        tooltip: 'Open conversation',
                                        onPressed: _selecting
                                            ? null
                                            : () => _select(_focusedIndex),
                                        icon: const Icon(Icons.open_in_full),
                                      ),
                                      IconButton(
                                        tooltip: 'Next conversation',
                                        onPressed: _selecting
                                            ? null
                                            : () => _settleStack(
                                                _motion.position
                                                        .roundToDouble() -
                                                    1,
                                              ),
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            _nudge(),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    widget.session.setInteractive(false, origin: null);
    widget.session.removeListener(_sessionChanged);
    widget.session.nudges.removeListener(_nudgeChanged);
    _motion.removeListener(_motionChanged);
    _motion.dispose();
    _pulse.dispose();
    _clearCaptures();
    super.dispose();
  }
}
