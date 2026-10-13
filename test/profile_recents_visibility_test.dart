import 'package:wing/core/widgets/studio_loading.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wing/core/screens/workspace_overview_content.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/workspace_recents_session.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/recent_identity_card.dart';
import 'support/bots_fixture.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/models/session_visibility.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_browser_fixture.dart';

class TechnicalSessionsFixture extends ProfileBrowserFixture {
  bool oldTechnicalHistory = false;
  String technicalSource = 'oneshot';
  final extraRows = <Map<String, dynamic>>[];
  @override
  List<Map<String, dynamic>> searchRows(String profile, String query) => [
    for (final row in sessions(profile))
      if (row['id'] == query) {...row, 'session_id': row['id']},
  ];
  @override
  List<Map<String, dynamic>> sessions(String profile) => profile != 'personal'
      ? []
      : [
          ...extraRows,
          {
            'id': 'user-chat',
            'title': 'User conversation',
            'source': 'desktop',
            'profile': profile,
            'last_active': now - 120,
          },
          {
            'id': 'technical-run',
            'title': 'Technical command',
            'source': technicalSource,
            'parent_session_id': null,
            'profile': profile,
            'last_active': now - 60,
          },
        ];
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {
      'id': 1,
      'role': 'assistant',
      'content': 'Result',
      'timestamp':
          now - (oldTechnicalHistory && id == 'technical-run' ? 90000 : 60),
    },
  ];
}

const _captureLoading = bool.fromEnvironment('CAPTURE_RECENTS_LOADING');

Future<void> _captureRecents(
  WidgetTester tester,
  GlobalKey frame,
  String name,
) async {
  if (!_captureLoading) return;
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() async {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/design-previews/recents-loading')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_captureLoading) return;
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
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final cached in [false, true]) {
        testWidgets(
          '${cached ? 'usable Recents' : 'Recents initial loading'} has no layout jump ${brightness.name} $scale',
          (tester) async {
            tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            SharedPreferences.setMockInitialValues({});
            final preferences = await SharedPreferences.getInstance();
            final appPreferences = AppPreferences(preferences);
            final fixture = ProfileBrowserFixture();
            final controller = ProfileWorkspaceController(
              access: ConnectionAccess(
                connection: identityTestConnection(),
                dashboardOAuth: null,
              ),
              connectionIdentity: 'review',
              preferences: preferences,
              appPreferences: appPreferences,
              gatewayFactory: fixture.gateway,
            );
            var now = DateTime.now();
            final botFixture = BotsFixture();
            botFixture.events.add({
              'room_id': 'room-1',
              'seq': 1,
              'kind': 'message.member',
              'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
              'actor': {'kind': 'member', 'id': 'atlas'},
              'payload': {'text': 'Saved group reply'},
            });
            final bots = BotsSession(
              (_) async => [botFixture.repository],
              now: () => now,
            );
            final recents = WorkspaceRecentsSession(controller, bots);
            final release = Completer<void>(), started = Completer<void>();
            Future<void>? refresh;
            addTearDown(() {
              if (!release.isCompleted) release.complete();
              recents.dispose();
              bots.dispose();
              controller.dispose();
              appPreferences.dispose();
            });
            await controller.initialize();
            if (cached) await recents.refresh();
            final catalogRelease = Completer<void>();
            addTearDown(() {
              if (!catalogRelease.isCompleted) catalogRelease.complete();
            });
            botFixture.readHook = (_, method, _) async {
              if (method == 'groups.list' && !cached) {
                await catalogRelease.future;
              }
              if (method == 'session.active_list') {
                if (!started.isCompleted) started.complete();
                await release.future;
              }
              return null;
            };
            final frame = GlobalKey();
            var opens = 0;
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
                home: Scaffold(
                  appBar: AppBar(
                    title: const Text('Recents'),
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(48),
                      child: Row(
                        children: const [
                          Expanded(child: Text('Instance')),
                          StudioLoadingSlot(),
                        ],
                      ),
                    ),
                  ),
                  body: WorkspaceActivityContent(
                    recents: recents,
                    visible: true,
                    onOpen: (_, _) => opens++,
                    onOpenGroup: (_) async => opens++,
                  ),
                ),
              ),
            );
            await tester.pump();
            final listPosition = tester.getTopLeft(find.byType(ListView));
            if (cached) {
              expect(recents.items(), isNotEmpty);
              expect(find.byType(StudioLoading), findsNothing);
              now = now.add(const Duration(seconds: 30));
              refresh = recents.refresh(force: true);
            } else {
              for (var i = 0; i < 20; i++) {
                await tester.pump();
              }
              expect(recents.items(), isEmpty);
              final progress = find.byType(StudioLoading);
              expect(progress, findsOneWidget);
              expect(
                find.ancestor(of: progress, matching: find.byType(AppBar)),
                findsOneWidget,
              );
              expect(
                tester.getRect(progress).bottom,
                lessThanOrEqualTo(listPosition.dy),
              );
              expect(
                tester.widget<StudioLoading>(progress).label,
                'Loading recent chats',
              );
              await _captureRecents(
                tester,
                frame,
                'initial-${brightness.name}-$scale',
              );
              refresh = recents.refresh();
              catalogRelease.complete();
            }
            for (var i = 0; i < 20; i++) {
              await tester.pump();
            }
            final readyPosition = listPosition + const Offset(16, 16);
            expect(started.isCompleted, isTrue);
            await tester.pump(const Duration(seconds: 11));
            expect(
              tester.getTopLeft(find.byType(RecentIdentityCard).first),
              readyPosition,
            );
            expect(controller.recentsLoading, isFalse);
            expect(bots.state.loading, isTrue);
            expect(find.text('Research team'), findsOneWidget);
            await _captureRecents(
              tester,
              frame,
              '${cached ? 'cached' : 'cold'}-ready-${brightness.name}-$scale',
            );
            await tester.tap(find.text('Research team'));
            await tester.pump();
            expect(
              opens,
              1,
              reason: 'Recents remains usable while background presence waits',
            );
            final loadingAfterElevenSeconds = find
                .byType(StudioLoading)
                .evaluate()
                .length;
            release.complete();
            for (var i = 0; i < 20; i++) {
              await tester.pump();
            }
            await refresh;
            expect(
              tester.getTopLeft(find.byType(RecentIdentityCard).first),
              readyPosition,
            );
            expect(bots.state.loading, isFalse);
            expect(
              find.byType(StudioLoading),
              findsNothing,
              reason: 'Completion clears the indicator',
            );
            await _captureRecents(
              tester,
              frame,
              '${cached ? 'cached' : 'cold'}-settled-${brightness.name}-$scale',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            expect(
              loadingAfterElevenSeconds,
              0,
              reason:
                  'Ready content must not advertise page loading after 11 seconds',
            );
          },
        );
      }
    }
  }
  testWidgets('empty Recents settles loading without replacing its catalog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    final fixture = ProfileBrowserFixture();
    final controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'empty-loading',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    final release = Completer<void>();
    final bots = BotsSession((_) async {
      await release.future;
      return const [];
    });
    final recents = WorkspaceRecentsSession(controller, bots);
    addTearDown(() {
      if (!release.isCompleted) release.complete();
      recents.dispose();
      bots.dispose();
      controller.dispose();
      appPreferences.dispose();
    });
    await controller.initialize();
    await controller.refreshRecents();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: const [StudioLoadingSlot()]),
          body: WorkspaceActivityContent(
            recents: recents,
            visible: false,
            onOpen: (_, _) {},
            onOpenGroup: (_) async {},
          ),
        ),
      ),
    );
    final catalog = recents.catalog;
    expect(recents.items(), isEmpty);
    expect(find.text('No recent chats'), findsNothing);
    final refresh = bots.refresh();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(recents.contentLoading, isTrue);
    expect(find.byType(StudioLoading), findsOneWidget);
    expect(find.text('No recent chats'), findsNothing);
    release.complete();
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    await refresh;
    expect(recents.catalog, same(catalog));
    expect(recents.contentLoading, isFalse);
    expect(find.byType(StudioLoading), findsNothing);
    expect(find.text('No recent chats'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('Recents excludes the observed oneshot technical run', () async {
    SharedPreferences.setMockInitialValues({});
    final fixture = TechnicalSessionsFixture();
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'technical-recents',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshRecents();
    expect(controller.recentChats().map((chat) => chat.key.sessionId), [
      'user-chat',
    ]);
  });
  for (final running in [false, true]) {
    test('Recents excludes a loaded oneshot run (running=$running)', () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture();
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'loaded-technical',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final resource = controller.current!;
      final chat = await openFixtureChat(
        controller: controller,
        key: ProfileSessionKey(resource.scope, 'technical-run'),
        title: 'Technical command',
        select: false,
      );
      chat.reading.installSavedHistory([
        ...chat.reading.messages,
        {'role': 'assistant', 'content': 'Result', 'timestamp': fixture.now},
      ]);
      if (running) emitChatEvent(controller, chat, 'message.start');

      expect(controller.recentChats(), isEmpty);
    });
  }
  test(
    'Recents excludes a remote live oneshot run with old messages',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture()..oldTechnicalHistory = true;
      fixture.liveSessions['personal'] = [
        {
          'id': 'technical-runtime',
          'session_key': 'technical-run',
          'status': 'working',
          'last_active': fixture.now,
        },
      ];
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'live-technical',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshRecents();
      expect(controller.recentChats().map((chat) => chat.key.sessionId), [
        'user-chat',
      ]);
    },
  );

  for (final source in ['cron', 'tool', 'subagent', 'kanban', 'oneshot']) {
    test(
      'Recents hides $source even with Show automated chats enabled',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fixture = TechnicalSessionsFixture()..technicalSource = source;
        fixture.liveSessions['personal'] = [
          {
            'id': 'technical-runtime',
            'session_key': 'technical-run',
            'status': 'waiting',
            'last_active': fixture.now,
          },
        ];
        final preferences = await SharedPreferences.getInstance();
        final appPreferences = AppPreferences(preferences);
        addTearDown(appPreferences.dispose);
        final controller = ProfileWorkspaceController(
          access: ConnectionAccess(
            connection: identityTestConnection(),
            dashboardOAuth: null,
          ),
          connectionIdentity: 'automation-$source',
          preferences: preferences,
          appPreferences: appPreferences,
          gatewayFactory: fixture.gateway,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.setSessionVisibility(SessionVisibility.all);
        await controller.refreshRecents();
        expect(controller.liveActivity.single.source, source);
        expect(controller.recentChats().map((chat) => chat.key.sessionId), [
          'user-chat',
        ]);
        expect(
          fixture.reads.where(
            (read) => read.$1 == 'sessions/technical-run/messages',
          ),
          isEmpty,
        );
      },
    );
  }

  test(
    'Recents keeps interactive and custom sources, branches and parent background work',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture();
      for (final source in ['cli', 'telegram', 'custom', 'unknown', null]) {
        fixture.extraRows.add({
          'id': 'chat-$source',
          'title': 'Conversation',
          'source': source,
          'profile': 'personal',
          'last_active': fixture.now - 60,
          'parent_session_id': 'user-chat',
        });
      }
      fixture.liveSessions['personal'] = [
        {
          'id': 'user-runtime',
          'session_key': 'user-chat',
          'status': 'idle',
          'side_tasks_running': 2,
          'last_active': fixture.now,
        },
      ];
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'user-sources',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshRecents();
      expect(
        controller.recentChats().map((chat) => chat.key.sessionId),
        unorderedEquals([
          'user-chat',
          'chat-cli',
          'chat-telegram',
          'chat-custom',
          'chat-unknown',
          'chat-null',
        ]),
      );
      expect(
        controller
            .recentChats()
            .singleWhere((chat) => chat.key.sessionId == 'user-chat')
            .sideTasksRunning,
        2,
      );
    },
  );

  test(
    'a full page of internal sessions does not hide later recent chats',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = TechnicalSessionsFixture();
      fixture.extraRows.addAll([
        for (var i = 0; i < 100; i++)
          {
            'id': 'internal-$i',
            'title': 'Internal',
            'source': 'oneshot',
            'profile': 'personal',
            'last_active': fixture.now,
          },
      ]);
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'internal-page',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.refreshRecents();
      expect(controller.recentChats().map((chat) => chat.key.sessionId), [
        'user-chat',
      ]);
      expect(
        fixture.reads.any(
          (read) => read.$1 == 'sessions' && read.$2['offset'] == '100',
        ),
        isTrue,
      );
    },
  );
}
