import 'package:wing/core/screens/profile_transcript.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';
import 'package:wing/core/widgets/profile_activity_tabs.dart';
import 'package:wing/core/widgets/profile_live_work_dock.dart';
import 'package:wing/core/widgets/profile_subagent_panel.dart';
import 'package:wing/core/widgets/profile_tool_call.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/widgets/profile_live_execution.dart';
import 'package:wing/core/widgets/transcript_latest_button.dart';

import 'helpers/pump_markdown_widget.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

class _LiveWorkHost extends Host {
  Completer<Map<String, dynamic>>? pendingRoster;
  int rosterReads = 0;
  final agents = [
    for (var i = 0; i < 2; i++)
      {
        'subagent_id': 'agent-$i',
        'goal': i == 0
            ? 'Inspect source mappings'
            : 'Research metric definitions',
        'status': 'running',
      },
  ];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    late final ProfileGateway gateway;
    gateway = ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: () async {
        if (gateway.onEvent != null) gateways[scope.profileName] = gateway;
        await base.connect();
      },
      close: base.close,
      get: base.read,
      rpc: (method, params) {
        if (method == 'subagent.list') {
          rosterReads++;
          return pendingRoster?.future ?? Future.value({'subagents': agents});
        }
        return base.call(method, params);
      },
    );
    return gateway;
  }
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_LIVE_WORK_DOCK');
  setUpAll(() async {
    if (!capture) return;
    for (final font in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(
            font.key,
          )..addFont(File(font.value).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  testWidgets('saved partial history preserves readable live reasoning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final app = AppPreferences(prefs);
    final host = _LiveWorkHost()
      ..historyMessages = [
        {'id': 1, 'role': 'user', 'content': 'Find local lunch in Bangkok.'},
      ];
    final controller = ProfileWorkspaceController(
      connectionIdentity: 'partial-live-activity',
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      preferences: prefs,
      appPreferences: app,
      gatewayFactory: host.gateway,
    );
    addTearDown(() {
      controller.dispose();
      app.dispose();
    });
    await controller.initialize();
    final chat = await controller.createChat(canDispatch: () => true);
    host.event('a', 'message.start');
    host.event('a', 'tool.complete', {
      'tool_id': 'one',
      'name': 'web_search',
      'result': 'First search result',
    });
    host.event('a', 'reasoning.available', {'text': 'Later live reasoning'});
    host.event('a', 'tool.start', {'tool_id': 'two', 'name': 'web_extract'});
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: ProfileWorkspaceScreen(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.settleMarkdown();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProfileActivitySection), findsNWidgets(2));
    expect(find.text('Timeline'), findsNothing);
    await tester.openLiveActivity();
    expect(
      find.text('Later live reasoning', findRichText: true),
      findsOneWidget,
    );
    final currentTool = tester.element(
      find.byWidgetPredicate(
        (widget) => widget is ProfileToolCall && widget.call.callId == 'two',
      ),
    );
    host.historyMessages = [
      {'id': 1, 'role': 'user', 'content': 'Find local lunch in Bangkok.'},
      {
        'id': 2,
        'role': 'assistant',
        'content': '',
        'reasoning': 'Earlier saved reasoning',
      },
      {
        'id': 3,
        'role': 'assistant',
        'content': '',
        'reasoning': 'Later live reasoning',
        'tool_calls': [
          {
            'id': 'two',
            'function': {'name': 'web_extract', 'arguments': '{}'},
          },
        ],
      },
    ];
    await controller.refreshHistory(chat);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.settleMarkdown();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProfileActivitySection), findsNWidgets(2));
    expect(find.text('Activity · 1 tool'), findsNWidgets(2));
    expect(find.byType(ProfileReasoningDisclosure), findsNothing);
    await tester.openLiveActivity();
    expect(
      find.text('Later live reasoning', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(ProfileReasoningDisclosure), findsNothing);
    expect(
      find.text('Earlier saved reasoning', findRichText: true),
      findsOneWidget,
    );
    expect(chat.reading.messages.any((row) => row['id'] == 3), isTrue);
    expect(
      tester.element(
        find.byWidgetPredicate(
          (widget) => widget is ProfileToolCall && widget.call.callId == 'two',
        ),
      ),
      same(currentTool),
    );
    expect(chat.reading.messages.where((row) => row['id'] == 2), hasLength(1));
    final persistence = Completer<void>();
    host.heldHistoryStarted = Completer<void>();
    host.heldHistoryDelay = persistence;
    host.heldHistoryFailure = StateError(
      'Saved history temporarily unavailable',
    );
    addTearDown(() {
      if (!persistence.isCompleted) persistence.complete();
    });
    host.event('a', 'message.complete', {
      'text': 'Final answer before persistence',
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.settleMarkdown();
    expect(host.heldHistoryStarted!.isCompleted, isTrue);
    tester
        .widget<ScrollView>(find.byKey(const ValueKey('profile-transcript')))
        .controller!
        .jumpTo(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.settleMarkdown();
    expect(
      find.byType(ProfileActivitySection),
      findsOneWidget,
      reason: 'Received final answer must not split saved and retained work',
    );
    persistence.complete();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.settleMarkdown();
    expect(find.byType(ProfileActivitySection), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('live work production route ${brightness.name} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final app = AppPreferences(prefs);
        final host = _LiveWorkHost()
          ..todoState = {
            'revision': 4,
            'todos': [
              for (var i = 0; i < 7; i++)
                {
                  'id': 'task-$i',
                  'content': [
                    'Read retained health data',
                    'Confirm source units',
                    'Map sleep metrics',
                    'Research definitions for the remaining metrics',
                    'Build the health domain model',
                    'Validate mappings',
                    'Report findings',
                  ][i],
                  'status': i < 3
                      ? 'completed'
                      : i == 3
                      ? 'in_progress'
                      : i == 6
                      ? 'cancelled'
                      : 'pending',
                },
            ],
          };
        final controller = ProfileWorkspaceController(
          connectionIdentity: 'live-work-render',
          access: ConnectionAccess(
            connection: identityTestConnection(),
            dashboardOAuth: null,
          ),
          preferences: prefs,
          appPreferences: app,
          gatewayFactory: host.gateway,
        );
        addTearDown(() {
          controller.dispose();
          app.dispose();
        });
        await controller.initialize();
        final chat = await controller.createChat(canDispatch: () => true);
        await controller.refreshSubagents(chat);
        host.event('a', 'message.start');
        host.event('a', 'tool.complete', {
          'tool_id': 'retained',
          'name': 'read_file',
          'args': {'path': 'health/metrics.md'},
          'result': '## Health metrics\n\nRetained source units.',
          'duration_s': .195,
        });
        host.event('a', 'reasoning.delta', {
          'text':
              'I’m mapping the **health domain** from the retained data.\n\n'
              'The sleep pipeline stays as existing work. Next I’ll verify the remaining units.',
        });
        host.event('a', 'tool.start', {
          'tool_id': 'research',
          'name': 'web_search',
          'args': {'query': 'health metric definitions'},
        });
        host.event('a', 'todo.updated', {'revision': 5, 'todos': []});
        final frame = GlobalKey();
        final keyboard = ValueNotifier<double>(0);
        addTearDown(keyboard.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: keyboard,
              builder: (_, inset, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                  viewInsets: EdgeInsets.only(bottom: inset),
                ),
                child: RepaintBoundary(key: frame, child: child!),
              ),
            ),
            home: ProfileWorkspaceScreen(controller: controller),
          ),
        );
        Future<void> settle() async {
          await tester.pump(const Duration(milliseconds: 300));
          await tester.settleMarkdown();
          await tester.pump();
        }

        Future<void> picture(String state) async {
          if (!capture) return;
          await tester.runAsync(() async {
            final bitmap =
                await (frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await bitmap.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('build/design-previews/live-work-native')
                ..createSync(recursive: true);
              await File(
                '${dir.path}/route-${brightness.name}-$scale-$state.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              bitmap.dispose();
            }
          });
        }

        Finder tab(int i, {bool overlay = true}) =>
            find.byKey(ValueKey(('live-work-tab', i, overlay)));
        await settle();
        expect(find.text('Timeline'), findsNothing);
        await tester.openLiveActivity();
        await settle();
        final sharedTranscript = tester.widget<ProfileTranscript>(
          find.byType(ProfileTranscript),
        );
        expect(
          sharedTranscript.activity?.runtime.runtimeId,
          chat.runtime.runtimeId,
        );
        expect(sharedTranscript.activity?.live, isTrue);
        expect(find.byType(ProfileLiveWorkDock), findsOneWidget);
        expect(find.text('Tasks 3/7'), findsNothing);
        expect(find.text('2 subagents'), findsOneWidget);
        expect(find.byType(ProfileReasoningDisclosure), findsNothing);
        // Both tool runs stay visible around the received reasoning.
        expect(find.byType(ProfileToolCall), findsNWidgets(2));
        await tester.enterText(
          find.byKey(const Key('profile-message-composer')),
          'Keep my draft',
        );
        await settle();
        expect(chat.composer.observation.displayedText, 'Keep my draft');
        final composer = find.byKey(const ValueKey('conversation-composer'));
        final rect = tester.getRect(composer);
        await picture('agents-only-folded');
        expect(tab(1, overlay: false), findsNothing);
        await tester.tap(tab(0, overlay: false));
        await settle();
        await picture('agents-only-open');
        final fittedAgents = tester.getSize(find.byType(PageView)).height;
        expect(fittedAgents, lessThanOrEqualTo(320));
        host.event('a', 'todo.updated', {
          'revision': 6,
          'todos': host.todoState!['todos'],
        });
        await settle();
        expect(find.text('Tasks 3/7'), findsWidgets);
        expect(tester.getRect(composer), rect);
        expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page,
          0,
        );
        expect(tester.getSize(find.byType(PageView)).height, fittedAgents);
        await picture('second-tab-arrived');
        await tester.tap(tab(0));
        await settle();
        await picture('folded');
        await tester.tap(tab(1, overlay: false));
        await settle();
        expect(tester.getRect(composer), rect);
        expect(
          find.text('Research definitions for the remaining metrics'),
          findsOneWidget,
        );
        await picture('tasks');
        final drawer = find.byKey(const ValueKey('live-work-panel'));
        final handle = find.byKey(const ValueKey('live-work-handle'));
        final compact = tester.getRect(drawer);
        final taskSummary = tester.getRect(find.byType(ProfileTodoSummary));
        await tester.drag(find.byType(PageView), const Offset(0, -100));
        await settle();
        expect(tester.getRect(find.byType(ProfileTodoSummary)), taskSummary);
        await tester.fling(handle, const Offset(0, -500), 1000);
        await settle();
        expect(tester.getRect(drawer).top, closeTo(8, 1));
        expect(tester.getRect(drawer).bottom, compact.bottom);
        expect(tester.getRect(composer), rect);
        await picture('tasks-expanded');
        await tester.tap(tab(0));
        await settle();
        expect(tester.getRect(composer), rect);
        expect(find.text('Inspect source mappings'), findsOneWidget);
        expect(tester.getRect(drawer).top, closeTo(8, 1));
        expect(find.text('0 of 2 completed · 2 running'), findsOneWidget);
        await picture('subagents-expanded');
        await tester.fling(handle, const Offset(0, 500), 1000);
        await settle();
        expect(tester.getSize(drawer).height, lessThanOrEqualTo(320));
        await picture('subagents');

        void expectNoReadButtons() {
          final panel = find.byType(ProfileSubagentPanel);
          expect(panel, findsOneWidget);
          for (final label in ['Refresh', 'Retry']) {
            expect(
              find.descendant(of: panel, matching: find.byTooltip(label)),
              findsNothing,
            );
          }
        }

        expectNoReadButtons();
        final beforeRetry = host.rosterReads;
        await tester.tap(tab(0));
        await settle();
        host.pendingRoster = Completer<Map<String, dynamic>>();
        await tester.tap(tab(0, overlay: false));
        await tester.pump();
        expect(host.rosterReads, beforeRetry + 1);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        await settle();
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.text('Inspect source mappings'), findsOneWidget);
        expect(tester.getRect(composer), rect);
        expectNoReadButtons();
        await picture('roster-held');
        host.pendingRoster!.completeError(StateError('Roster unavailable'));
        await settle();
        expect(chat.subagentsError, isNotNull);
        expect(
          find.text('${chat.subagentsError!} Reopen to retry.'),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expectNoReadButtons();
        await picture('roster-failed');
        // The same tab closes the drawer. Reopening is the retry control.
        await tester.tap(tab(0));
        await settle();
        expect(find.byType(PageView), findsNothing);
        host.pendingRoster = Completer<Map<String, dynamic>>();
        await tester.tap(tab(0, overlay: false));
        await tester.pump();
        expect(host.rosterReads, beforeRetry + 2);
        expect(chat.subagentsError, isNull);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expectNoReadButtons();
        host.pendingRoster!.complete({'subagents': host.agents});
        await settle();
        host.pendingRoster = null;
        expect(chat.subagentsError, isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Inspect source mappings'), findsOneWidget);
        expect(chat.composer.observation.displayedText, 'Keep my draft');
        expect(tester.getRect(composer), rect);
        expectNoReadButtons();
        await picture('roster-recovered');
        keyboard.value = 260;
        await settle();
        expect(tester.getRect(composer).bottom, lessThanOrEqualTo(844 - 260));
        expect(
          tester.getRect(find.byType(PageView)).top,
          greaterThanOrEqualTo(56),
        );
        await picture('keyboard');
        await tester.tap(handle);
        await settle();
        expect(tester.getRect(drawer).top, closeTo(8, 1));
        expect(
          tester.getRect(drawer).bottom,
          lessThan(tester.getRect(composer).top),
        );
        await picture('keyboard-expanded');
        await tester.binding.handlePopRoute();
        await settle();
        expect(find.byType(PageView), findsNothing);
        expect(find.byType(ProfileLiveWorkDock), findsOneWidget);
        expect(find.text('Keep my draft'), findsOneWidget);
        keyboard.value = 0;
        await settle();
        await tester.openLiveActivity();
        await settle();
        // The transcript is lazy: inspect retention while the tool is visible,
        // rather than expecting an offscreen row to remain mounted.
        await tester.scrollUntilVisible(
          find.byType(ProfileToolCall).last,
          120,
          scrollable: find
              .descendant(
                of: find.byType(ProfileTranscript),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle();
        final liveTool = tester.element(find.byType(ProfileToolCall).last);
        host.event('a', 'message.delta', {'text': 'The first answer text.'});
        await settle();
        expect(
          tester.element(find.byType(ProfileToolCall).last),
          same(liveTool),
        );
        // The shorter direct Timeline may already be at the newest edge.
        final latest = find.byType(TranscriptLatestButton);
        if (latest.evaluate().isNotEmpty) {
          await tester.tap(latest);
          await settle();
        }
        expect(
          find.text('The first answer text.', findRichText: true),
          findsOneWidget,
        );
        keyboard.value = 0;
        for (final agent in host.agents) {
          agent['status'] = 'completed';
        }
        host.historyMessages = [
          {'id': 1, 'role': 'user', 'content': 'Map the health metrics.'},
          {
            'id': 2,
            'role': 'tool',
            'tool_call_id': 'retained',
            'tool_name': 'read_file',
            'args': {'path': 'health/metrics.md'},
            'content': 'Retained source units.',
          },
          {'id': 3, 'role': 'assistant', 'content': 'The mapping is underway.'},
          {
            'id': 4,
            'role': 'user',
            'display_kind': 'async_delegation_complete',
            'display_metadata': {
              'task_count': 1,
              'display_text':
                  'Subagent Task Completed: Inspect source mappings',
            },
            'content': 'Verified the health mappings.',
          },
          {
            'id': 5,
            'role': 'tool',
            'tool_call_id': 'research',
            'tool_name': 'web_search',
            'args': {'query': 'health metric definitions'},
            'content': 'Checked the metric definitions.',
          },
          {'id': 6, 'role': 'assistant', 'content': 'The saved final answer.'},
        ];
        // A completion receipt can save while its parent is still streaming.
        // That must not move or duplicate the canonical agent into Activity.
        final finalAnswer = host.historyMessages!.removeLast();
        await controller.refreshHistory(chat);
        await settle();
        expect(chat.runtime.executionActive, isTrue);
        expect(chat.reading.messages.any((row) => row['id'] == 4), isTrue);
        // Reveal the lazy current row after the expanded drawer/keyboard visit.
        for (
          var attempt = 0;
          attempt < 12 &&
              find.byKey(const ValueKey('live-activity')).evaluate().isEmpty;
          attempt++
        ) {
          await tester.drag(
            find.byKey(const ValueKey('profile-transcript')),
            const Offset(0, 160),
          );
          await settle();
        }
        await tester.openLiveActivity();
        await settle();
        final liveTabs = find.descendant(
          of: find.byType(ProfileLiveExecution),
          matching: find.byType(ProfileActivityTabs),
        );
        expect(liveTabs, findsWidgets);
        for (final tabs in tester.widgetList<ProfileActivityTabs>(liveTabs)) {
          expect(tabs.tabs.map((tab) => tab.id), ['timeline']);
        }
        expect(
          find.text('Subagent Task Completed: Inspect source mappings'),
          findsNothing,
        );
        await picture('current-receipt-timeline');
        await tester.tap(tab(0, overlay: false));
        await settle();
        expect(find.text('Inspect source mappings'), findsOneWidget);
        expect(chat.subagents.every((agent) => agent.isTerminal), isTrue);
        await picture('current-receipt-drawer');
        host.historyMessages!.add(finalAnswer);
        host.event('a', 'message.complete', {
          'text': 'The saved final answer.',
        });
        await tester.pump();
        expect(chat.runtime.executionActive, isFalse);
        expect(tab(0), findsNothing);
        expect(tab(0, overlay: false), findsNothing);
        await settle();
        expect(find.byType(ProfileSubagentPanel), findsNothing);
        expect(tab(1), findsOneWidget);
        await picture('turn-ended-drawer');
        await tester.binding.handlePopRoute();
        await settle();
        for (var i = 0; i < 8; i++) {
          await settle();
          if (!chat.runtime.executionActive) break;
        }
        expect(chat.runtime.executionActive, isFalse);
        for (final agent in host.agents) {
          host.event('a', 'subagent.complete', {
            'subagent_id': agent['subagent_id'],
            'status': 'completed',
          });
        }
        await settle();
        expect(chat.subagents.every((agent) => agent.isTerminal), isTrue);
        expect(chat.reading.streamingMessage, isNull);
        expect(find.byType(ProfileLiveWorkDock), findsOneWidget);
        expect(tab(0, overlay: false), findsNothing);
        expect(tab(1, overlay: false), findsOneWidget);
        expect(find.byType(ProfileLiveExecution), findsNothing);
        expect(find.text('Keep my draft'), findsOneWidget);
        expect(
          find.text('Subagent Task Completed: Inspect source mappings'),
          findsNothing,
        );
        final saved = find.byWidgetPredicate(
          (widget) =>
              widget is ProfileToolActivitySection &&
              widget.section.containsMessage(4),
        );
        expect(chat.reading.messages.any((row) => row['id'] == 4), isTrue);
        final savedTitle = find.descendant(
          of: saved,
          matching: find.text('Activity · 1 tool'),
        );
        // Navigate through the actual viewport. Whole-row ensureVisible can
        // place a lazily resized row's header outside a short enlarged viewport.
        for (var i = 0; i < 20; i++) {
          if (savedTitle.evaluate().isNotEmpty) {
            await tester.ensureVisible(savedTitle);
            await settle();
          }
          if (savedTitle
              .hitTestable(at: Alignment.centerLeft)
              .evaluate()
              .isNotEmpty) {
            break;
          }
          await tester.drag(
            find.byType(ProfileTranscript),
            const Offset(0, 120),
          );
          await settle();
        }
        expect(
          savedTitle.hitTestable(at: Alignment.centerLeft),
          findsOneWidget,
        );
        await picture('saved-folded');
        final savedTitleRect = tester.getRect(savedTitle);
        await tester.tapAt(
          Offset(savedTitleRect.left + 4, savedTitleRect.center.dy),
        );
        await settle();
        expect(
          find.descendant(of: saved, matching: find.text('Timeline')),
          findsOneWidget,
        );
        expect(
          find.text('Subagent Task Completed: Inspect source mappings'),
          findsNothing,
        );
        final agents = find.descendant(
          of: saved,
          matching: find.text('Agents'),
        );
        await tester.ensureVisible(agents);
        await settle();
        // Anchored expansion can retain the header while large tabs extend
        // below the viewport. Scroll the actual tab into reach before tapping.
        for (
          var i = 0;
          i < 10 && agents.hitTestable().evaluate().isEmpty;
          i++
        ) {
          final viewport = tester.getRect(find.byType(ProfileTranscript));
          final movement = (viewport.center.dy - tester.getCenter(agents).dy)
              .clamp(-150.0, 150.0);
          await tester.drag(
            find.byType(ProfileTranscript),
            Offset(0, movement),
          );
          await settle();
        }
        expect(agents.hitTestable(), findsOneWidget);
        await tester.tap(agents);
        await settle();
        expect(
          find.descendant(
            of: saved,
            matching: find.text(
              'Subagent Task Completed: Inspect source mappings',
            ),
          ),
          findsOneWidget,
        );
        final result = find.descendant(
          of: saved,
          matching: find.text('View result'),
        );
        await tester.ensureVisible(result);
        await settle();
        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey<(String, Object?)>(('transcript-notice', 4)),
            ),
            matching: find.byIcon(Icons.expand_more),
          ),
        );
        await settle();
        final output = find.text(
          'Verified the health mappings.',
          findRichText: true,
        );
        expect(output, findsOneWidget);
        await tester.ensureVisible(output);
        await settle();
        await picture('turn-ended-saved-agents');
        await picture('saved-agents');
        // Keep reading the previous Activity instead of following the newest
        // edge when the next turn adds rows to the lazy transcript.
        await tester.drag(find.byType(ProfileTranscript), const Offset(0, 240));
        await settle();
        expect(output, findsOneWidget);
        // Start another answer while the previous Activity remains open on
        // Agents. Its completed children must no longer occupy the live dock.
        host.historyMessages!.add({
          'id': 7,
          'role': 'user',
          'content': 'Now find massage venues.',
        });
        await controller.refreshHistory(chat);
        host.event('a', 'message.start');
        host.event('a', 'message.delta', {'text': 'Checking nearby venues.'});
        await settle();
        expect(chat.runtime.executionActive, isTrue);
        expect(tab(0, overlay: false), findsNothing);
        expect(tab(1, overlay: false), findsOneWidget);
        expect(find.text('2 subagents'), findsNothing);
        await tester.ensureVisible(output);
        await settle();
        expect(output, findsOneWidget);
        await picture('next-round-previous-agents');
        keyboard.value = 260;
        await settle();
        final newest = find.byKey(const ValueKey('jump-to-latest'));
        if (newest.evaluate().isNotEmpty) {
          await tester.tap(newest);
          await settle();
        }
        expect(tab(0, overlay: false), findsNothing);
        expect(
          find.text('Checking nearby venues.', findRichText: true),
          findsOneWidget,
        );
        await picture('next-round-keyboard');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      testWidgets(
        'reasoning handoff production route ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final app = AppPreferences(prefs);
          final host = _LiveWorkHost()
            ..historyMessages = [
              {
                'id': 1,
                'role': 'user',
                'content': 'Find hotels within the travel policy.',
              },
            ];
          final controller = ProfileWorkspaceController(
            connectionIdentity: 'reasoning-handoff-render',
            access: ConnectionAccess(
              connection: identityTestConnection(),
              dashboardOAuth: null,
            ),
            preferences: prefs,
            appPreferences: app,
            gatewayFactory: host.gateway,
          );
          addTearDown(() {
            controller.dispose();
            app.dispose();
          });
          await controller.initialize();
          final chat = await controller.createChat(canDispatch: () => true);
          host.event('a', 'message.start');
          host.event('a', 'tool.complete', {
            'tool_id': 'policy',
            'name': 'read_file',
            'args': {'path': 'business-trip-policy.md'},
            'result': 'Use the official booking pages.',
          });
          final frame = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(key: frame, child: child!),
              ),
              home: ProfileWorkspaceScreen(controller: controller),
            ),
          );
          Future<void> settle() async {
            await tester.pump(const Duration(milliseconds: 300));
            await tester.settleMarkdown();
            await tester.pump(const Duration(milliseconds: 300));
          }

          Future<void> picture(String state) async {
            if (!capture) return;
            await tester.runAsync(() async {
              final bitmap =
                  await (frame.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              try {
                final bytes = await bitmap.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory('build/design-previews/live-work-native')
                  ..createSync(recursive: true);
                await File(
                  '${dir.path}/handoff-${brightness.name}-$scale-$state.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                bitmap.dispose();
              }
            });
          }

          await settle();
          expect(find.text('Timeline'), findsNothing);
          expect(find.text('Activity · 1 tool'), findsOneWidget);
          await picture('tools-collapsed');
          await tester.openLiveActivity();
          await settle();
          expect(find.text('Timeline'), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('profile-message-composer')),
            'Keep my draft',
          );
          await settle();
          final composer = find.byKey(const ValueKey('conversation-composer'));
          final bounds = tester.getRect(composer);
          await picture('tools-only');
          const heading = 'Searching for Tokyo hotels';
          const reasoningBody = 'Check the official booking pages for Gotanda.';
          host.event('a', 'reasoning.delta', {
            'text': '**$heading**\n\n$reasoningBody',
          });
          await settle();
          await tester.openLiveActivity();
          await settle();
          expect(find.text('Thinking'), findsOneWidget);
          expect(find.text(heading, findRichText: true), findsOneWidget);
          expect(tester.getRect(composer), bounds);
          await picture('thinking');
          host.event('a', 'tool.start', {
            'tool_id': 'booking',
            'name': 'web_search',
            'args': {'query': 'Tokyo Gotanda official booking'},
          });
          await settle();
          expect(chat.runtime.executionActive, isTrue);
          expect(find.text('Thinking'), findsNothing);
          expect(find.text(heading, findRichText: true), findsOneWidget);
          expect(find.text('Reasoning'), findsOneWidget);
          expect(find.byType(ProfileActivitySection), findsNWidgets(2));
          expect(find.byType(ProfileToolCall), findsOneWidget);
          // Opening the earlier run preserves its header. Move through the
          // viewport to inspect the reasoning and the next collapsed run.
          await tester.ensureVisible(
            find.text(reasoningBody, findRichText: true),
          );
          await settle();
          final latest = find.byKey(const ValueKey('jump-to-latest'));
          if (latest.evaluate().isNotEmpty) {
            await tester.tap(latest);
            await settle();
          }
          await picture('tool-handoff-collapsed');
          await tester.openLiveActivity();
          expect(find.text('Timeline'), findsNWidgets(2));
          expect(find.byType(ProfileToolCall), findsNWidgets(2));
          expect(tester.getRect(composer), bounds);
          expect(chat.composer.observation.displayedText, 'Keep my draft');
          await tester.ensureVisible(
            find.text(reasoningBody, findRichText: true),
          );
          await settle();
          await picture('tool-handoff-readable');
          host.event('a', 'tool.complete', {
            'tool_id': 'booking',
            'name': 'web_search',
            'result': 'Received booking search results.',
          });
          for (var i = 0; i < 11; i++) {
            host.event('a', 'tool.complete', {
              'tool_id': 'lunch-source-$i',
              'name': 'web_search',
              'args': {'query': 'Local Bangkok lunch source $i'},
              'result': 'Received source $i.',
              'duration_s': 32,
            });
          }
          host.event('a', 'reasoning.available', {
            'text': 'Check the restaurant menu and opening hours.',
          });
          for (final entry in {
            'lunch-query': 'web_search',
            'hours-query': 'web_search',
            'lunch-page': 'web_extract',
            'menu-image': 'vision_analyze',
          }.entries) {
            host.event('a', 'tool.complete', {
              'tool_id': entry.key,
              'name': entry.value,
              'args': {'query': 'Bangkok local lunch ${entry.key}'},
              'result': 'Received ${entry.key}.',
              'duration_s': 32,
            });
          }
          await settle();
          expect(find.byType(ProfileActivitySection), findsNWidgets(3));
          await tester.openLiveActivity();
          expect(find.text(heading, findRichText: true), findsOneWidget);
          expect(
            find.text(
              'Check the restaurant menu and opening hours.',
              findRichText: true,
            ),
            findsOneWidget,
          );
          expect(find.text('Timeline'), findsNWidgets(3));
          expect(find.byType(ProfileToolCall), findsNWidgets(17));
          expect(tester.getRect(composer), bounds);
          await tester.ensureVisible(
            find.text(reasoningBody, findRichText: true),
          );
          await settle();
          await picture('multiple-cycles-readable');
          host.historyMessages = [
            {
              'id': 1,
              'role': 'user',
              'content': 'Find hotels within the travel policy.',
            },
            {
              'id': 2,
              'role': 'assistant',
              'content': '',
              'reasoning': 'Saved planning before the first tool.',
            },
            {
              'id': 3,
              'role': 'tool',
              'tool_call_id': 'policy',
              'tool_name': 'read_file',
              'content': 'Use the official booking pages.',
            },
          ];
          await controller.refreshHistory(chat);
          await settle();
          expect(find.byType(ProfileActivitySection), findsNWidgets(3));
          expect(find.text('Activity · 12 tools'), findsOneWidget);
          expect(find.text('Activity · 4 tools'), findsOneWidget);
          expect(find.text(heading, findRichText: true), findsOneWidget);
          expect(
            find.text(
              'Check the restaurant menu and opening hours.',
              findRichText: true,
            ),
            findsOneWidget,
          );
          expect(chat.reading.messages.any((row) => row['id'] == 3), isTrue);
          expect(tester.getRect(composer), bounds);
          await tester.ensureVisible(
            find.text(reasoningBody, findRichText: true),
          );
          await settle();
          await picture('history-refreshed-readable');
          // Saved current-turn reasoning uses the same readable body. Receipt
          // persistence does not introduce another Activity or hide the prose.
          expect(find.byType(ProfileReasoningDisclosure), findsNothing);
          await tester.openLiveActivity();
          await settle();
          expect(find.text('Timeline'), findsNWidgets(3));
          final savedReasoning = find.text(
            'Saved planning before the first tool.',
            findRichText: true,
          );
          expect(savedReasoning, findsOneWidget);
          await tester.ensureVisible(savedReasoning);
          await settle();
          await picture('reasoning');
          await tester.ensureVisible(find.text(heading, findRichText: true));
          await settle();
          await picture('live-reasoning');
          expect(find.text(heading, findRichText: true), findsOneWidget);
          expect(chat.runtime.executionActive, isTrue);
          expect(tester.getRect(composer), bounds);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
