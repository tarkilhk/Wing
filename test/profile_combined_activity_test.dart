import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/screens/bots/bot_screen_view.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/bots_fixture.dart';
import 'dart:convert';
import 'helpers/pump_markdown_widget.dart';
import 'package:wing/core/models/transcript_timeline.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';

const _captureMenu = bool.fromEnvironment('STUDIO_REVIEW');

Future<void> _capture(WidgetTester tester, GlobalKey frame, String name) async {
  if (!_captureMenu) return;
  await tester.runAsync(() async {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rendered = await boundary.toImage();
    final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('build/design-previews/chat-menu')
      ..createSync(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    rendered.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_captureMenu) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  for (final category in ['tasks', 'agents']) {
    testWidgets('saved history restores the $category activity tab', (
      tester,
    ) async {
      final name = category == 'tasks' ? 'todo_list' : 'delegate_task';
      final arguments = category == 'tasks'
          ? <String, dynamic>{}
          : {
              'tasks': [
                {'goal': 'Inspect the saved delegation'},
              ],
            };
      final result = category == 'tasks'
          ? {
              'revision': 2,
              'todos': [
                {
                  'id': 'one',
                  'content': 'Inspect the saved task',
                  'status': 'completed',
                },
              ],
            }
          : {
              'results': [
                {
                  'task_index': 0,
                  'status': 'completed',
                  'summary': 'Inspection complete',
                  'duration_seconds': 42.5,
                  'model': 'test-model',
                  'api_calls': 3,
                },
              ],
              'total_duration_seconds': 43,
            };
      final rows = <Map<String, dynamic>>[
        {
          'id': 1,
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call',
              'type': 'function',
              'function': {'name': name, 'arguments': jsonEncode(arguments)},
            },
          ],
        },
        {
          'id': 2,
          'role': 'tool',
          'tool_call_id': 'call',
          'content': jsonEncode(result),
        },
      ];
      final timeline = TranscriptTimeline.project(
        rows,
        presentationId: (row) => row['id']!,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ProfileToolActivitySection(section: timeline.sections.single),
              ],
            ),
          ),
        ),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^Activity(?: · \d+ tools?)?$')),
      );
      await tester.pumpAndSettle();
      final tab = find.byKey(ValueKey(('activity-tab', category)));
      expect(tab, findsOneWidget);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(
        find.text(
          category == 'tasks'
              ? 'Inspect the saved task'
              : 'Inspect the saved delegation',
        ),
        findsOneWidget,
      );
      if (category == 'agents') {
        expect(find.text('43 s'), findsOneWidget);
        await tester.tap(find.text('Inspect the saved delegation'));
        await tester.pumpAndSettle();
        await tester.settleMarkdown();
        expect(
          find.text('Inspection complete', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Steer'), findsNothing);
        expect(find.text('Interrupt'), findsNothing);
      }
    });
  }

  testWidgets('saved tool calls and current work share one Activity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final host = ProfileActionsFixture();
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'combined-activity',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final chat = await controller.createChat(canDispatch: () => true);
    chat.reading.installSavedHistory([
      ...chat.reading.messages,
      ...[
        {'id': 1, 'role': 'user', 'content': 'Continue searching'},
        for (var id = 2; id <= 68; id++)
          {
            'id': id,
            'role': 'tool',
            'tool_name': 'Search',
            'content': 'Result $id',
          },
      ],
    ]);
    emitChatEvent(controller, chat, 'tool.start', {
      'name': 'terminal',
      'tool_id': 'live',
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ProfileWorkspaceScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'^Activity(?: · \d+ tools?)?$')),
      findsOneWidget,
    );
    expect(find.text('Tool activity'), findsNothing);
    expect(find.text('Activity · 68 tools'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    await tester.tap(
      find.textContaining(RegExp(r'^Activity(?: · \d+ tools?)?$')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsNWidgets(67));
    expect(find.text('Running command'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profile-message-composer')),
      'Keep Activity open while typing',
    );
    await tester.pump();
    expect(find.text('Search'), findsNWidgets(67));
    expect(find.text('Running command'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.text('Search').first),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    expect(find.text('Result 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final canonical in [false, true]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'shared chat menu and screen for ${canonical ? 'canonical' : 'ordinary'} in ${brightness.name} at $scale',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            final preferences = await SharedPreferences.getInstance();
            final appPreferences = AppPreferences(preferences);
            final host = ProfileActionsFixture();
            final controller = ProfileWorkspaceController(
              access: ConnectionAccess(
                connection: SavedConnection(
                  id: 'host',
                  label: 'Home server',
                  host: 'localhost',
                  port: 1,
                  apiKey: '',
                ),
                dashboardOAuth: null,
              ),
              connectionIdentity: 'instance-1',
              preferences: preferences,
              appPreferences: appPreferences,
              gatewayFactory: host.gateway,
            );
            addTearDown(controller.dispose);
            addTearDown(appPreferences.dispose);
            await controller.initialize();
            final chat = await controller.createChat(canDispatch: () => true);
            final fixture = BotsFixture();
            fixture.profiles
              ..clear()
              ..add(
                BotsFixture.profile(chat.key.workspace.profileName, 'Pace'),
              );
            fixture.profiles.single['canonical_session'] = {
              'id': canonical ? chat.key.sessionId : 'another-chat',
            };
            final screenReads = <String>[];
            fixture.readHook = (profile, method, _) async {
              if (method.startsWith('display.')) screenReads.add(profile);
              return null;
            };
            emitChatEvent(controller, chat, 'tool.start', {
              'name': 'terminal',
              'tool_id': 'live',
            });
            emitChatEvent(controller, chat, 'subagent.start', {
              'subagent_id': 'child',
              'goal': 'Inspect the release',
            });
            tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final frame = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: frame, child: child!),
                ),
                home: ProfileWorkspaceScreen(
                  controller: controller,
                  createBotsSession: () =>
                      BotsSession((_) async => [fixture.repository]),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            final name =
                '${canonical ? 'canonical' : 'ordinary'}-${brightness.name}-$scale';
            expect(find.text('Activity · 1 tool'), findsOneWidget);
            await _capture(tester, frame, '$name-chat');
            await tester.tap(find.byTooltip('Chat actions'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            final items = tester
                .widgetList<PopupMenuItem<String>>(
                  find.byWidgetPredicate(
                    (widget) => widget is PopupMenuItem<String>,
                  ),
                )
                .map((item) => item.value)
                .toList();
            expect(items, ['screen', 'outputs', 'find', 'refresh']);
            expect(find.byType(PopupMenuDivider), findsOneWidget);
            for (final label in [
              'View screen',
              'Outputs',
              'Find in chat',
              'Refresh workspace',
            ]) {
              final target = tester.getRect(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is PopupMenuItem<String>,
                  ),
                ),
              );
              expect(target.height, greaterThanOrEqualTo(48));
              expect(target.left, greaterThanOrEqualTo(0));
              expect(
                target.right,
                lessThanOrEqualTo(tester.view.physicalSize.width),
              );
            }
            expect(find.text('Subagents'), findsNothing);
            expect(find.text('Goal'), findsNothing);
            expect(find.text('Background work'), findsNothing);
            await _capture(tester, frame, '$name-menu');
            await tester.tap(find.text('View screen'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(BotScreenView), findsOneWidget);
            expect(find.text('Pace screen'), findsOneWidget);
            expect(screenReads, isNotEmpty);
            expect(screenReads, everyElement(chat.key.workspace.profileName));
            expect(fixture.commands, isEmpty);
            Navigator.of(tester.element(find.byType(BotScreenView))).pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(BotScreenView), findsNothing);
            expect(controller.current!.chat, same(chat));
            expect(find.text('Activity · 1 tool'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  test('screen opening retires an overtaken profile read', () async {
    final fixture = BotsFixture();
    final gate = Completer<Map<String, dynamic>?>();
    fixture.readHook = (_, method, _) =>
        method == 'profiles.list' ? gate.future : Future.value(null);
    final session = BotsSession((_) async => [fixture.repository]);
    addTearDown(session.dispose);
    var current = true;
    final opening = session.openScreen(
      WorkspaceScope(
        connectionId: 'host',
        connectionIdentity: 'instance-1',
        profileName: 'atlas',
      ),
      canUse: () => current,
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    gate.complete(null);
    expect(await opening, isNull);
    expect(fixture.commands, isEmpty);
  });
}
