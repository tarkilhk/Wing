import 'package:package_info_plus/package_info_plus.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/services/versions_controller.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/screens/administration/administration_content.dart';
import 'package:wing/core/widgets/profile_selector.dart';
import 'support/administration_fixture.dart';
import 'support/administration_design_fixture.dart';
import 'support/scheduled_tasks_fixture.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'support/profile_browser_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_ADMINISTRATION');
  if (capture) {
    setUpAll(() async {
      const root = String.fromEnvironment('CAPTURE_FONT_DIR');
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
        'monospace': 'monospace.ttf',
      }.entries) {
        await (FontLoader(font.key)..addFont(
              File(
                '$root/${font.value}',
              ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
            ))
            .load();
      }
    });
  }
  late ProfileWorkspaceController controller;
  late AdministrationFixture admin;
  late GlobalKey<ScaffoldState> shellKey;
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.tarkilhk.wing',
      version: '1.0.1',
      buildNumber: '2260',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    final fixture = ProfileBrowserFixture();
    admin = AdministrationFixture();
    shellKey = GlobalKey<ScaffoldState>();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: admin.server.connectionId,
        label: 'Home server',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: admin.server.connectionIdentity,
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());
  Future<void> show(
    WidgetTester tester,
    Brightness brightness, {
    double scale = 1,
    double width = 390,
    WorkspaceAccent accent = WorkspaceAccent.mint,
    bool healthOnly = false,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('admin-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: profileWorkspaceTheme(wingTheme(brightness), accent: accent),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            key: shellKey,
            drawer: AppDrawer(
              selected: healthOnly
                  ? AppDestination.health
                  : AppDestination.administration,
              onSelected: (_) {},
              connection: controller.connection,
              connectionStatus: controller.connectionStatus,
              versionsControllerFactory: (_) =>
                  VersionsController(gateway: admin.server.gateway('default')),
            ),
            body: healthOnly
                ? HermesHealthContent(
                    onOpenMenu: () => shellKey.currentState!.openDrawer(),
                    onOpenSession: (_) async {},
                    controller: controller,
                    repository: admin.server,
                    onConnections: () {},
                  )
                : HermesAdministrationContent(
                    onOpenMenu: () => shellKey.currentState!.openDrawer(),
                    onOpenSession: (_) async {},
                    controller: controller,
                    repository: admin.server,
                    onConnections: () {},
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    // Asset decoding runs outside the widget test's fake clock.
    for (final element in find.byType(Image).evaluate()) {
      final widget = element.widget as Image;
      await tester.runAsync(() => precacheImage(widget.image, element));
    }
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('admin-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/administration-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'header refresh reloads overview reads without duplicate action',
    (tester) async {
      await show(tester, Brightness.dark);
      admin.requests.clear();
      await tester.runAsync(() async {
        await Function.apply(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Refresh administration',
                ),
              )
              .onPressed!,
          const [],
        );
      });
      await tester.pumpAndSettle();
      for (final endpoint in [
        'config',
        'model/info',
        'skills',
        'tools/toolsets',
        'providers/oauth',
        'mcp/servers',
        'cron/jobs',
      ]) {
        expect(
          admin.requests.where((r) => r.$1 == 'GET' && r.$2 == endpoint),
          hasLength(1),
          reason: endpoint,
        );
      }
      expect(find.text('Refresh overview', skipOffstage: false), findsNothing);
      expect(admin.requests.where((r) => r.$1 != 'GET'), isEmpty);
      await show(tester, Brightness.dark, healthOnly: true);
      expect(find.byTooltip('Refresh profile status'), findsOneWidget);
      expect(admin.requests.where((r) => r.$2 == 'profiles/active'), isEmpty);
      expect(admin.requests.where((r) => r.$1 != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'direct profile choices retain canonical administration ownership',
    (tester) async {
      await show(tester, Brightness.dark);
      expect(find.byType(ProfileSelector), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-work')));
      await tester.pumpAndSettle();
      expect(controller.current?.scope.profileName, 'work');
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester
            .widget<ProfileSelector>(find.byType(ProfileSelector))
            .selectedProfile,
        'work',
      );
      await tester.tap(find.text('Memory'));
      await tester.pumpAndSettle();
      expect(
        admin.requests
            .where((r) => r.$2 == 'learning/graph')
            .last
            .$3['profile'],
        'work',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['light', 'dark', 'narrow']) {
    testWidgets('profile brief and attention hierarchy $mode', (tester) async {
      final fixture = AdministrationDesignFixture();
      admin = fixture;
      fixture.jobs.add(
        taskJson(
          id: 'next',
          name: 'Morning research and a deliberately long project name',
        )..['next_run_at'] = '2026-09-18T01:00:00Z',
      );
      controller.discovery = ProfileDiscovery(
        profiles: [
          HermesProfile(
            name: 'personal',
            displayName: 'Personal',
            description: fixture.description,
          ),
          const HermesProfile(
            name: 'work',
            displayName: 'Client research and planning',
          ),
        ],
        currentName: 'personal',
        activeName: 'personal',
      );
      await show(
        tester,
        mode == 'light' ? Brightness.light : Brightness.dark,
        width: mode == 'narrow' ? 320 : 390,
        scale: mode == 'narrow' ? 2 : 1,
      );
      expect(find.text(fixture.description), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-brief')), findsNothing);
      expect(find.text('Describe this agent'), findsNothing);
      await screenshot(tester, '$mode-profile-brief');
      await tester.scrollUntilVisible(
        find.text('Access and connectors'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Setup needed'), findsOneWidget);
      expect(find.text('Sign-in expired'), findsOneWidget);
      await screenshot(tester, '$mode-profile-attention');
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('versions and updates ${brightness.name} at $scale text', (
        tester,
      ) async {
        await show(
          tester,
          brightness,
          scale: scale,
          width: scale == 2 ? 320 : 390,
        );
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('menu-server-version')),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.sync), findsOneWidget);
        await screenshot(tester, '${brightness.name}-$scale-versions-entry');
        final checksBefore = admin.requests
            .where((r) => r.$2 == 'hermes/update/check')
            .length;
        await tester.tap(find.byKey(const ValueKey('menu-server-version')));
        await tester.pumpAndSettle();
        expect(find.text('1.2.3'), findsOneWidget);
        expect(
          find.text('Update available · 3 commits behind'),
          findsOneWidget,
        );
        expect(find.text('Reconnect MCP tools'), findsNothing);
        expect(find.text('Check update progress'), findsNothing);
        expect(
          admin.requests.where((r) => r.$2 == 'hermes/update/check').length,
          checksBefore + 1,
        );
        await screenshot(tester, '${brightness.name}-$scale-versions');
        await tester.ensureVisible(find.text('Changes in this update'));
        await tester.pumpAndSettle();
        final requestCount = admin.requests.length;
        await tester.tap(find.text('Changes in this update'));
        await tester.pumpAndSettle();
        expect(find.text('Showing 2 of 3 commits'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Keep scheduled tasks running after reconnecting'),
          160,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Keep scheduled tasks running after reconnecting'),
          findsOneWidget,
        );
        expect(find.text('Commit: abc1234'), findsNothing);
        expect(admin.requests, hasLength(requestCount));
        await screenshot(tester, '${brightness.name}-$scale-changes');
        await tester.scrollUntilVisible(
          find.text('Commit details'),
          -160,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Commit details'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Commit: abc1234'),
          160,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Commit: abc1234'), findsOneWidget);
        await screenshot(tester, '${brightness.name}-$scale-changes-details');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot(tester, '${brightness.name}-$scale-changes-bottom');
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Update backend'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'administration and Health entry fit ${brightness.name} and preserve ownership',
      (tester) async {
        await show(tester, brightness);
        expect(find.text('Models and reasoning'), findsOneWidget);
        expect(find.text('Identity'), findsOneWidget);
        await screenshot(tester, '${brightness.name}-profile');
        expect(find.byType(TabBar), findsNothing);
        expect(find.text('Profiles'), findsNothing);
        expect(find.text('Versions & updates'), findsNothing);
        await show(tester, brightness, scale: 2, width: 320);
        expect(tester.takeException(), isNull);
        await screenshot(tester, '${brightness.name}-profile-large-text');
        await show(tester, brightness, healthOnly: true);
        expect(find.byTooltip('Refresh profile status'), findsOneWidget);
        await screenshot(tester, '${brightness.name}-health-profile');
        await tester.scrollUntilVisible(
          find.text('Server'),
          250,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Runtime profile:'), findsNothing);
        expect(find.byTooltip('Run all diagnostics'), findsOneWidget);
        expect(admin.requests.where((r) => r.$2 == 'profiles/active'), isEmpty);
        await screenshot(tester, '${brightness.name}-health');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('all root owners remain reachable at 320dp and 200 percent', (
    tester,
  ) async {
    await show(tester, Brightness.dark, scale: 2, width: 320);
    await screenshot(tester, 'narrow-profile');
    await tester.scrollUntilVisible(
      find.text('Scheduled tasks'),
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await screenshot(tester, 'narrow-profile-bottom');
    await show(tester, Brightness.dark, scale: 2, width: 320, healthOnly: true);
    await screenshot(tester, 'narrow-health');
    await tester.scrollUntilVisible(
      find.text('Doctor'),
      100,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await screenshot(tester, 'narrow-health-runtime');
    expect(tester.takeException(), isNull);
  });

  testWidgets('runtime health remains available without a selected profile', (
    tester,
  ) async {
    controller.current = null;
    await show(tester, Brightness.dark, scale: 1.3, healthOnly: true);
    expect(find.byType(TabBar), findsNothing);
    expect(find.textContaining('Runtime profile:'), findsNothing);
    expect(find.byTooltip('Run all diagnostics'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'large-text-missing-profile');
  });

  testWidgets('search shows owner and opens the one scoped editor', (
    tester,
  ) async {
    await show(tester, Brightness.light);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && !widget.readOnly,
      ),
      'providers',
    );
    await tester.pumpAndSettle();
    expect(find.text('Providers'), findsNothing);
    expect(
      find.text('Profile › Access and connectors\nServer A / personal'),
      findsOneWidget,
    );
    await tester.tap(find.text('Access and connectors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Provider access'));
    await tester.pumpAndSettle();
    expect(find.text('Profile access'), findsOneWidget);
    expect(find.text('Server A / personal'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && !widget.readOnly,
      ),
      'Memory budget',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Profile › Memory › Memory settings\nServer A / personal'),
      findsOneWidget,
    );
    await tester.tap(find.text('Memory budget').last);
    await tester.pumpAndSettle();
    expect(find.text('Server A / personal'), findsOneWidget);
    expect(find.text('Memory settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.tap(find.byType(TextFormField).last);
    await tester.pumpAndSettle();
    await screenshot(tester, 'light-editor-keyboard');
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Save')).bottom,
      lessThanOrEqualTo(564),
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'profile management scrolls after the last profile ${brightness.name} $scale',
        (tester) async {
          controller.discovery = const ProfileDiscovery(
            profiles: [
              HermesProfile(name: 'personal'),
              HermesProfile(name: 'client-work'),
              HermesProfile(name: 'reminder-inbox'),
              HermesProfile(name: 'last-profile'),
            ],
            currentName: 'personal',
            activeName: 'personal',
          );
          await show(
            tester,
            brightness,
            scale: scale,
            width: scale == 2 ? 320 : 390,
          );
          final manage = find.byTooltip('Manage profiles');
          final selector = find.byKey(const ValueKey('profile-selector'));
          final last = find.byKey(const ValueKey('profile-last-profile'));
          expect(manage.hitTestable(), findsNothing);
          await screenshot(
            tester,
            '${brightness.name}-$scale-profile-row-start',
          );
          await tester.drag(selector, const Offset(-1600, 0));
          await tester.pumpAndSettle();
          expect(manage.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(manage).left,
            greaterThan(tester.getRect(last).right),
          );
          expect(tester.getSize(manage).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
          await screenshot(tester, '${brightness.name}-$scale-profile-row-end');
          await tester.tap(manage);
          await tester.pumpAndSettle();
          expect(find.text('Create profile'), findsOneWidget);
          await tester.tap(find.text('personal').first);
          await tester.pumpAndSettle();
          expect(find.text('Models and reasoning'), findsOneWidget);
          expect(find.text('Create profile'), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'unknown credential results offer retry without administrative navigation',
    (tester) async {
      await show(tester, Brightness.dark, healthOnly: true);
      await tester.ensureVisible(find.byTooltip('Refresh profile status'));
      await tester.tap(find.byTooltip('Refresh profile status'));
      await tester.pumpAndSettle();
      expect(find.text('Check incomplete'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Fix access'), findsNothing);
      expect(find.text('Manage provider access'), findsNothing);
      expect(find.text('Change model'), findsNothing);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Model access'), findsOneWidget);
      expect(find.text('Profile access'), findsNothing);
    },
  );

  for (final brightness in Brightness.values) {
    for (final accent in WorkspaceAccent.values) {
      testWidgets(
        'administration preserves the ${accent.name} accent in ${brightness.name}',
        (tester) async {
          await show(tester, brightness, accent: accent);
          final theme = Theme.of(
            tester.element(find.byType(HermesAdministrationContent)),
          );
          expect(
            theme.colorScheme.primary,
            brightness == Brightness.dark ? accent.dark : accent.light,
          );
          expect(
            theme.filledButtonTheme.style!.minimumSize!.resolve({}),
            const Size(48, 40),
          );
          await screenshot(tester, '${brightness.name}-${accent.name}-profile');
        },
      );
    }
  }

  testWidgets('Health runtime findings survive returning from an action', (
    tester,
  ) async {
    admin = AdministrationDesignFixture();
    await show(tester, Brightness.dark, healthOnly: true);
    await tester.scrollUntilVisible(
      find.text('Doctor'),
      100,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Run')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Doctor'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(HermesHealthContent), findsOneWidget);
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(
      admin.requests.where((r) => r.$1 == 'POST' && r.$2 == 'ops/doctor'),
      hasLength(1),
    );
    expect(
      admin.requests.where((r) => r.$2 == 'actions/doctor/status'),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'runtime metadata failure does not hide supported server health actions',
    (tester) async {
      admin.override = (method, path, query, body) async =>
          throw StateError('offline');
      await show(tester, Brightness.dark, healthOnly: true);
      await tester.scrollUntilVisible(
        find.text('Doctor'),
        100,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Profile scope unavailable'), findsNothing);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Logs'), findsOneWidget);
      expect(find.byTooltip('Run all diagnostics'), findsOneWidget);
    },
  );

  testWidgets('scheduled tasks opens from Profile with captured ownership', (
    tester,
  ) async {
    await show(tester, Brightness.light);
    final selected = controller.current!.scope.profileName;
    admin.override = (method, path, query, body) async => {'data': []};
    await tester.scrollUntilVisible(
      find.text('Scheduled tasks'),
      250,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scheduled tasks'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No scheduled tasks for this profile. Start with a morning briefing or a weekly review.',
      ),
      findsOneWidget,
    );
    expect(
      admin.requests.where((r) => r.$2 == 'cron/jobs').last.$3['profile'],
      selected,
    );
    expect(find.text('Server A / $selected'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Models and reasoning'), findsOneWidget);
  });
}
