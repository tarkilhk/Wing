import 'package:wing/core/screens/profile_transcript.dart';
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
import 'package:wing/core/widgets/profile_tool_call.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/widgets/profile_live_execution.dart';

import 'helpers/pump_markdown_widget.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

class _LiveWorkHost extends Host {
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
      rpc: (method, params) => method == 'subagent.list'
          ? Future.value({'subagents': agents})
          : base.call(method, params),
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
        expect(find.byType(ProfileLiveWorkDock), findsOneWidget);
        expect(find.text('Tasks 3/7'), findsOneWidget);
        expect(find.text('2 subagents'), findsOneWidget);
        expect(find.byType(ProfileReasoningDisclosure), findsNothing);
        // The earlier run is folded by the reasoning boundary; its existing
        // tool renderer is lazy until the user opens it.
        expect(find.byType(ProfileToolCall), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('profile-message-composer')),
          'Keep my draft',
        );
        await settle();
        expect(chat.composer.observation.displayedText, 'Keep my draft');
        final composer = find.byKey(const ValueKey('conversation-composer'));
        final rect = tester.getRect(composer);
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
        final liveTool = tester.element(find.byType(ProfileToolCall));
        host.event('a', 'message.delta', {'text': 'The first answer text.'});
        await settle();
        expect(tester.element(find.byType(ProfileToolCall)), same(liveTool));
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
    }
  }
}
