import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/workspace_overview_content.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/theme/wing_theme.dart';

const _capture = bool.fromEnvironment('CAPTURE_RECENTS');

class _ActivityHost {
  final live = <String, List<Map<String, dynamic>>>{};
  final failed = <String>{};
  bool includeHistory = false;

  Future<ProfileDiscovery> discover() async => ProfileDiscovery(
    profiles: [const HermesProfile(name: 'main')],
    currentName: 'main',
    activeName: 'main',
  );

  ProfileGateway gateway(WorkspaceScope scope) => ProfileGateway(
    scope: scope,
    discover: discover,
    connect: () async {},
    get: (path, query) async => path == 'sessions/search'
        ? {
            'results': [
              for (final row in const [
                {'id': 'running', 'title': 'Running job', 'profile': 'main'},
                {'id': 'needs-input', 'title': 'Question', 'profile': 'main'},
                {
                  'id': 'side-work',
                  'title': 'Deploy checks',
                  'profile': 'main',
                },
                {
                  'id': 'idle-old',
                  'title': 'Idle old server',
                  'profile': 'main',
                },
              ])
                if (row['id'] == query['q'])
                  {
                    'session_id': row['id'],
                    'title': row['title'],
                    'profile': row['profile'],
                  },
            ],
          }
        : RegExp(r'^sessions/[^/]+$').hasMatch(path)
        ? const <Map<String, dynamic>>[
            {'id': 'running', 'title': 'Running job', 'profile': 'main'},
            {'id': 'needs-input', 'title': 'Question', 'profile': 'main'},
            {'id': 'side-work', 'title': 'Deploy checks', 'profile': 'main'},
            {'id': 'idle-old', 'title': 'Idle old server', 'profile': 'main'},
          ].singleWhere(
            (row) => row['id'] == Uri.decodeComponent(path.split('/')[1]),
          )
        : path == 'sessions'
        ? {
            'sessions': [
              if (includeHistory)
                {
                  'id': 'recent',
                  'title': 'Draft the setup guide',
                  'profile': 'main',
                  'last_active':
                      DateTime.now().millisecondsSinceEpoch / 1000 - 7200,
                },
              {'id': 'running', 'title': 'Running job', 'profile': 'main'},
              {'id': 'needs-input', 'title': 'Question', 'profile': 'main'},
              {'id': 'side-work', 'title': 'Deploy checks', 'profile': 'main'},
              {'id': 'idle-old', 'title': 'Idle old server', 'profile': 'main'},
            ],
            'offset': int.parse(query['offset']!),
            'limit': int.parse(query['limit']!),
            'total': includeHistory ? 5 : 4,
          }
        : {
            'session_id': path.split('/')[1],
            'messages': <Map<String, dynamic>>[
              if (includeHistory && path == 'sessions/recent/messages')
                {
                  'id': 1,
                  'role': 'assistant',
                  'content': 'Guide ready',
                  'timestamp':
                      DateTime.now().millisecondsSinceEpoch / 1000 - 7200,
                },
            ],
            'pagination': {
              'offset': 0,
              'limit': int.parse(query['limit'] ?? '50'),
              'returned': includeHistory && path == 'sessions/recent/messages'
                  ? 1
                  : 0,
              'order': 'latest',
            },
          },
    rpc: (method, params) async {
      if (method == 'session.active_list') {
        if (failed.contains(scope.profileName)) throw StateError('offline');
        return {'sessions': live[scope.profileName] ?? []};
      }
      if (method == 'projects.tree') return {'projects': []};
      return {};
    },
  );
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  late _ActivityHost host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _ActivityHost();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'activity-filter-test',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    host.live['main'] = [
      {
        'id': 'runtime-running',
        'session_key': 'running',
        'status': 'working',
        'last_active': 2,
      },
      {
        'id': 'runtime-input',
        'session_key': 'needs-input',
        'status': 'waiting',
        'last_active': 1,
        'side_tasks_running': 0,
      },
      {
        'id': 'runtime-side',
        'session_key': 'side-work',
        'status': 'idle',
        'last_active': 3,
        'side_tasks_running': 2,
      },
      {
        'id': 'runtime-idle-old',
        'session_key': 'idle-old',
        'status': 'idle',
        'last_active': 4,
      },
    ];
    await controller.refreshRecents();
  });

  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('work and history at $scale in ${brightness.name}', (
        tester,
      ) async {
        host.includeHistory = true;
        final now = DateTime.now().millisecondsSinceEpoch / 1000;
        for (final (index, row) in host.live['main']!.indexed) {
          row['last_active'] = now - (index + 1) * 180;
        }
        await controller.refreshRecents();
        expect(controller.recentChats(), hasLength(4));
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
              child: RepaintBoundary(key: frame, child: child),
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Recents')),
              body: WorkspaceActivityContent(
                controller: controller,
                onOpen: (_, displayed) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final ongoing = find.byKey(const ValueKey('recents-ongoing'));
        expect(
          find.descendant(of: ongoing, matching: find.text('Deploy checks')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: ongoing,
            matching: find.text('Draft the setup guide'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        Future<void> capture(String suffix) async {
          if (!_capture) return;
          final boundary =
              frame.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/recents-review/${brightness.name}-$scale-$suffix.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('top');
        await tester.scrollUntilVisible(
          find.text('Draft the setup guide'),
          200,
        );
        expect(find.text('Draft the setup guide'), findsOneWidget);
        expect(find.text('Last 24 hours'), findsOneWidget);
        expect(find.text('Recent'), findsNothing);
        expect(tester.takeException(), isNull);
        await capture('history');
      });
    }
  }

  testWidgets('filters activity, opens an owner item, and fits large text', (
    tester,
  ) async {
    ProfileRecentChat? opened;
    List<ProfileRecentChat>? displayedAtOpen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: SizedBox(
            width: 320,
            child: Scaffold(
              body: WorkspaceActivityContent(
                controller: controller,
                onOpen: (item, displayed) {
                  opened = item;
                  displayedAtOpen = displayed;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Running job'), findsOneWidget);
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('Deploy checks'), findsOneWidget);
    expect(find.textContaining('2 background tasks running'), findsOneWidget);
    expect(find.text('Idle old server'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Needs input'));
    await tester.pump();
    expect(find.text('Running job'), findsNothing);
    expect(find.text('Question'), findsOneWidget);
    await tester.tap(find.text('Question'));
    expect(opened?.key.sessionId, 'needs-input');
    expect(displayedAtOpen!.map((chat) => chat.key.sessionId), ['needs-input']);
    expect(() => displayedAtOpen!.clear(), throwsUnsupportedError);

    await tester.tap(find.widgetWithText(FilterChip, 'Running'));
    await tester.pump();
    expect(find.text('Running job'), findsOneWidget);
    expect(find.text('Question'), findsNothing);
    expect(find.text('Deploy checks'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pump();
    expect(find.text('Question'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retains activity-unavailable error', (tester) async {
    host.failed.add('main');
    await controller.refreshRecents();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceActivityContent(
            controller: controller,
            onOpen: (_, displayed) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Live status could not be loaded.'), findsOneWidget);
    expect(find.text('No recent chats'), findsNothing);
  });
}
