// Offline profile fixture. Native draft storage is excluded: preferences use
// an isolated in-memory store. Rendering, controller events and composer input
// run through the real workspace. No gateway performs network requests.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';
import 'package:wing/core/widgets/block_reusing_markdown_body.dart';
import 'package:wing/core/widgets/markdown_code_block.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';

import '../../test/support/profile_browser_fixture.dart';
import 'streaming_replay_fixture.dart';

const workspaceReplayDeltaCount = 400;
const workspaceReplayIntervalUs = 50000;

bool workspaceReplayMatchesSegments(
  String source,
  Iterable<Widget> widgets, {
  required bool streaming,
}) {
  final expected = splitMarkdownCodeBlocks(source, streaming: streaming)
      .map(
        (part) =>
            part is MarkdownCodeBlock ? ('code', part.code) : ('prose', part),
      )
      .toList();
  final actual = widgets
      .where(
        (widget) =>
            widget is BlockReusingMarkdownBody || widget is MarkdownCodeBlock,
      )
      .map(
        (widget) => widget is MarkdownCodeBlock
            ? ('code', widget.code)
            : ('prose', (widget as BlockReusingMarkdownBody).data),
      )
      .toList();
  return listEquals(expected, actual);
}

void main() {
  if (!kProfileMode) {
    throw StateError('Workspace replay requires profile mode');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: wingTheme(Brightness.light),
      home: const WorkspaceStreamingReplay(),
    ),
  );
}

class _ReplayGateway extends ProfileBrowserFixture {
  List<Map<String, dynamic>> rows = [
    {
      'id': 1,
      'role': 'user',
      'content': 'Show the fixed synthetic mixed answer.',
    },
  ];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => rows;

  @override
  List<Map<String, dynamic>> projects(String profile) => [];

  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    {
      'id': 'new-chat',
      'title': 'Offline workspace replay',
      'profile': profile,
      'last_active': 1800000000,
    },
  ];
}

class WorkspaceStreamingReplay extends StatefulWidget {
  const WorkspaceStreamingReplay({super.key});

  @override
  WorkspaceStreamingReplayState createState() =>
      WorkspaceStreamingReplayState();
}

class WorkspaceStreamingReplayState extends State<WorkspaceStreamingReplay>
    with WidgetsBindingObserver {
  ProfileWorkspaceController? controller;
  ProfileChat? _chat;
  _ReplayGateway? _fixture;
  ProfileGateway? _gateway;
  EditableTextState? _composer;
  final _frames = <FrameTiming>[];
  Completer<void>? _abort;
  var _canceled = false;
  var _preparing = false;
  var _running = false;
  var _prepared = false;
  var _collecting = false;
  var _run = 0;

  Map<String, Object?> ready() => {
    'prepared': _prepared,
    'preparing': _preparing,
    'running': _running,
    'keyboard': mounted && View.of(context).viewInsets.bottom > 0,
    'composerFocused': _composer?.widget.focusNode.hasFocus ?? false,
    'draft': _chat?.composerText,
    'sourceCharacters': _chat?.streaming.length ?? 0,
    'nativeDraftStorage': false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_timings);
    if (kProfileMode) {
      for (final action in ['ready', 'prepare', 'replay']) {
        developer.registerExtension('ext.wingReplay.$action', (
          _,
          parameters,
        ) async {
          try {
            final result = switch (action) {
              'prepare' => await prepare(),
              'replay' => await replay(label: parameters['label'] ?? ''),
              _ => ready(),
            };
            return developer.ServiceExtensionResponse.result(
              jsonEncode(result),
            );
          } catch (error) {
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.extensionError,
              error.toString(),
            );
          }
        });
      }
    }
  }

  void _timings(List<FrameTiming> frames) {
    if (_collecting) {
      _frames.addAll(frames);
    }
  }

  void _requireMounted() {
    if (!mounted) {
      throw StateError('Replay unmounted');
    }
    if (_canceled) {
      throw StateError('Replay canceled by lifecycle change');
    }
    if (_running && !identical(controller?.current?.chat, _chat)) {
      throw StateError('Selected replay chat changed');
    }
    if (_running &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      throw StateError('Replay must remain in the foreground');
    }
  }

  double _textScaleAt14() {
    _requireMounted();
    return MediaQuery.textScalerOf(context).scale(14);
  }

  Future<void> _wait(Duration duration) async {
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    try {
      await Future.any([done.future, if (_abort != null) _abort!.future]);
    } finally {
      timer.cancel();
    }
    _requireMounted();
  }

  Future<void> _endFrame() async {
    _requireMounted();
    final timeout = Completer<void>();
    final timer = Timer(
      const Duration(seconds: 3),
      () => timeout.completeError(
        StateError('Frame wait exceeded three seconds'),
      ),
    );
    WidgetsBinding.instance.scheduleFrame();
    try {
      await Future.any([
        WidgetsBinding.instance.endOfFrame,
        timeout.future,
        if (_abort != null) _abort!.future,
      ]);
    } finally {
      timer.cancel();
    }
    _requireMounted();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        (!_preparing && !_running && !_prepared)) {
      return;
    }
    _canceled = true;
    _prepared = false;
    if (_abort case final abort? when !abort.isCompleted) {
      abort.complete();
    }
  }

  Iterable<Element> _walk(Element element) sync* {
    if (element.widget case Offstage(offstage: true)) {
      return;
    }
    yield element;
    final children = <Element>[];
    element.visitChildren(children.add);
    for (final child in children) {
      yield* _walk(child);
    }
  }

  // Called only before measurement or after the completion tail.
  Map<String, Object> renderedReadiness(String source) {
    final bodies = _walk(context as Element)
        .where(
          (element) =>
              element.widget is MarkdownMessageContent &&
              (element.widget as MarkdownMessageContent).data == source,
        )
        .toList();
    final elements = bodies.length == 1
        ? _walk(bodies.single).toList()
        : <Element>[];
    final parsers = elements
        .whereType<StatefulElement>()
        .map((element) => element.state)
        .whereType<BackgroundMarkdownContentState>()
        .toList();
    final marker = source.contains('Synthetic11_44')
        ? 'Synthetic11_44'
        : 'Synthetic5_44';
    final segmentsMatch = workspaceReplayMatchesSegments(
      source,
      elements.map((element) => element.widget),
      streaming: _chat!.busy,
    );
    var editableMarkers = 0;
    var paragraphMarkers = 0;
    for (final element in elements.whereType<RenderObjectElement>()) {
      final render = element.renderObject;
      if (render is RenderEditable &&
          render.hasSize &&
          (render.text?.toPlainText().contains(marker) ?? false)) {
        editableMarkers++;
      } else if (render is RenderParagraph &&
          render.hasSize &&
          render.text.toPlainText().contains(marker)) {
        paragraphMarkers++;
      }
    }
    final pending = parsers.where((state) => state.pending).length;
    final stale = parsers
        .where((state) => state.renderedSource != state.widget.data)
        .length;
    return {
      'bodyCount': bodies.length,
      'expectedSegments': splitMarkdownCodeBlocks(
        source,
        streaming: _chat!.busy,
      ).length,
      'mountedProse': elements
          .where((element) => element.widget is BlockReusingMarkdownBody)
          .length,
      'mountedCode': elements
          .where((element) => element.widget is MarkdownCodeBlock)
          .length,
      'segmentsMatch': segmentsMatch,
      'parserCount': parsers.length,
      'pendingParsers': pending,
      'staleParsers': stale,
      'editableMarkers': editableMarkers,
      'paragraphMarkers': paragraphMarkers,
      'rendered':
          bodies.length == 1 &&
          segmentsMatch &&
          parsers.isNotEmpty &&
          pending == 0 &&
          stale == 0 &&
          editableMarkers + paragraphMarkers > 0,
    };
  }

  bool _rendered(String source) =>
      renderedReadiness(source)['rendered'] == true;

  Future<void> _awaitRendered(String source) async {
    for (var attempt = 0; attempt < 150; attempt++) {
      await _endFrame();
      if (_rendered(source)) {
        return;
      }
      await _wait(const Duration(milliseconds: 20));
    }
    throw StateError(
      'Final renderer did not settle: ${jsonEncode(renderedReadiness(source))}',
    );
  }

  void _emit(String type, Map<String, dynamic> data) {
    _gateway!.onEvent!(
      StreamEvent(type: type, sessionId: _chat!.runtimeId, data: data),
    );
  }

  // Tests may omit the physical keyboard precondition; the VM extension always
  // uses it. Preparation and renderer checks are outside measured intervals.
  Future<Map<String, Object?>> prepare({bool requireKeyboard = true}) async {
    if (_preparing || _running) {
      throw StateError('Replay already active');
    }
    _preparing = true;
    _prepared = false;
    _canceled = false;
    _abort = Completer<void>();
    try {
      final old = controller;
      controller = null;
      _composer = null;
      setState(() {});
      await _endFrame();
      old?.dispose();
      // This offline profile benchmark intentionally excludes native draft
      // storage and must never read or mutate the installed app's preferences.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final fixture = _fixture = _ReplayGateway();
      final next = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'qa-render-replay',
          label: 'Offline replay',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        connectionIdentity: 'qa-render-replay',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: fixture.gateway,
      );
      controller = next;
      await next.initialize();
      _chat = await next.createChat();
      _gateway = next.current!.gateway;
      await next.refreshHistory(_chat!);
      setState(() {});
      _emit('message.start', {});
      _emit('message.delta', {'text': streamingReplayInitial()});
      await _awaitRendered(streamingReplayInitial());
      if (!mounted) {
        throw StateError('Replay unmounted');
      }
      final composerRoot = _walk(context as Element)
          .where(
            (element) =>
                element.widget.key == const Key('profile-message-composer'),
          )
          .single;
      _composer = _walk(composerRoot)
          .whereType<StatefulElement>()
          .map((element) => element.state)
          .whereType<EditableTextState>()
          .single;
      _composer!.userUpdateTextEditingValue(
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
        SelectionChangedCause.keyboard,
      );
      _composer!.widget.focusNode.requestFocus();
      await _endFrame();
      if (!mounted) {
        throw StateError('Replay unmounted');
      }
      if (requireKeyboard) {
        final view = View.of(context);
        var stable = 0;
        var previous = view.viewInsets;
        for (var attempt = 0; attempt < 30 && stable < 3; attempt++) {
          await _wait(const Duration(milliseconds: 100));
          final insets = view.viewInsets;
          stable =
              insets == previous &&
                  insets.bottom > 0 &&
                  _composer!.widget.focusNode.hasFocus
              ? stable + 1
              : 0;
          previous = insets;
        }
        if (stable < 3) {
          throw StateError('Focus the composer and open the keyboard');
        }
      }
      _prepared = true;
      return {...ready(), 'preparing': false};
    } finally {
      _preparing = false;
      _abort = null;
    }
  }

  Future<Map<String, Object?>> replay({String label = ''}) async {
    if (!_prepared || _running || _preparing) {
      throw StateError('Prepare before replay');
    }
    _running = true;
    _prepared = false;
    _abort = Completer<void>();
    try {
      _requireMounted();
      final owner = controller;
      final chat = _chat;
      if (owner == null ||
          chat == null ||
          !owner.initialized ||
          !identical(owner.current?.chat, chat) ||
          !chat.busy ||
          chat.streaming != streamingReplayInitial() ||
          !_rendered(streamingReplayInitial())) {
        throw StateError(
          'Prepared source or selected chat changed; prepare again',
        );
      }
      final view = View.of(context);
      if (view.viewInsets.bottom <= 0 ||
          !_composer!.widget.focusNode.hasFocus) {
        throw StateError('Open the keyboard and focus the prepared composer');
      }
      final geometry = (
        view.physicalSize,
        view.viewInsets,
        view.devicePixelRatio,
        _textScaleAt14(),
      );
      final keyboardStart = view.viewInsets.bottom;
      final focus = _composer!.widget.focusNode;
      var geometryStable = true;
      var focusHeld = focus.hasFocus;
      final run = ++_run;
      _frames.clear();
      _collecting = true;
      final startUs = developer.Timeline.now;
      final startEpochUs = DateTime.now().microsecondsSinceEpoch;
      final watch = Stopwatch()..start();
      final growth = streamingReplayGrowth();
      final achieved = <int>[];
      var consumed = 0;
      developer.Timeline.instantSync(
        'WingWorkspaceReplayStart',
        arguments: {'run': run},
      );
      for (var index = 0; index < workspaceReplayDeltaCount; index++) {
        final deadline = (index + 1) * workspaceReplayIntervalUs;
        await _wait(
          Duration(
            microseconds: math.max(0, deadline - watch.elapsedMicroseconds),
          ),
        );
        final end = ((index + 1) * growth.length / workspaceReplayDeltaCount)
            .floor();
        _emit('message.delta', {'text': growth.substring(consumed, end)});
        consumed = end;
        achieved.add(developer.Timeline.now);
        geometryStable =
            geometryStable &&
            geometry ==
                (
                  view.physicalSize,
                  view.viewInsets,
                  view.devicePixelRatio,
                  _textScaleAt14(),
                );
        focusHeld = focusHeld && focus.hasFocus;
      }
      final streamEndUs = developer.Timeline.now;
      final finalSource = streamingReplayInitial() + growth;
      _fixture!.rows = [
        ..._fixture!.rows,
        {'id': 2, 'role': 'assistant', 'content': finalSource},
      ];
      _emit('message.complete', {
        'status': 'complete',
        'text': finalSource,
        'persisted_turn': {
          'row_ids': [2],
          'complete': true,
          'final_assistant_row_id': 2,
        },
      });
      await _wait(const Duration(milliseconds: 500));
      final endUs = developer.Timeline.now;
      geometryStable =
          geometryStable &&
          geometry ==
              (
                view.physicalSize,
                view.viewInsets,
                view.devicePixelRatio,
                _textScaleAt14(),
              );
      focusHeld = focusHeld && focus.hasFocus;
      developer.Timeline.instantSync(
        'WingWorkspaceReplayEnd',
        arguments: {'run': run},
      );
      await _wait(const Duration(milliseconds: 1500));
      _collecting = false;
      final frames = _frames
          .where((frame) {
            final start = frame.timestampInMicroseconds(FramePhase.buildStart);
            return start >= startUs && start < endUs;
          })
          .map(
            (frame) => {
              'startUs': frame.timestampInMicroseconds(FramePhase.buildStart),
              'buildEndUs': frame.timestampInMicroseconds(
                FramePhase.buildFinish,
              ),
              'rasterStartUs': frame.timestampInMicroseconds(
                FramePhase.rasterStart,
              ),
              'rasterEndUs': frame.timestampInMicroseconds(
                FramePhase.rasterFinish,
              ),
              'rasterFinishEpochUs': frame.timestampInMicroseconds(
                FramePhase.rasterFinishWallTime,
              ),
              'buildUs': frame.buildDuration.inMicroseconds,
              'rasterUs': frame.rasterDuration.inMicroseconds,
            },
          )
          .toList();
      await _awaitRendered(finalSource);
      final exactSource = _chat!.messages.any(
        (row) => row['role'] == 'assistant' && row['content'] == finalSource,
      );
      return {
        'label': label,
        'run': run,
        'startUs': startUs,
        'startEpochUs': startEpochUs,
        'streamEndUs': streamEndUs,
        'endUs': endUs,
        'deltaCount': achieved.length,
        'deltaIntervalUs': workspaceReplayIntervalUs,
        'deltaAchievedUs': achieved,
        'sourceCodeUnits': finalSource.length,
        'source': finalSource,
        'initialSource': streamingReplayInitial(),
        'draft': _chat!.composerText,
        'exactFinalSource': exactSource,
        'finalRendererReady': _rendered(finalSource),
        'completed': !_chat!.busy,
        'geometryStable': geometryStable,
        'focusHeld': focusHeld,
        'keyboardStartPx': keyboardStart,
        'keyboardEndPx': view.viewInsets.bottom,
        'displayRefreshHz': view.display.refreshRate,
        'physicalWidthPx': view.physicalSize.width,
        'physicalHeightPx': view.physicalSize.height,
        'devicePixelRatio': view.devicePixelRatio,
        'textScaleAt14': _textScaleAt14(),
        'nativeDraftStorage': false,
        'valid':
            exactSource &&
            !_chat!.busy &&
            _rendered(finalSource) &&
            geometryStable &&
            focusHeld &&
            keyboardStart > 0 &&
            frames.isNotEmpty,
        'frames': frames,
      };
    } finally {
      _collecting = false;
      _running = false;
      _abort = null;
    }
  }

  @override
  Widget build(BuildContext context) =>
      controller == null || !controller!.initialized
      ? const Scaffold(body: Center(child: Text('Prepare offline replay')))
      : ProfileWorkspaceScreen(
          key: ObjectKey(controller),
          controller: controller!,
        );

  @override
  void dispose() {
    _canceled = true;
    if (_abort case final abort? when !abort.isCompleted) {
      abort.complete();
    }
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_timings);
    controller?.dispose();
    super.dispose();
  }
}
