import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/gateway_sensitive_prompt.dart';
import 'package:wing/core/models/gateway_activity.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/widgets/playful_portrait.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_history_fixture.dart';

void main({Future<void> Function(WidgetTester, String)? capture}) {
  late ProfileWorkspaceController controller;
  late ProfileHistoryFixture host;
  late ProfileChat chat;
  var tailHeight = 0.0;
  var reducedMotion = false;
  List<Widget> currentActivity = [];
  List<Widget> extraTail = [];
  final list = find.byKey(const ValueKey('profile-transcript'));
  final jump = find.byKey(const ValueKey('jump-to-latest'));

  Map<String, dynamic> row(int id) => {
    'id': id,
    'role': 'assistant',
    'content': 'Message $id',
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ProfileHistoryFixture();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'transcript-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = ProfileChat(
      key: ProfileSessionKey(controller.current!.scope, 'chat-0'),
      runtimeId: '',
      title: 'Read-only test',
    );
    controller.current!.chats['chat-0'] = chat;
    controller.current!.selectedSession = 'chat-0';
    await controller.refreshHistory(chat);
    tailHeight = 0;
    reducedMotion = false;
    currentActivity = [];
    extraTail = [];
  });
  tearDown(() => controller.dispose());

  Future<void> show(WidgetTester tester) async {
    if (tester.binding is AutomatedTestWidgetsFlutterBinding) {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => ProfileTranscript(
              key: ValueKey(chat.key),
              chat: chat,
              controller: controller,
              messageBuilder: (m) => SizedBox(
                key: ValueKey('body-${m['id']}'),
                height: 60 + (m['id'] as int) % 3 * 20,
                child: Text(m['content'].toString()),
              ),
              currentActivity: currentActivity,
              tail: [
                if (tailHeight > 0) SizedBox(height: tailHeight),
                ...extraTail,
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> publish(WidgetTester tester) async {
    controller.clearSearch();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('empty greeting yields to messages and history states', (
    tester,
  ) async {
    chat.messages.clear();
    chat.nextHistoryOffset = null;
    await show(tester);
    expect(find.byType(PlayfulPortrait), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);

    chat.historyLoading = true;
    controller.clearSearch();
    await tester.pump();
    expect(find.byType(PlayfulPortrait), findsNothing);
    expect(find.text('Loading history…'), findsOneWidget);

    chat.historyLoading = false;
    chat.historyError = 'History unavailable';
    await publish(tester);
    expect(find.byType(PlayfulPortrait), findsNothing);
    expect(find.text('Refresh history'), findsOneWidget);

    chat.historyError = null;
    extraTail = [const Text('Live work')];
    await publish(tester);
    expect(find.byType(PlayfulPortrait), findsNothing);
    expect(find.text('Live work'), findsOneWidget);

    extraTail = [];
    chat.messages = [row(500)];
    await publish(tester);
    expect(find.byType(PlayfulPortrait), findsNothing);
    expect(find.text('Message 500'), findsOneWidget);
  });

  testWidgets('empty greeting scrolls within a short transcript viewport', (
    tester,
  ) async {
    chat.messages.clear();
    chat.nextHistoryOffset = null;
    await show(tester);
    tester.view.physicalSize = const Size(320, 140);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PlayfulPortrait), findsOneWidget);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
  });

  Finder visibleRow(WidgetTester tester) {
    return find.byWidgetPredicate((w) {
      if (w.key is! ValueKey<String> ||
          !(w.key as ValueKey<String>).value.startsWith('body-')) {
        return false;
      }
      final y = tester.getTopLeft(find.byWidget(w)).dy;
      return y > 150 && y < 400;
    }).first;
  }

  Future<void> toggleInPlace(WidgetTester tester, Finder header) async {
    final before = tester.getTopLeft(header).dy;
    await tester.tapAt(
      Offset(tester.getRect(list).right - 32, tester.getCenter(header).dy),
    );
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(header).dy, closeTo(before, 1));
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, closeTo(before, 1));
  }

  testWidgets(
    '2500 variable-height rows stay lazy; older pages do not signal new activity',
    (tester) async {
      chat.messages = List.generate(2500, (i) => row(i + 100));
      chat.nextHistoryOffset = null;
      await show(tester);
      expect(find.byType(Text).evaluate().length, lessThan(35));
      await tester.drag(list, const Offset(0, 440));
      await tester.pumpAndSettle();
      final anchor = tester.widget(visibleRow(tester)).key!;
      final before = tester.getTopLeft(find.byKey(anchor)).dy;
      chat.messages = [...List.generate(100, row), ...chat.messages];
      await publish(tester);
      expect(tester.getTopLeft(find.byKey(anchor)).dy, closeTo(before, 1));
      expect(find.text('Latest'), findsOneWidget);
      expect(find.text('New activity'), findsNothing);
      expect(find.byType(Text).evaluate().length, lessThan(35));
    },
  );

  testWidgets(
    'a tall new streaming tail preserves the reader and marks new activity',
    (tester) async {
      await show(tester);
      await tester.drag(list, const Offset(0, 480));
      await tester.pumpAndSettle();
      final anchor = tester.widget(visibleRow(tester)).key!;
      final before = tester.getTopLeft(find.byKey(anchor)).dy;
      tailHeight = 1800;
      chat.streaming = 'New streaming output';
      await publish(tester);
      expect(find.byKey(anchor), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(anchor)).dy, closeTo(before, 2));
      expect(find.text('New activity'), findsOneWidget);
      await tester.tap(jump);
      await tester.pumpAndSettle();
      expect(chat.historyScrollOffset, closeTo(0, 1));
      expect(jump, findsNothing);
      chat.streaming = 'More streaming output';
      tailHeight = 2000;
      await publish(tester);
      expect(chat.historyScrollOffset, closeTo(0, 1));
      expect(jump, findsNothing);
    },
  );

  testWidgets('streaming updates do not cancel an active reader drag', (
    tester,
  ) async {
    tailHeight = 100;
    chat.streaming = 'Answer';
    await show(tester);
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    final anchor = tester.widget(visibleRow(tester)).key!;
    final before = tester.getTopLeft(find.byKey(anchor)).dy;
    tailHeight += 40;
    chat.streaming += ' more';
    controller.clearSearch();
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(anchor)).dy, closeTo(before, 1));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(anchor)).dy, closeTo(before + 80, 1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('streaming preserves fling momentum', (tester) async {
    tailHeight = 100;
    chat.streaming = 'Answer';
    await show(tester);
    await tester.fling(list, const Offset(0, 150), 800);
    await tester.pump(const Duration(milliseconds: 16));
    final scroll = tester.widget<ListView>(list).controller!;
    expect(scroll.position.isScrollingNotifier.value, isTrue);
    tailHeight += 40;
    chat.streaming += ' more';
    controller.clearSearch();
    await tester.pump();
    expect(scroll.position.isScrollingNotifier.value, isTrue);
    final before = scroll.offset;
    await tester.pump(const Duration(milliseconds: 16));
    expect(scroll.offset, greaterThan(before));
    await tester.pumpAndSettle();
  });

  testWidgets('a small scroll away from latest opts out of streaming follow', (
    tester,
  ) async {
    tailHeight = 100;
    chat.streaming = 'Answer';
    await show(tester);
    final scroll = tester.widget<ListView>(list).controller!;
    scroll.jumpTo(10);
    await tester.pumpAndSettle();
    final anchor = tester.widget(visibleRow(tester)).key!;
    final before = tester.getTopLeft(find.byKey(anchor)).dy;
    tailHeight += 40;
    chat.streaming += ' more';
    controller.clearSearch();
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(anchor)).dy, closeTo(before, 1));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'reading inside a long streaming answer stays anchored on every frame',
    (tester) async {
      chat.messages = [row(1)];
      chat.nextHistoryOffset = null;
      chat.streaming = 'Answer';
      extraTail = [
        Column(
          children: List.generate(
            100,
            (i) => SizedBox(height: 40, child: Text('Answer line $i')),
          ),
        ),
      ];
      await show(tester);
      await tester.drag(list, const Offset(0, 300));
      await tester.pumpAndSettle();
      final anchor = find.text('Answer line 80');
      final before = tester.getTopLeft(anchor).dy;
      extraTail = [
        Column(
          children: List.generate(
            105,
            (i) => SizedBox(height: 40, child: Text('Answer line $i')),
          ),
        ),
      ];
      chat.streaming += ' more';
      controller.clearSearch();
      await tester.pump();
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
    },
  );

  testWidgets(
    'new durable messages keep reading position, and reduced-motion Latest clears the badge',
    (tester) async {
      reducedMotion = true;
      await show(tester);
      await tester.drag(list, const Offset(0, 450));
      await tester.pumpAndSettle();
      final anchor = tester.widget(visibleRow(tester)).key!;
      final before = tester.getTopLeft(find.byKey(anchor)).dy;
      chat.messages.add(row(621));
      await publish(tester);
      expect(tester.getTopLeft(find.byKey(anchor)).dy, closeTo(before, 2));
      expect(find.text('New activity'), findsOneWidget);
      await tester.tap(jump);
      await tester.pumpAndSettle();
      expect(chat.historyScrollOffset, 0);
      expect(jump, findsNothing);
      expect(chat.messages.last['id'], 621);
    },
  );

  testWidgets('an expanded tool group survives older and newer additions', (
    tester,
  ) async {
    Map<String, dynamic> tool(int id) => {
      'id': id,
      'role': 'tool',
      'tool_name': 'Tool $id',
      'content': 'Output $id',
    };
    chat.messages = [tool(1), tool(2), row(3)];
    chat.nextHistoryOffset = null;
    await show(tester);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('2 tool results')),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 tool results'));
    await tester.pumpAndSettle();
    expect(find.text('Output 1'), findsOneWidget);
    chat.messages.insert(0, tool(0));
    await publish(tester);
    expect(find.text('Output 1'), findsOneWidget);
    chat.messages.insert(3, tool(4));
    await publish(tester);
    expect(find.text('Output 1'), findsOneWidget);
    expect(find.text('Output 4'), findsOneWidget);
  });

  testWidgets('expanding long tool output keeps its header in place', (
    tester,
  ) async {
    chat.messages = [
      ...List.generate(20, row),
      {
        'id': 100,
        'role': 'tool',
        'tool_name': 'Long output',
        'content': List.generate(100, (i) => 'Output line $i').join('\n'),
      },
    ];
    chat.nextHistoryOffset = null;
    await show(tester);
    final activity = find.text('Activity');
    await toggleInPlace(tester, activity);
    final header = find.text('Long output');
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await capture?.call(tester, 'tool-before-expansion');
    await toggleInPlace(tester, header);
    expect(find.text(chat.messages.last['content'] as String), findsOneWidget);
    await capture?.call(tester, 'tool-after-expansion');
    await toggleInPlace(tester, header);
    await toggleInPlace(tester, header);
    final beforeDrag = tester.getTopLeft(header).dy;
    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, lessThan(beforeDrag - 100));
    await tester.tap(jump);
    await tester.pumpAndSettle();
    expect(chat.historyScrollOffset, closeTo(0, 1));
  });

  testWidgets(
    'nested live tool details and reasoning expand without movement',
    (tester) async {
      chat.messages = List.generate(20, row);
      chat.nextHistoryOffset = null;
      currentActivity = [
        ProfileLiveToolActivity(
          activities: [
            GatewayToolActivity(
              name: 'delegate_task',
              phase: GatewayToolActivityPhase.completed,
              arguments: List.generate(100, (i) => 'Argument $i').join('\n'),
              result: 'Result starts here',
            ),
          ],
        ),
      ];
      extraTail = [ProfileReasoningDisclosure(text: 'Reasoning line\n' * 100)];
      await show(tester);
      await toggleInPlace(tester, find.text('Activity'));
      final current = find.text('Current tools');
      await tester.ensureVisible(current);
      await tester.pumpAndSettle();
      await toggleInPlace(tester, current);
      final tool = find.text('Delegate task');
      await tester.ensureVisible(tool);
      await tester.pumpAndSettle();
      await toggleInPlace(tester, tool);
      expect(find.text('Result starts here'), findsOneWidget);
      await capture?.call(tester, 'nested-tool-after-expansion');
      chat.streaming = 'Concurrent streaming update';
      final beforeRefresh = tester.getTopLeft(tool).dy;
      await publish(tester);
      expect(tester.getTopLeft(tool).dy, closeTo(beforeRefresh, 1));
      await toggleInPlace(tester, tool);
      expect(find.text('Result starts here'), findsNothing);
      await tester.tap(jump);
      await tester.pumpAndSettle();
      final thought = find.text('Thought');
      await tester.ensureVisible(thought);
      await tester.pumpAndSettle();
      await toggleInPlace(tester, thought);
    },
  );

  testWidgets('a short conversation keeps the expansion header in place', (
    tester,
  ) async {
    chat.messages = [row(1)];
    chat.nextHistoryOffset = null;
    extraTail = [const ProfileReasoningDisclosure(text: 'A short thought')];
    await show(tester);
    final thought = find.text('Thought');
    await toggleInPlace(tester, thought);
    expect(find.text('A short thought'), findsOneWidget);
    await toggleInPlace(tester, thought);
    expect(chat.historyScrollOffset, closeTo(0, 1));
  });

  testWidgets('empty assistant rows leave existing tool cards in one section', (
    tester,
  ) async {
    chat.messages = [
      {
        'id': 1,
        'role': 'tool',
        'tool_name': 'read_file',
        'content': 'Read output',
      },
      {'id': 2, 'role': 'assistant', 'content': ''},
      {
        'id': 3,
        'role': 'tool',
        'tool_name': 'patch',
        'content': 'Patch output',
      },
      {
        'id': 4,
        'role': 'tool',
        'tool_name': 'terminal',
        'content': 'Test output',
      },
      row(5),
    ];
    chat.nextHistoryOffset = null;
    await show(tester);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('3 tool calls'), findsOneWidget);
    expect(find.text('read_file'), findsNothing);
    expect(find.text('2 tool results'), findsNothing);
    expect(find.text('Message 5'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('read_file'), findsOneWidget);
    expect(find.text('2 tool results'), findsOneWidget);
    expect(find.text('Read output'), findsNothing);
    await Scrollable.ensureVisible(
      tester.element(find.text('read_file')),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('read_file'));
    await tester.pumpAndSettle();
    expect(find.text('Read output'), findsOneWidget);
    expect(find.text('Patch output'), findsNothing);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Read output'), findsNothing);
    expect(find.text('Message 5'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Read output'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    chat.historyScrollOffset = 0;
    await show(tester);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('read_file'), findsNothing);
  });

  testWidgets('long tool history stays compact and prose separates sections', (
    tester,
  ) async {
    chat.messages = [
      for (var i = 0; i < 30; i++) ...[
        {'id': i * 2, 'role': 'assistant', 'content': ''},
        {'id': i * 2 + 1, 'role': 'tool', 'content': 'Output $i'},
      ],
      row(60),
      {'id': 61, 'role': 'tool', 'content': 'Another output'},
      row(62),
    ];
    chat.nextHistoryOffset = null;
    await show(tester);
    expect(find.text('Activity'), findsNWidgets(2));
    expect(find.text('30 tool calls'), findsOneWidget);
    expect(find.text('1 tool call'), findsOneWidget);
    expect(find.text('Tool result'), findsNothing);
    expect(find.text('Message 60').hitTestable(), findsOneWidget);
    expect(find.text('Message 62').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool rows without saved IDs stay collapsed by default', (
    tester,
  ) async {
    chat.messages = [
      {'role': 'tool', 'content': 'Unsaved tool output'},
    ];
    chat.nextHistoryOffset = null;

    await show(tester);

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Unsaved tool output'), findsNothing);
  });

  testWidgets(
    'input requests are discoverable while reading without automatically approving',
    (tester) async {
      await show(tester);
      await tester.drag(list, const Offset(0, 450));
      await tester.pumpAndSettle();
      chat.approval = {'command': 'test command'};
      await publish(tester);
      expect(find.text('Input needed'), findsOneWidget);
      final before = host.calls.length;
      await tester.tap(jump);
      await tester.pumpAndSettle();
      expect(chat.historyScrollOffset, 0);
      expect(chat.approval, isNotNull);
      expect(host.calls.length, before);
    },
  );

  for (final kind in GatewaySensitivePromptKind.values) {
    testWidgets('older-history reading signals ${kind.name} input', (
      tester,
    ) async {
      await show(tester);
      await tester.drag(list, const Offset(0, 450));
      await tester.pumpAndSettle();
      final request = GatewaySensitivePromptRequest.fromEventData(
        kind: kind,
        data: {'request_id': 'reading-request', 'site': 'Fixture site'},
      )!;
      chat.sensitivePrompt = request;
      await publish(tester);
      expect(find.text('Input needed'), findsOneWidget);
      chat.sensitivePrompt = null;
      await publish(tester);
      expect(find.text('Input needed'), findsNothing);
      expect(find.text('Latest'), findsOneWidget);
      chat.sensitivePrompt = request;
      await publish(tester);
      final before = host.calls.length;
      await tester.tap(jump);
      await tester.pumpAndSettle();
      expect(chat.historyScrollOffset, 0);
      expect(chat.sensitivePrompt, same(request));
      expect(host.calls.length, before);
    });
  }

  testWidgets(
    'search context keeps its header visible and expands the matched tool result',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final originalMessages = List<Map<String, dynamic>>.of(chat.messages);
      chat.historyScrollOffset = 84;
      var returned = false;
      final nearby = [
        for (var id = 1; id <= 9; id++)
          id == 5
              ? {
                  'id': id,
                  'role': 'tool',
                  'tool_name': 'read_file',
                  'content': 'Matched tool output',
                }
              : {
                  'id': id,
                  'role': 'assistant',
                  'content': List.filled(30, 'Nearby message $id').join('\n'),
                },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => ProfileTranscript(
                chat: chat,
                controller: controller,
                messageBuilder: (message) =>
                    Text(message['content'].toString()),
                tail: const [],
                nearbyMessages: nearby,
                focusedMessageId: 5,
                onBackToLatest: () => returned = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.clearSearch();
      await tester.pumpAndSettle();

      expect(find.text('Search result'), findsOneWidget);
      expect(find.text('Nearby messages'), findsOneWidget);
      expect(find.text('Back to latest'), findsOneWidget);
      expect(find.text('Matched tool output').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(chat.messages, originalMessages);
      expect(chat.historyScrollOffset, 84);

      await tester.tap(find.text('Back to latest'));
      expect(returned, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(chat.historyScrollOffset, 84);
    },
  );

  testWidgets(
    'an older-page failure retains messages and only retries on request',
    (tester) async {
      await show(tester);
      host.failHistory = true;
      final scroll = tester.widget<ListView>(list).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(chat.historyError, isNotNull);
      expect(chat.messages.length, 50);
      final reads = host.reads.length;
      await tester.pump(const Duration(seconds: 2));
      expect(host.reads.length, reads);
      host.failHistory = false;
      await tester.ensureVisible(find.text('Retry older messages'));
      await tester.tap(find.text('Retry older messages'));
      await tester.pumpAndSettle();
      expect(chat.historyError, isNull);
      expect(chat.messages.length, greaterThanOrEqualTo(100));
      expect(tester.takeException(), isNull);
    },
  );
}
