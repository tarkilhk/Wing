// Profile-only synthetic fixture; no app startup, settings, storage or backend.
// flutter build apk --profile -t tools/performance/streaming_replay.dart
// ext.wingPerf.replay returns after a bounded replay and frame-batch drain.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/activity_shimmer.dart';
import 'package:wing/core/widgets/profile_message.dart';

import 'streaming_replay_fixture.dart';

void main() {
  if (!kProfileMode) {
    throw StateError('Streaming replay requires profile mode.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(theme: wingTheme(Brightness.light), home: const _Replay()),
  );
}

class _Replay extends StatefulWidget {
  const _Replay();
  @override
  State<_Replay> createState() => _ReplayState();
}

class _ReplayState extends State<_Replay> with WidgetsBindingObserver {
  final _source = ValueNotifier(streamingReplayInitial());
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final _frames = <FrameTiming>[];
  Timer? _timer;
  Completer<void>? _pending;
  Completer<void>? _abort;
  var _foreground = false;
  var _canceled = false;
  var _busy = false;
  var _run = 0;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_timings);
    developer.registerExtension('ext.wingPerf.replay', (_, parameters) async {
      final fences = switch (parameters['fences']) {
        'true' => true,
        'false' => false,
        _ => null,
      };
      if (fences == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'Choose a replay with or without code fences.',
        );
      }
      if (!mounted || !_foreground || _busy) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'Replay is unavailable.',
        );
      }
      _busy = true;
      _canceled = false;
      _abort = Completer<void>();
      try {
        return developer.ServiceExtensionResponse.result(
          jsonEncode(await _replay(fences: fences)),
        );
      } on StateError {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'Replay canceled or keyboard, geometry, and animation preconditions failed.',
        );
      } finally {
        _busy = false;
        _abort = null;
      }
    });
  }

  void _timings(List<FrameTiming> frames) {
    if (mounted && _busy) {
      _frames.addAll(frames);
    }
  }

  void _requireMounted() {
    if (!mounted || !_foreground || _canceled) {
      throw StateError('Replay canceled.');
    }
  }

  bool get _animationAllowed {
    _requireMounted();
    return !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
  }

  void _cancel() {
    _canceled = true;
    _timer?.cancel();
    if (_pending case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    if (_abort case final abort? when !abort.isCompleted) {
      abort.complete();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _busy) {
      _cancel();
    }
  }

  Future<void> _endFrame() async {
    _requireMounted();
    final binding = WidgetsBinding.instance;
    binding.scheduleFrame();
    await Future.any([binding.endOfFrame, _abort!.future]);
    _requireMounted();
  }

  Future<void> _wait(Duration duration) async {
    _requireMounted();
    final done = _pending = Completer<void>();
    _timer = Timer(duration, done.complete);
    await done.future;
    _timer = null;
    _pending = null;
    _requireMounted();
  }

  Future<Map<String, Object>> _replay({required bool fences}) async {
    _requireMounted();
    final run = ++_run;
    _source.value = streamingReplayInitial(fences: fences);
    _draft.clear();
    _focus.requestFocus();
    await _wait(const Duration(seconds: 1));
    if (!mounted) throw StateError('Replay canceled.');
    final view = View.of(context);
    Object geometry() =>
        (view.viewInsets, view.physicalSize, view.devicePixelRatio);
    var previous = geometry();
    var stable = 0;
    for (var sample = 0; sample < 10 && stable < 3; sample++) {
      await _wait(const Duration(milliseconds: 100));
      final current = geometry();
      stable =
          current == previous && _focus.hasFocus && view.viewInsets.bottom > 0
          ? stable + 1
          : 0;
      previous = current;
    }
    if (stable < 3 || !_animationAllowed) {
      throw StateError('Replay preconditions failed.');
    }
    await _endFrame();
    _frames.clear();
    final startMonotonicUs = developer.Timeline.now;
    final startEpochUs = DateTime.now().microsecondsSinceEpoch;
    final keyboardStart = view.viewInsets.bottom / view.devicePixelRatio;
    final startGeometry = geometry();
    var geometryStable = true;
    var animationEnabled = true;
    var focusHeld = true;
    final watch = Stopwatch()..start();
    final growth = streamingReplayGrowth(fences: fences);
    var accumulated = streamingReplayInitial(fences: fences);
    var consumed = 0;
    final deltaUs = <int>[];
    final publicationUs = <int>[];
    final draftUs = <int>[];
    developer.Timeline.instantSync(
      'WingStreamingReplayStart',
      arguments: {'run': run},
    );
    debugPrint(
      '[WingStreamingReplay] start run=$run epochUs=$startEpochUs monotonicUs=$startMonotonicUs',
    );
    const count =
        streamingReplayPresentations * streamingReplayDeltasPerPresentation;
    for (var event = 0; event < count; event++) {
      // Absolute deadlines preserve requested inputs even when the UI stalls.
      // Overdue events catch up on event-loop turns; achieved times remain visible.
      final dueUs = (event + 1) * 10000;
      await _wait(
        Duration(microseconds: math.max(0, dueUs - watch.elapsedMicroseconds)),
      );
      geometryStable = geometryStable && geometry() == startGeometry;
      animationEnabled = animationEnabled && _animationAllowed;
      focusHeld = focusHeld && _focus.hasFocus;
      final presentation = event ~/ streamingReplayDeltasPerPresentation;
      final delta = event % streamingReplayDeltasPerPresentation;
      final next = streamingReplayDeltaEnd(presentation, delta, growth.length);
      accumulated += growth.substring(consumed, next);
      consumed = next;
      deltaUs.add(watch.elapsedMicroseconds);
      if (delta == 2 || delta == 7) {
        final text = streamingReplayDraft(presentation, delta + 1);
        _draft.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        draftUs.add(watch.elapsedMicroseconds);
      }
      if (delta == streamingReplayDeltasPerPresentation - 1) {
        _source.value = accumulated;
        publicationUs.add(watch.elapsedMicroseconds);
      }
    }
    await _endFrame();
    final endMonotonicUs = developer.Timeline.now;
    final endEpochUs = DateTime.now().microsecondsSinceEpoch;
    final keyboardEnd = view.viewInsets.bottom / view.devicePixelRatio;
    geometryStable = geometryStable && geometry() == startGeometry;
    animationEnabled = animationEnabled && _animationAllowed;
    focusHeld = focusHeld && _focus.hasFocus;
    watch.stop();
    developer.Timeline.instantSync(
      'WingStreamingReplayEnd',
      arguments: {'run': run},
    );
    debugPrint(
      '[WingStreamingReplay] end run=$run epochUs=$endEpochUs monotonicUs=$endMonotonicUs',
    );
    // Timeline.now and raw build/raster timestamps use the VM's monotonic clock.
    // A vsync target timestamp is not an actual build-start boundary. Bounded
    // draining does not guarantee all callbacks arrived. ActivityShimmer supplies
    // continuous frames while honoring OS reduced motion.
    await _wait(const Duration(milliseconds: 1500));
    final frames = _frames.where((frame) {
      final start = frame.timestampInMicroseconds(FramePhase.buildStart);
      return start > startMonotonicUs && start <= endMonotonicUs;
    }).toList();
    return {
      'run': run,
      'fences': fences ? 1 : 0,
      'startEpochUs': startEpochUs,
      'endEpochUs': endEpochUs,
      'startMonotonicUs': startMonotonicUs,
      'endMonotonicUs': endMonotonicUs,
      'elapsedUs': watch.elapsedMicroseconds,
      'deltas': deltaUs.length,
      'presentations': publicationUs.length,
      'draftEdits': draftUs.length,
      'deltaAchievedUs': deltaUs,
      'publicationAchievedUs': publicationUs,
      'draftAchievedUs': draftUs,
      'scheduleOverrunUs': math.max(0, deltaUs.last - count * 10000),
      'maxDeltaLatenessUs': List.generate(
        count,
        (i) => deltaUs[i] - (i + 1) * 10000,
      ).reduce(math.max),
      'finalCodeUnits': accumulated.length,
      'exactFinalContent':
          accumulated == streamingReplayInitial(fences: fences) + growth
          ? 1
          : 0,
      'exactFinalDraft': _draft.text == streamingReplayDraft(59, 8) ? 1 : 0,
      'keyboardStartDp': keyboardStart,
      'keyboardEndDp': keyboardEnd,
      'geometryStable': geometryStable ? 1 : 0,
      'animationEnabled': animationEnabled ? 1 : 0,
      'focusHeld': focusHeld ? 1 : 0,
      'valid':
          geometryStable &&
              keyboardEnd > 0 &&
              focusHeld &&
              animationEnabled &&
              frames.isNotEmpty
          ? 1
          : 0,
      'displayRefreshHz': view.display.refreshRate,
      'frameCount': frames.length,
      'buildUs': frames
          .map((frame) => frame.buildDuration.inMicroseconds)
          .toList(),
      'rasterUs': frames
          .map((frame) => frame.rasterDuration.inMicroseconds)
          .toList(),
      'frameBuildStartUs': frames
          .map((frame) => frame.timestampInMicroseconds(FramePhase.buildStart))
          .toList(),
      'rasterFinishEpochUs': frames
          .map(
            (frame) =>
                frame.timestampInMicroseconds(FramePhase.rasterFinishWallTime),
          )
          .toList(),
      'frameRasterFinishUs': frames
          .map(
            (frame) => frame.timestampInMicroseconds(FramePhase.rasterFinish),
          )
          .toList(),
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const ActivityShimmer(
        active: true,
        child: Text('Streaming replay'),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              padding: const EdgeInsets.all(WingSpacing.lg),
              child: ValueListenableBuilder<String>(
                valueListenable: _source,
                builder: (_, data, _) => ProfileMessage(
                  streaming: true,
                  message: {'role': 'assistant', 'content': data},
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(WingSpacing.md),
            child: TextField(controller: _draft, focusNode: _focus),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_timings);
    _source.dispose();
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }
}
