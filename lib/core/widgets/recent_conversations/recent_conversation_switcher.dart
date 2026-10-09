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
import 'conversation_card_snapshots.dart';
import 'conversation_gestures.dart';
import 'conversation_preview.dart';

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
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );
  final _snapshots = ConversationCardSnapshots();
  final _previewBoundary = GlobalKey();
  final _placeholders = <ProfileSessionKey, Widget>{};
  final _previewVersions = <ProfileSessionKey, RecentConversationCard>{};
  RecentConversationCard? _stagingCard;
  Timer? _idleTimer;
  bool _preparing = false, _preparationRequested = false, _liveDirty = true;
  Object? _renderEnvironment;
  Completer<void>? _selectionCompletion;
  Completer<void>? _expansionCompletion;
  Widget? _selectionChild;
  ProfileSessionKey? _openingKey;
  bool _paintingSelected = false, _selectionPainted = false;
  bool _expansionFinished = false;
  bool get _moving => _gesture != null || _motion.animating || _selecting;

  final _previews =
      <ProfileSessionKey, ({RecentConversationCard card, Widget view})>{};
  int _captureGeneration = 0;
  bool _active = false, _stack = false, _selecting = false;
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
      !_selecting;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _queueIdleWork());
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
      _completeSelection();
      _active = _stack = _selecting = false;
      _base = math.max(0, _indexOf(widget.chatKey));
      _motion.jump(position: 0, lift: 0, zoom: 0);
    } else if (oldWidget.chatKey != widget.chatKey && !_selecting) {
      _base = math.max(0, _indexOf(widget.chatKey));
      _active = _stack = false;
      _motion.jump(position: 0, lift: 0, zoom: 0);
    }
    if (oldWidget.child != widget.child) {
      _liveDirty = true;
      ++_captureGeneration;
    }
    _queueIdleWork();
    if (!widget.gesturesEnabled && _gesture != null) _cancel();
    _syncCueAdmission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final environment = (
      Theme.of(context),
      media.size,
      media.padding,
      media.textScaler,
    );
    if (_renderEnvironment != environment) {
      _renderEnvironment = environment;
      _clearCaptures();
      _queueIdleWork();
    }
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (!widget.session.active) {
      _active = _stack = _selecting = false;
      _gesture = null;
      _motion.stop();
      _clearCaptures();
      _completeSelection();
      _notifyPresentation();
    }
    setState(() {});
    _queueIdleWork();
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
    if (_moving) _idleTimer?.cancel();
  }

  void _queueIdleWork() {
    _idleTimer?.cancel();
    if (!mounted || _moving || !widget.session.active) return;
    if (_preparing) {
      _preparationRequested = true;
      return;
    }
    _idleTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted && !_moving) unawaited(_prepareIdle());
    });
  }

  Future<void> _prepareIdle() async {
    if (_preparing || _moving || !widget.session.active || _size.isEmpty) {
      return;
    }
    _preparing = true;
    final generation = _captureGeneration;
    bool current() =>
        mounted &&
        widget.session.active &&
        !_moving &&
        generation == _captureGeneration;
    try {
      _preparedIndex = _active
          ? _focusedIndex
          : math.max(0, widget.session.selectedIndex);
      widget.session.prepareAround(_preparedIndex);
      final wanted = <ProfileSessionKey>{
        widget.chatKey,
        for (final offset in [-1, 0, 1])
          widget.session.entryAt(_preparedIndex + offset).key,
      };
      _snapshots.retain(wanted);
      _previews.removeWhere((key, _) => !wanted.contains(key));
      _placeholders.removeWhere((key, _) => !wanted.contains(key));
      _previewVersions.removeWhere((key, _) => !wanted.contains(key));
      if (_liveDirty && !_active) await _capture();
      for (final offset in [0, -1, 1]) {
        if (!current()) return;
        final card = widget.session.cardAt(_preparedIndex + offset);
        final key = card.entry.key;
        if (_snapshots.isLive(key) ||
            card.loading ||
            identical(_previewVersions[key], card)) {
          continue;
        }
        setState(() => _stagingCard = card);
        await SchedulerBinding.instance.endOfFrame;
        if (!current()) return;
        final boundary = _previewBoundary.currentContext?.findRenderObject();
        if (boundary is! RenderRepaintBoundary || !boundary.attached) continue;
        ui.Image image;
        try {
          image = await boundary.toImage(
            pixelRatio: math.min(1, 768 / _size.longestSide),
          );
        } catch (_) {
          continue;
        }
        if (!current()) {
          image.dispose();
          return;
        }
        _snapshots.record(key, image, live: false);
        _previewVersions[key] = card;
      }
    } finally {
      _preparing = false;
      if (mounted) {
        setState(() => _stagingCard = null);
        if (_preparationRequested) {
          _preparationRequested = false;
          _queueIdleWork();
        }
      }
    }
  }

  Future<void> _capture() async {
    final key = widget.chatKey, generation = _captureGeneration;
    if (_active || _moving) return;
    final boundary = _liveBoundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted ||
        generation != _captureGeneration ||
        widget.chatKey != key ||
        !boundary.attached ||
        _active ||
        _moving) {
      return;
    }
    ui.Image image;
    try {
      image = await boundary.toImage(
        pixelRatio: math.min(
          MediaQuery.devicePixelRatioOf(context),
          math.min(1.5, 1280 / _size.longestSide),
        ),
      );
    } catch (_) {
      return;
    }
    if (!mounted || generation != _captureGeneration || _active || _moving) {
      image.dispose();
      return;
    }
    _snapshots.record(key, image, live: true);
    _liveDirty = false;
    setState(() {});
  }

  void _clearCaptures() {
    ++_captureGeneration;
    _idleTimer?.cancel();
    _snapshots.clear();
    _previewVersions.clear();
    _liveDirty = true;
    _previews.clear();
    _placeholders.clear();
  }

  void _notifyPresentation() {
    widget.onPresentationChanged(_active, _stack);
    _syncCueAdmission();
  }

  void _start(ConversationGestureSample sample) {
    if (!_canGesture) return;
    _idleTimer?.cancel();
    ++_captureGeneration;
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
    setState(() => _active = true);
    _preparedIndex = -1;
    if (sample.kind != ConversationGestureKind.pinch) {
      _motion.spring(lift: 1, zoom: 0, reducedMotion: _reduced);
    }
    _notifyPresentation();
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
    final unit = _size.width * .77;
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
    final index =
        _motion.position.abs() > .22 / .77 ||
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
    }
    setState(() {
      _active = _stack = true;
      _gesture = null;
    });
    _preparedIndex = -1;
    _notifyPresentation();
    _settleStack(_motion.position.roundToDouble());
  }

  void _settleStack(double position) {
    _motion.spring(
      position: position,
      lift: 1,
      zoom: 1,
      reducedMotion: _reduced,
      settled: () {
        _syncCueAdmission();
        _queueIdleWork();
      },
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
    _motion.expand(
      position: 0,
      reducedMotion: _reduced,
      settled: _finishPresentation,
    );
    _syncCueAdmission();
  }

  void _finishPresentation() {
    if (!mounted) return;
    _completeSelection();
    setState(() {
      _active = _stack = _selecting = false;
      _base = math.max(0, widget.session.selectedIndex);
      _preparedIndex = -1;
    });
    _motion.jump(position: 0, lift: 0, zoom: 0);
    _notifyPresentation();
    _queueIdleWork();
  }

  Future<void> selectAdjacent(int delta) =>
      _select(math.max(0, widget.session.selectedIndex) + delta);

  Future<void> _select(int index) {
    if (_selecting || !widget.session.active) return Future.value();
    final key = widget.session.entryAt(index).key;
    if (key == widget.session.selected) {
      _returnToChat(cardIndex: index);
      return Future.value();
    }
    final fromStack = _stack;
    _idleTimer?.cancel();
    ++_captureGeneration;
    final completion = _selectionCompletion = Completer<void>();
    final expansion = _expansionCompletion = Completer<void>();
    _selectionChild = widget.child;
    _openingKey = key;
    _paintingSelected = _selectionPainted = _expansionFinished = false;
    _reveal.value = 0;
    setState(() {
      _selecting = _active = true;
      _stack = false;
    });
    _notifyPresentation();
    // Start I/O immediately, but retain the mounted child during pixel motion.
    // Building the selected transcript here can stall the expansion animation.
    _motion.expand(
      position: (_base - index).toDouble(),
      reducedMotion: _reduced,
      settled: () {
        _expansionFinished = true;
        if (!expansion.isCompleted) expansion.complete();
        _tryReveal(completion);
      },
    );
    unawaited(_openSelected(index, fromStack, completion, expansion.future));
    return completion.future;
  }

  void _tryReveal(Completer<void> completion) {
    if (!mounted ||
        _selectionCompletion != completion ||
        !_expansionFinished ||
        !_selectionPainted ||
        _reveal.isAnimating) {
      return;
    }
    if (_reduced) {
      _finishPresentation();
    } else {
      _reveal.forward().whenCompleteOrCancel(() {
        if (mounted && _selectionCompletion == completion) {
          _finishPresentation();
        }
      });
    }
  }

  Future<void> _openSelected(
    int index,
    bool fromStack,
    Completer<void> completion,
    Future<void> expansion,
  ) async {
    final session = widget.session;
    try {
      if (!mounted || !session.active) return;
      final opened = await session.select(session.entryAt(index).key);
      if (!mounted ||
          !session.active ||
          widget.session != session ||
          _selectionCompletion != completion) {
        return;
      }
      if (!opened) {
        _motion.stop();
        _completeSelection();
        setState(() {
          _selecting = false;
          _stack = fromStack;
        });
        if (fromStack) {
          _settleStack(_motion.position.roundToDouble());
        } else {
          if (widget.session.error case final error?) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: StudioError(error)));
          }
          _returnToChat();
        }
        return;
      }
      await expansion;
      if (!mounted ||
          !session.active ||
          widget.session != session ||
          _selectionCompletion != completion) {
        return;
      }
      setState(() => _paintingSelected = true);
      // The first layout can schedule Markdown/reading-position corrections.
      // Give those a paint frame under the opaque cover before fading it away.
      for (var frame = 0; frame < 2; frame++) {
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted ||
            !session.active ||
            widget.session != session ||
            _selectionCompletion != completion) {
          return;
        }
      }
      _liveDirty = true;
      _selectionPainted = true;
      _tryReveal(completion);
    } finally {
      if ((!mounted || !session.active || widget.session != session) &&
          !completion.isCompleted) {
        completion.complete();
      }
    }
  }

  void _completeSelection() {
    final completion = _selectionCompletion;
    _selectionCompletion = null;
    final expansion = _expansionCompletion;
    _expansionCompletion = null;
    if (expansion != null && !expansion.isCompleted) expansion.complete();
    _selectionChild = null;
    _reveal.stop();
    _reveal.value = 0;
    _openingKey = null;
    _paintingSelected = _selectionPainted = _expansionFinished = false;
    if (completion != null && !completion.isCompleted) completion.complete();
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
    _motion.coast(
      velocity: details.velocity.pixelsPerSecond.dx / (_size.width * .67),
      reducedMotion: _reduced,
      settled: () {
        _syncCueAdmission();
        _queueIdleWork();
      },
    );
    _syncCueAdmission();
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
            key: ValueKey(_base + step + offset),
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
    final capture = _snapshots.imageFor(key);
    final content = _preparedCard(index, key, capture);
    if (key != _openingKey || _snapshots.isLive(key)) return content;
    // An excerpt is useful in a thumbnail, but isn't the normal chat. Fade it
    // into an opening frame instead of magnifying a different transcript.
    final excerptOpacity = _motion.lift.clamp(0.0, 1.0);
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(opacity: excerptOpacity, child: content),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 1 - excerptOpacity,
            child: Stack(
              children: [
                Positioned.fill(child: _placeholder(index)),
                Center(
                  child: Text(
                    'Opening conversation…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _preparedCard(int index, ProfileSessionKey key, ui.Image? capture) {
    if (capture != null) {
      return RawImage(
        key: ValueKey((key, 'snapshot')),
        image: capture,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.low,
      );
    }
    final prepared = _previews[key];
    if (prepared != null) return prepared.view;
    return _placeholder(index);
  }

  Widget _placeholder(int index) {
    final key = widget.session.entryAt(index).key;
    if (_placeholders.length >= 6 && !_placeholders.containsKey(key)) {
      _placeholders.remove(_placeholders.keys.first);
    }
    return _placeholders.putIfAbsent(
      key,
      () => RepaintBoundary(
        child: ConversationPreview(
          card: RecentConversationCard(entry: widget.session.entryAt(index)),
          connectionLabel: '',
        ),
      ),
    );
  }

  Widget _previewFor(RecentConversationCard card) {
    final key = card.entry.key;
    final cached = _previews[key];
    if (cached != null && identical(cached.card, card)) return cached.view;
    final view = RepaintBoundary(child: widget.previewBuilder(card));
    _previews[key] = (card: card, view: view);
    return view;
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
      if (_size != constraints.biggest) {
        _size = constraints.biggest;
        _clearCaptures();
        _queueIdleWork();
      }
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
                recognizer.onStart = _start;
                recognizer.onUpdate = _update;
                recognizer.onEnd = _end;
                recognizer.onCancel = _cancel;
              }),
        },
        child: Stack(
          children: [
            if (_stagingCard case final card?)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      key: _previewBoundary,
                      child: _previewFor(card),
                    ),
                  ),
                ),
              ),
            NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                _liveDirty = true;
                _queueIdleWork();
                return false;
              },
              child: TickerMode(
                enabled: !_active,
                child: Offstage(
                  offstage: _active && !_paintingSelected,
                  child: RepaintBoundary(
                    key: _liveBoundary,
                    child: ExcludeSemantics(
                      excluding: _active,
                      child: ExcludeFocus(
                        excluding: _active,
                        child: IgnorePointer(
                          ignoring: _active,
                          child: _selecting && !_paintingSelected
                              ? _selectionChild ?? widget.child
                              : widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_active)
              Positioned.fill(
                child: FadeTransition(
                  opacity: ReverseAnimation(_reveal),
                  child: Material(
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xffbccac7)
                        : const Color(0xff202c33),
                    child: ClipRect(
                      child: Stack(
                        children: [
                          AnimatedBuilder(
                            animation: _motion,
                            builder: (context, _) => _cards(),
                          ),
                          if (_selecting && !_motion.animating)
                            Positioned(
                              top: MediaQuery.paddingOf(context).top,
                              left: 0,
                              right: 0,
                              child: const LinearProgressIndicator(
                                minHeight: 2,
                              ),
                            ),
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
                                  _settleStack(
                                    _motion.position.roundToDouble(),
                                  );
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
                                icon: const Icon(Icons.close),
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
                                  if (!_selecting &&
                                      widget.session.error != null)
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
                                        MediaQuery.accessibleNavigationOf(
                                              context,
                                            )
                                            ? 'Choose a conversation'
                                            : 'Swipe to browse · tap to open',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  if (_selecting)
                                    const LinearProgressIndicator(),
                                  if (MediaQuery.accessibleNavigationOf(
                                    context,
                                  ))
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
    _completeSelection();
    _reveal.dispose();
    super.dispose();
  }
}
