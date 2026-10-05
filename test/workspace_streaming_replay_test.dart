import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';
import 'package:wing/core/widgets/block_reusing_markdown_body.dart';
import 'package:wing/core/widgets/markdown_code_block.dart';

import '../tools/performance/streaming_replay_fixture.dart';
import '../tools/performance/workspace_streaming_replay.dart';
import 'helpers/pump_markdown_widget.dart';

Future<WorkspaceStreamingReplayState> _preparedWorkspace(
  WidgetTester tester,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<WorkspaceStreamingReplayState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: wingTheme(Brightness.light),
      home: WorkspaceStreamingReplay(key: key),
    ),
  );
  Map<String, Object?>? result;
  Object? failure;
  final pending = key.currentState!
      .prepare(requireKeyboard: false)
      .then((value) {
        result = value;
      })
      .catchError((Object error) {
        failure = error;
      });
  for (
    var attempt = 0;
    attempt < 200 && result == null && failure == null;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.settleMarkdown();
  }
  expect(failure, isNull);
  expect(result, isNotNull);
  await pending;
  return key.currentState!;
}

void main() {
  test('render verification rejects missing and stale mounted segments', () {
    const source = 'Visible prose.\n\n```dart\nfinal value = 1;\n```\n';
    final split = splitMarkdownCodeBlocks(source, streaming: true);
    final widgets = split
        .map<Widget>(
          (part) => part is MarkdownCodeBlock
              ? part
              : BlockReusingMarkdownBody(data: part as String),
        )
        .toList();
    expect(
      workspaceReplayMatchesSegments(source, widgets, streaming: true),
      isTrue,
    );
    expect(
      workspaceReplayMatchesSegments(source, widgets.skip(1), streaming: true),
      isFalse,
    );
    expect(
      workspaceReplayMatchesSegments(source, [
        const BlockReusingMarkdownBody(data: 'Old prose.'),
        ...widgets.skip(1),
      ], streaming: true),
      isFalse,
    );
  });

  testWidgets('changed prepared source is rejected before measurement', (
    tester,
  ) async {
    final state = await _preparedWorkspace(tester);
    state.controller!.current!.chat!.reading.appendStreaming(
      'Unexpected input',
    );
    await expectLater(
      state.replay(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Prepared source'),
        ),
      ),
    );
    expect(state.ready()['running'], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pause then resume invalidates preparation', (tester) async {
    final state = await _preparedWorkspace(tester);
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(state.ready()['prepared'], isFalse);
    await expectLater(state.replay(), throwsStateError);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'pause cancels pending frame preparation without waiting for resume',
    (tester) async {
      final key = GlobalKey<WorkspaceStreamingReplayState>();
      await tester.pumpWidget(
        MaterialApp(home: WorkspaceStreamingReplay(key: key)),
      );
      final state = key.currentState!;
      final preparing = state.prepare(requireKeyboard: false);
      final expectation = expectLater(
        preparing,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('canceled'),
          ),
        ),
      );
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await expectation;
      expect(state.ready()['prepared'], isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('offline replay prepares the real workspace and composer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<WorkspaceStreamingReplayState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        home: WorkspaceStreamingReplay(key: key),
      ),
    );
    Map<String, Object?>? result;
    Object? failure;
    final preparing = key.currentState!
        .prepare(requireKeyboard: false)
        .then((value) {
          result = value;
        })
        .catchError((Object error) {
          failure = error;
        });
    for (
      var attempt = 0;
      attempt < 200 && result == null && failure == null;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.settleMarkdown();
    }
    expect(failure, isNull);
    expect(result, isNotNull);
    await preparing;
    expect(result!['prepared'], isTrue);
    expect(result!['nativeDraftStorage'], isFalse);
    expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
    final chat = key.currentState!.controller!.current!.chat!;
    expect(chat.runtime.blocksTurnAdmission, isTrue);
    expect(chat.reading.streaming, streamingReplayInitial());
    final rendered = key.currentState!.renderedReadiness(
      streamingReplayInitial(),
    );
    expect(rendered['rendered'], isTrue, reason: rendered.toString());
    expect(rendered['segmentsMatch'], isTrue);
    expect(rendered['editableMarkers'], greaterThan(0));
    final textField = tester.widget<TextField>(
      find.byKey(const Key('profile-message-composer')),
    );
    expect(textField.focusNode!.hasFocus, isTrue);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Physical typing equivalent',
    );
    await tester.pump();
    expect(
      chat.composer.observation.displayedText,
      'Physical typing equivalent',
    );
    key.currentState!.controller!.current!.gateway.onEvent!(
      StreamEvent(
        type: 'message.delta',
        sessionId: chat.runtime.runtimeId,
        data: {'text': 'A deterministic appended paragraph.'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.settleMarkdown();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MarkdownMessageContent &&
            widget.data ==
                '${streamingReplayInitial()}A deterministic appended paragraph.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(workspaceReplayDeltaCount * workspaceReplayIntervalUs, 20000000);
  });
}
