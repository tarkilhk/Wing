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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final fixture = ProfileBrowserFixture();
    admin = AdministrationFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Home server',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'settings',
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
    int refreshRevision = 0,
    WorkspaceAccent accent = WorkspaceAccent.mint,
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
            appBar: AppBar(title: const Text('Administration')),
            body: HermesAdministrationContent(
              refreshRevision: refreshRevision,
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
      await show(tester, Brightness.dark, refreshRevision: 1);
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
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      admin.requests.clear();
      await show(tester, Brightness.dark, refreshRevision: 2);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(
        admin.requests.where((r) => r.$2 == 'profiles/active'),
        hasLength(1),
      );
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
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-brief')),
          matching: find.text(fixture.description),
        ),
        findsOneWidget,
      );
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
    testWidgets(
      'three administration tabs fit ${brightness.name} and preserve ownership',
      (tester) async {
        await show(tester, brightness);
        expect(find.text('Models and reasoning'), findsOneWidget);
        expect(find.text('Identity'), findsOneWidget);
        await screenshot(tester, '${brightness.name}-profile');
        await tester.tap(find.text('Server'));
        await tester.pumpAndSettle();
        expect(find.text('Providers'), findsOneWidget);
        expect(find.text('Profiles'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Memory'), findsNothing);
        await screenshot(tester, '${brightness.name}-server');
        await tester.tap(find.text('Health'));
        await tester.pumpAndSettle();
        expect(find.text('Selected profile'), findsOneWidget);
        await screenshot(tester, '${brightness.name}-health-profile');
        await tester.scrollUntilVisible(
          find.text('Runtime'),
          250,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Runtime profile: Shared root'), findsOneWidget);
        expect(
          admin.requests.where((r) => r.$2 == 'profiles/active').last.$3,
          isEmpty,
        );
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
    await tester.ensureVisible(find.text('Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'narrow-health');
    await tester.scrollUntilVisible(
      find.text('Doctor'),
      300,
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

  testWidgets(
    'server controls and runtime health remain available without a selected profile',
    (tester) async {
      controller.current = null;
      await show(tester, Brightness.dark, scale: 1.3);
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      expect(find.text('Providers'), findsOneWidget);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(find.text('Runtime profile: Shared root'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'large-text-missing-profile');
    },
  );

  testWidgets('search shows owner and opens the one scoped editor', (
    tester,
  ) async {
    await show(tester, Brightness.light);
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

  testWidgets('opening a server profile returns to the Profile tab', (
    tester,
  ) async {
    await show(tester, Brightness.light);
    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('personal').first);
    await tester.pumpAndSettle();
    expect(find.text('Models and reasoning'), findsOneWidget);
    expect(find.text('Create profile'), findsNothing);
  });

  testWidgets(
    'health recovery opens captured profile access and its shared-provider link',
    (tester) async {
      await show(tester, Brightness.dark);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('More health actions'),
        280,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More health actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review provider access'));
      await tester.pumpAndSettle();
      expect(find.text('Profile access'), findsOneWidget);
      expect(find.text('Server A / personal'), findsOneWidget);
      expect(find.text('Manage shared providers'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    for (final accent in WorkspaceAccent.values) {
      testWidgets(
        'administration preserves the ${accent.name} accent in ${brightness.name}',
        (tester) async {
          await show(tester, brightness, accent: accent);
          final theme = Theme.of(tester.element(find.byType(TabBar)));
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

  testWidgets(
    'Health findings and originating tab survive search and editor return',
    (tester) async {
      await show(tester, Brightness.dark);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Run checks'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run checks'));
      await tester.pumpAndSettle();
      expect(find.text('Check again'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Memory budget');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Memory budget').last);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Run checks'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'runtime metadata failure does not hide supported server health actions',
    (tester) async {
      admin.override = (method, path, query, body) async =>
          throw StateError('offline');
      await show(tester, Brightness.dark);
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Doctor'),
        250,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Profile scope unavailable'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('Retry runtime identity'), findsOneWidget);
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
