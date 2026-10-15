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
    expect(find.byType(ProfileActivitySection), findsNothing);
    expect(find.text('Activity · 1 tool'), findsNothing);
    expect(find.text('Activity'), findsNothing);
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
    expect(find.byType(ProfileActivitySection), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(
      find.text('Later live reasoning', findRichText: true),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Activity'));
    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProfileReasoningDisclosure), findsOneWidget);
    expect(
      tester
          .widget<ProfileReasoningDisclosure>(
            find.byType(ProfileReasoningDisclosure),
          )
          .text,
      'Earlier saved reasoning',
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
        await tester.tap(tab(0));
        await settle();
        expect(tester.getRect(composer), rect);
        expect(find.text('Inspect source mappings'), findsOneWidget);
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
        await tester.binding.handlePopRoute();
        await settle();
        expect(find.byType(PageView), findsNothing);
        expect(find.byType(ProfileLiveWorkDock), findsOneWidget);
        expect(find.text('Keep my draft'), findsOneWidget);
        keyboard.value = 0;
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
        host.event('a', 'message.complete', {
          'text': 'The saved final answer.',
        });
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
        expect(find.byType(ProfileLiveWorkDock), findsNothing);
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
        await tester.scrollUntilVisible(
          saved,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ProfileTranscript),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.up,
                ),
              )
              .first,
        );
        await picture('saved-folded');
        await tester.tap(
          find.descendant(of: saved, matching: find.text('Activity · 1 tool')),
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
        await picture('saved-agents');
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
          expect(find.text('Timeline'), findsOneWidget);
          expect(find.text('Activity · 1 tool'), findsNothing);
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
          expect(find.byType(ProfileActivitySection), findsNothing);
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
          expect(find.byType(ProfileActivitySection), findsNothing);
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
          expect(find.byType(ProfileActivitySection), findsOneWidget);
          expect(find.text('Activity'), findsOneWidget);
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
          await tester.ensureVisible(find.text('Activity'));
          await settle();
          // Use the header's leading edge, clear of the centered Latest overlay
          // when the ordinary test font wraps it at enlarged text.
          final activityTitle = tester.getRect(find.text('Activity'));
          await tester.tapAt(
            Offset(activityTitle.left + 4, activityTitle.center.dy),
          );
          await settle();
          // Only authoritative saved reasoning is folded. Neither live block
          // moves into Activity when tools or saved receipts arrive.
          expect(find.byType(ProfileReasoningDisclosure), findsOneWidget);
          expect(find.text('Timeline'), findsNWidgets(4));
          final reasoningLabel = find.descendant(
            of: find.byType(ProfileReasoningDisclosure),
            matching: find.text('Reasoning'),
          );
          await tester.ensureVisible(reasoningLabel);
          await settle();
          await picture('activity');
          // The centered Latest overlay can cover the middle of an enlarged
          // title. Its leading edge remains part of the same tappable row.
          final reasoningTitle = tester.getRect(reasoningLabel);
          await tester.tapAt(
            Offset(reasoningTitle.left + 4, reasoningTitle.center.dy),
          );
          await settle();
          expect(
            find.text(
              'Saved planning before the first tool.',
              findRichText: true,
            ),
            findsWidgets,
          );
          expect(find.byTooltip('Copy Reasoning'), findsOneWidget);
          await tester.ensureVisible(find.byTooltip('Copy Reasoning'));
          await settle();
          await tester.ensureVisible(find.text(heading, findRichText: true));
          await settle();
          await picture('reasoning');
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
