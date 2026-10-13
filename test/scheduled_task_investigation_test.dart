import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/screens/administration/admin_scheduled_task_detail_page.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/scheduled_tasks_controller.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';

import 'support/profile_browser_fixture.dart';
import 'support/scheduled_tasks_fixture.dart';

const _error =
    'Script exited with code 1\nstderr:\n'
    '{"status": "partial", "error": "ValueError", "records": 87}';
const _frame = ValueKey('investigation-capture');

class _Fixture {
  final tasks = ScheduledTasksFixture();
  final browser = ProfileBrowserFixture();
  late ProfileWorkspaceController workspace;
  late ScheduledTasksController controller;
  final creates = <(String, Map<String, dynamic>)>[];
  final sends = <(String, Map<String, dynamic>)>[];
  final opened = <ProfileSessionKey>[];
  Completer<void>? createGate, sendGate;
  bool failCreate = false, failNavigate = false;

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tasks.jobs['morning']!['last_error'] = _error;
    controller = ScheduledTasksController(
      ScheduledTasksRepository(tasks.profile),
      prefs,
    );
    await controller.refresh();
    workspace = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: SavedConnection(
          id: tasks.admin.server.connectionId,
          label: 'Home',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      connectionIdentity: tasks.admin.server.connectionIdentity,
      preferences: prefs,
      appPreferences: AppPreferences(prefs),
      gatewayFactory: (scope) {
        final source = browser.gateway(scope);
        return ProfileGateway(
          scope: scope,
          discover: source.discover,
          get: (path, query) async {
            if (path == 'model/options') {
              return {'providers': <Object>[], 'models': <Object>[]};
            }
            return source.read(path, query);
          },
          rpc: (method, params) async {
            if (method == 'session.create') {
              creates.add((scope.profileName, Map.of(params)));
              final number = creates.length;
              await createGate?.future;
              if (failCreate) throw StateError('offline');
              return {
                'session_id': 'runtime-$number',
                'stored_session_id': 'investigation-$number',
                'messages': [],
                'info': {'profile_name': scope.profileName},
              };
            }
            if (method == 'prompt.submit') {
              sends.add((scope.profileName, Map.of(params)));
              await sendGate?.future;
              return {};
            }
            return source.call(method, params);
          },
        );
      },
    );
    await workspace.initialize();
  }

  Future<void> navigate(ProfileSessionKey key) async {
    if (failNavigate) throw StateError('navigation failed');
    opened.add(key);
  }

  Widget page() => AdminScheduledTaskDetailPage(
    controller: controller,
    initial: controller.task('morning')!,
    chatController: workspace,
    onOpenSession: navigate,
  );

  void dispose() {
    workspace.dispose();
    controller.dispose();
  }
}

void main() {
  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
    final flutter = packages.cast<Map>().singleWhere(
      (package) => package['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      config.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '${sdk.path}/bin/cache/artifacts/material_fonts/${font.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
    await (FontLoader('WingIcons')..addFont(
          File(
            'assets/fonts/wing-icons.ttf',
          ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
        ))
        .load();
  });
  late _Fixture fixture;
  setUp(() async {
    fixture = _Fixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.dispose());

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(key: _frame, child: child!),
        ),
        home: fixture.page(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ask personal'),
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('task-detail-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Last run needs attention')),
      alignment: 0.05,
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, bool Function() settled) async {
    for (var attempt = 0; attempt < 100 && !settled(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(settled(), isTrue, reason: 'The expected action did not settle');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Ask targets the failed profile, sends exact error, and clears project',
    (tester) async {
      await fixture.workspace.switchProfile('work');
      await fixture.workspace.selectProject(
        fixture.workspace.current!.projects.first,
      );
      await pump(tester);
      expect(find.byType(AdminAskHermesButton), findsOneWidget);
      await tester.tap(find.text('Ask personal'));
      await tester.pumpAndSettle();
      await waitFor(tester, () => fixture.opened.isNotEmpty);
      expect(fixture.creates.single.$1, 'personal');
      expect(fixture.creates.single.$2['cwd'], isNull);
      expect(fixture.sends.single.$1, 'personal');
      final prompt = fixture.sends.single.$2['text'] as String;
      expect(prompt, contains('Morning briefing'));
      expect(prompt, contains('task ID: morning'));
      expect(prompt, contains('2026-09-17T01:00:00.000Z'));
      expect(prompt, contains(_error));
      expect(prompt, contains('Please investigate'));
      expect(fixture.opened.single.workspace, fixture.tasks.profile.scope);
      expect(fixture.opened.single.sessionId, 'investigation-1');
      expect(fixture.workspace.current!.chat!.projectId, isNull);
      expect(fixture.workspace.current!.selectedProject, isNull);
      expect(
        fixture.workspace.current!.chat!.composer.observation.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pending creation and send show feedback, suppress duplicates, then open',
    (tester) async {
      fixture.createGate = Completer<void>();
      fixture.sendGate = Completer<void>();
      await pump(tester);
      await tester.tap(find.text('Ask personal'));
      await tester.pumpAndSettle();
      expect(fixture.creates, hasLength(1));
      expect(find.byType(StudioLoading), findsOneWidget);
      expect(
        tester.widget<StudioLoading>(find.byType(StudioLoading)).label,
        'Opening investigation chat',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Copy task error',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is StudioPageLoading &&
              w.active &&
              w.label == 'Opening investigation chat',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Ask personal'));
      await tester.pump();
      expect(fixture.creates, hasLength(1));
      fixture.createGate!.complete();
      await tester.pumpAndSettle();
      await waitFor(tester, () => fixture.sends.isNotEmpty);
      expect(fixture.sends, hasLength(1));
      expect(fixture.opened, isEmpty);
      fixture.sendGate!.complete();
      await waitFor(tester, () => fixture.opened.isNotEmpty);
      expect(fixture.opened, hasLength(1));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is StudioPageLoading &&
              w.active &&
              w.label == 'Opening investigation chat',
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('creation failure clears feedback and allows retry', (
    tester,
  ) async {
    fixture.failCreate = true;
    await pump(tester);
    await tester.tap(find.text('Ask personal'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not open the investigation chat. Check the connection and retry.',
      ),
      findsOneWidget,
    );
    expect(fixture.sends, isEmpty);
    fixture.failCreate = false;
    await tester.tap(find.text('Ask personal'));
    await waitFor(tester, () => fixture.opened.isNotEmpty);
    expect(fixture.sends, hasLength(1));
    expect(fixture.opened, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('navigation retry reuses the created chat and submitted prompt', (
    tester,
  ) async {
    fixture.failNavigate = true;
    await pump(tester);
    await tester.tap(find.text('Ask personal'));
    await waitFor(
      tester,
      () => find
          .text(
            'Could not open the investigation chat. Check the connection and retry.',
          )
          .evaluate()
          .isNotEmpty,
    );
    fixture.failNavigate = false;
    await tester.tap(find.text('Ask personal'));
    await waitFor(tester, () => fixture.opened.isNotEmpty);
    expect(fixture.creates, hasLength(1));
    expect(fixture.sends, hasLength(1));
    expect(fixture.opened.single.sessionId, 'investigation-1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'leaving during creation retains draft without sending or navigating',
    (tester) async {
      fixture.createGate = Completer<void>();
      await pump(tester);
      await tester.tap(find.text('Ask personal'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      fixture.createGate!.complete();
      await tester.pumpAndSettle();
      expect(fixture.sends, isEmpty);
      expect(fixture.opened, isEmpty);
      final chat = fixture.workspace
          .browserResource('personal')
          .chats['investigation-1']!;
      expect(chat.composer.observation.text, contains(_error));
    },
  );

  testWidgets(
    'copy preserves exact error and shows pending, copied and failure feedback',
    (tester) async {
      final clipboard = <String>[];
      var gate = Completer<void>();
      var fail = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
            await gate.future;
            if (fail) throw PlatformException(code: 'unavailable');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester);
      await tester.tap(find.byTooltip('Copy task error'));
      await tester.pump();
      expect(find.byTooltip('Copy task error: copying'), findsOneWidget);
      expect(clipboard.single, _error);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copy task error: copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      gate = Completer<void>();
      fail = true;
      await tester.tap(find.byTooltip('Copy task error'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not copy this text. Try again.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('unknown run time is qualified in the investigation prompt', () async {
    fixture.tasks.jobs['morning']!.remove('last_run_at');
    await fixture.controller.refresh();
    final task = fixture.controller.task('morning')!;
    expect(task.failureInvestigationPrompt, contains(_error));
    expect(
      task.failureInvestigationPrompt,
      contains('run time was not recorded'),
    );
  });

  testWidgets('healthy run omits failure actions', (tester) async {
    fixture.tasks.jobs['morning']!.remove('last_error');
    await fixture.controller.refresh();
    await tester.pumpWidget(
      MaterialApp(theme: wingTheme(Brightness.dark), home: fixture.page()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ask personal'), findsNothing);
    expect(find.byTooltip('Copy task error'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('profile change during submission suppresses late navigation', (
    tester,
  ) async {
    fixture.sendGate = Completer<void>();
    await pump(tester);
    await tester.tap(find.text('Ask personal'));
    await waitFor(tester, () => fixture.sends.isNotEmpty);
    await fixture.workspace.switchProfile('work');
    fixture.sendGate!.complete();
    await waitFor(
      tester,
      () => find
          .text('Chat saved in personal. Open it from Chats.')
          .evaluate()
          .isNotEmpty,
    );
    expect(fixture.opened, isEmpty);
    expect(fixture.workspace.current!.scope.profileName, 'work');
    expect(fixture.sends, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_TASK_INVESTIGATION')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_frame),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/design-previews/task-investigation/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final long in [false, true]) {
        testWidgets(
          'failure controls render ${brightness.name} $scale long=$long',
          (tester) async {
            if (long) {
              fixture.tasks.jobs['morning']!['last_error'] = '$_error\n' * 12;
              await fixture.controller.refresh();
            }
            await pump(tester, brightness: brightness, scale: scale);
            expect(find.byTooltip('Copy task error'), findsOneWidget);
            expect(tester.takeException(), isNull);
            final name = '${brightness.name}-$scale-${long ? 'long' : 'short'}';
            await capture(tester, '$name-ready');
            fixture.createGate = Completer<void>();
            fixture.failCreate = true;
            await tester.tap(find.text('Ask personal'));
            await tester.pumpAndSettle();
            expect(find.byType(StudioLoading), findsOneWidget);
            await capture(tester, '$name-opening');
            fixture.createGate!.complete();
            await tester.pumpAndSettle();
            expect(find.byType(StudioLoading), findsNothing);
            expect(
              find.text(
                'Could not open the investigation chat. Check the connection and retry.',
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await capture(tester, '$name-failed');
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
