import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/screens/administration/admin_settings_page.dart';
import 'package:wing/core/screens/administration/admin_connectors_page.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/widgets/server_connection_label.dart';
import 'package:wing/main.dart';

import 'home_config_restore_test.dart' show buildManager;
import 'support/profile_browser_fixture.dart';
import 'support/administration_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_WORKSPACE_PICKER');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });
  late ProfileWorkspaceController controller;
  late ProfileBrowserFixture fixture;
  final first = SavedConnection(
    id: 'claw',
    label: 'Claw',
    host: 'localhost',
    port: 1,
    apiKey: '',
  );
  final second = SavedConnection(
    id: 'travel',
    label: 'Travel server',
    host: 'localhost',
    port: 2,
    apiKey: '',
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = ProfileBrowserFixture();
    controller = ProfileWorkspaceController(
      connection: first,
      connectionIdentity: 'picker-claw',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  Future<void> show(
    WidgetTester tester, {
    AppDestination destination = AppDestination.chats,
    Brightness brightness = Brightness.dark,
    double scale = 1,
    Future<void> Function(SavedConnection, AppDestination)? onConnection,
  }) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
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
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
        home: ProfileWorkspaceScreen(
          controller: controller,
          initialDestination: destination,
          savedConnections: () => [first, second],
          onSelectConnection: onConnection,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final status = find.byKey(const ValueKey('connection-status-target'));
  final picker = find.byKey(const ValueKey('workspace-picker-target'));
  final work = find.byKey(const ValueKey('workspace-profile-work'));

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/workspace-picker-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final destination in [
    AppDestination.chats,
    AppDestination.activity,
    AppDestination.administration,
    AppDestination.health,
  ]) {
    testWidgets('${destination.name} picker follows the displayed scope', (
      tester,
    ) async {
      await show(tester, destination: destination);
      expect(tester.getSize(status).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(picker).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(status).overlaps(tester.getRect(picker)), isFalse);
      await tester.tapAt(tester.getBottomRight(status) - const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(find.text('Connection details'), findsOneWidget);
      expect(work, findsNothing);
      await tester.tap(find.byTooltip('Close connection details'));
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('Connection details'), findsNothing);
      final includesProfile =
          destination == AppDestination.administration ||
          destination == AppDestination.health;
      expect(work, includesProfile ? findsOneWidget : findsNothing);
      expect(
        find.text('Profile'),
        includesProfile ? findsWidgets : findsNothing,
      );
      expect(
        find.byTooltip(
          includesProfile
              ? 'Choose connection and profile'
              : 'Choose connection',
        ),
        findsOneWidget,
      );
      if (includesProfile) {
        await tester.tap(work);
      } else {
        expect(find.text('Claw · personal'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('workspace-connection-claw')),
        );
      }
      await tester.pumpAndSettle();
      expect(
        controller.current!.scope.profileName,
        includesProfile ? 'work' : 'personal',
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppDrawer>(find.byType(AppDrawer, skipOffstage: false))
            .selected,
        destination,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('picker renders ${brightness.name} at $scale', (
        tester,
      ) async {
        await show(
          tester,
          destination: AppDestination.administration,
          brightness: brightness,
          scale: scale,
        );
        await screenshot(tester, 'header-${brightness.name}-$scale');
        await tester.tap(picker);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot(tester, 'picker-${brightness.name}-$scale');
        final semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('workspace-profile-personal')),
          ),
          isSemantics(isSelected: true),
        );
        semantics.dispose();
        await tester.tapAt(const Offset(5, 800));
        await tester.pumpAndSettle();
        expect(work, findsNothing);
        expect(controller.current!.scope.profileName, 'personal');
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-activity')));
        await tester.pumpAndSettle();
        expect(find.text('Claw · personal'), findsNothing);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        expect(work, findsNothing);
        expect(find.text('Profile'), findsNothing);
        expect(tester.takeException(), isNull);
        await screenshot(tester, 'connections-${brightness.name}-$scale');
      });
    }
  }

  testWidgets('connection choice retains current section', (tester) async {
    (String, AppDestination)? selected;
    await show(
      tester,
      destination: AppDestination.activity,
      onConnection: (connection, destination) async {
        selected = (connection.id, destination);
      },
    );
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-connection-travel')));
    await tester.pumpAndSettle();
    expect(selected, ('travel', AppDestination.activity));
  });

  testWidgets(
    'conversation header offers only connections and retains its draft',
    (tester) async {
      final chat = await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'newest'),
      );
      await controller.updateDraft(chat!, 'Keep this draft');
      String? selected;
      await show(
        tester,
        onConnection: (connection, destination) async {
          selected = connection.id;
          expect(destination, AppDestination.chats);
        },
      );
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(work, findsNothing);
      expect(find.text('Profile'), findsNothing);
      expect(find.byTooltip('Choose connection'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('workspace-connection-travel')),
      );
      await tester.pumpAndSettle();
      expect(selected, 'travel');
      expect(controller.current!.scope.profileName, 'personal');
      expect(chat.composerText, 'Keep this draft');
    },
  );

  testWidgets('server-owned administration header offers only connections', (
    tester,
  ) async {
    await show(tester, destination: AppDestination.administration);
    adminPush(
      tester.element(find.byType(ServerConnectionLabel)),
      (context) => const AdminPage(
        title: 'Server logs',
        scope: 'Claw',
        child: Text('Logs'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(work, findsNothing);
    expect(find.text('Profile'), findsNothing);
    expect(find.byTooltip('Choose connection'), findsOneWidget);
  });

  testWidgets('failed profile switch retains confirmed scope', (tester) async {
    await show(tester, destination: AppDestination.administration);
    fixture.failWork = true;
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(controller.current!.scope.profileName, 'personal');
    expect(controller.error, isNotNull);
  });

  testWidgets('Usage offers only profiles and reloads the selected owner', (
    tester,
  ) async {
    final administration = AdministrationFixture('Claw');
    addTearDown(administration.server.close);
    administration.override = (_, path, _, _) async =>
        path == 'analytics/models' ? {'models': []} : {'daily': []};
    await show(tester, destination: AppDestination.health);
    adminPushProfile(
      tester.element(find.byType(ServerConnectionLabel)),
      administration.server.profile('personal'),
      (_, profile) => AdminUsagePage(profile: profile),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Choose profile'), findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(work, findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-connection-claw')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workspace-connection-travel')),
      findsNothing,
    );
    expect(find.text('Connection'), findsNothing);
    await screenshot(tester, 'usage-profile-only');
    final before = administration.requests.length;
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(find.text('Usage'), findsOneWidget);
    expect(find.text('Claw / work'), findsOneWidget);
    expect(controller.current!.scope.profileName, 'work');
    expect(administration.requests.skip(before).length, 3);
    expect(
      administration.requests
          .skip(before)
          .every((r) => r.$3['profile'] == 'work'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile picker keeps Connectors open on the selected profile', (
    tester,
  ) async {
    final administration = AdministrationFixture('Claw');
    addTearDown(administration.server.close);
    await show(tester, destination: AppDestination.health);
    final context = tester.element(find.byType(ServerConnectionLabel));
    adminPushProfile(
      context,
      administration.server.profile('personal'),
      (context, profile) => AdminConnectorsPage(profile: profile),
    );
    await tester.pumpAndSettle();
    expect(find.text('MCP connectors'), findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(find.text('MCP connectors'), findsOneWidget);
    expect(find.text('Claw / work'), findsOneWidget);
    expect(controller.current!.scope.profileName, 'work');
    expect(
      administration.requests.any(
        (request) =>
            request.$2 == 'mcp/servers' && request.$3['profile'] == 'work',
      ),
      isTrue,
    );
  });

  testWidgets('Health Connectors stays open across profile changes and Back', (
    tester,
  ) async {
    await show(tester, destination: AppDestination.health);
    await tester.ensureVisible(find.text('Connectors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connectors'));
    await tester.pumpAndSettle();
    expect(find.text('Connectors'), findsOneWidget);
    for (final name in ['work', 'personal', 'work']) {
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('workspace-profile-$name')));
      await tester.pumpAndSettle();
      expect(find.text('Connectors'), findsOneWidget);
      expect(find.text('Claw / $name'), findsOneWidget);
      expect(find.text(AppDestination.health.label), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(AppDestination.health.label), findsOneWidget);
    expect(controller.current!.scope.profileName, 'work');
  });

  testWidgets('nested profile routes keep their stack and reload both owners', (
    tester,
  ) async {
    final administration = AdministrationFixture('Claw');
    addTearDown(administration.server.close);
    await show(tester, destination: AppDestination.administration);
    adminPushProfile(
      tester.element(find.byType(ServerConnectionLabel)),
      administration.server.profile('personal'),
      (context, profile) => AdminPage(
        title: 'Parent',
        scope: profile.label,
        child: TextButton(
          onPressed: () => adminPushProfile(
            context,
            profile,
            (context, profile) => AdminConnectorsPage(profile: profile),
          ),
          child: const Text('Open connectors'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open connectors'));
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(find.text('MCP connectors'), findsOneWidget);
    expect(find.text('Claw / work'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Parent'), findsOneWidget);
    expect(find.text('Claw / work'), findsOneWidget);
    await tester.tap(find.text('Open connectors'));
    await tester.pumpAndSettle();
    expect(find.text('MCP connectors'), findsOneWidget);
    expect(find.text('Claw / work'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'nested selection keeps its page while loading (failure: $fails)',
      (tester) async {
        final administration = AdministrationFixture('Claw');
        addTearDown(administration.server.close);
        await show(tester, destination: AppDestination.health);
        adminPushProfile(
          tester.element(find.byType(ServerConnectionLabel)),
          administration.server.profile('personal'),
          (context, profile) => AdminConnectorsPage(profile: profile),
        );
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        fixture.delays['work'] = gate;
        fixture.failWork = fails;
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(work);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('MCP connectors'), findsOneWidget);
        expect(find.text('Claw / personal'), findsOneWidget);
        expect(controller.switching, isTrue);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('MCP connectors'), findsOneWidget);
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.text('MCP connectors'), findsOneWidget);
        expect(
          find.text(fails ? 'Claw / personal' : 'Claw / work'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'connector details resolve identity within the selected profile',
    (tester) async {
      final administration = AdministrationFixture('Claw');
      addTearDown(administration.server.close);
      administration.override = (method, path, query, body) async => {
        'servers': query['profile'] == 'personal'
            ? [
                {'name': 'example', 'auth': 'oauth'},
              ]
            : [],
      };
      await show(tester, destination: AppDestination.health);
      adminPushProfile(
        tester.element(find.byType(ServerConnectionLabel)),
        administration.server.profile('personal'),
        (context, profile) =>
            AdminConnectorDetail(profile: profile, name: 'example'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test connection'), findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(work);
      await tester.pumpAndSettle();
      expect(find.text('example'), findsOneWidget);
      expect(find.text('Claw / work'), findsOneWidget);
      expect(
        find.text('This connector is not available in this profile.'),
        findsOneWidget,
      );
      expect(find.text('Test connection'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
      expect(
        administration.requests.every((request) => request.$1 == 'GET'),
        isTrue,
      );
    },
  );

  testWidgets(
    'editor reloads and saves only the selected profile, preserving dirty drafts',
    (tester) async {
      final administration = AdministrationFixture('Claw');
      addTearDown(administration.server.close);
      await show(tester, destination: AppDestination.administration);
      adminPushProfile(
        tester.element(find.byType(ServerConnectionLabel)),
        administration.server.profile('personal'),
        (context, profile) => AdminSettingsPage(
          profile: profile,
          title: 'Memory settings',
          fields: [memoryFields[2]],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2000'), findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(work);
      await tester.pumpAndSettle();
      expect(find.text('Memory settings'), findsOneWidget);
      expect(find.text('3000'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '3500');
      await tester.pump();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-profile-personal')),
      );
      await tester.pumpAndSettle();
      expect(find.text('3500'), findsOneWidget);
      expect(controller.current!.scope.profileName, 'work');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        (administration.configs['work']!['memory'] as Map)['memory_char_limit'],
        3500,
      );
      expect(
        (administration.configs['personal']!['memory']
            as Map)['memory_char_limit'],
        2000,
      );
      expect(
        administration.requests
            .where((request) => request.$1 == 'PUT')
            .every((request) => request.$3['profile'] == 'work'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nested editor guard blocks workspace change', (tester) async {
    await show(tester, destination: AppDestination.administration);
    final context = tester.element(find.byType(ServerConnectionLabel));
    var guarded = false;
    final administration = AdministrationFixture('Claw');
    addTearDown(administration.server.close);
    adminPushProfile(
      context,
      administration.server.profile('personal'),
      (context, profile) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          guarded = !didPop;
        },
        child: const AdminPage(
          title: 'Edit',
          scope: 'Claw / personal',
          child: Text('Unsaved draft'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(guarded, isFalse);
    expect(
      find.text('Finish or discard your edits before switching profiles.'),
      findsOneWidget,
    );
    expect(find.text('Unsaved draft'), findsOneWidget);
    expect(controller.current!.scope.profileName, 'personal');
  });

  testWidgets(
    'Home replaces connection, preserves section and retained owner',
    (tester) async {
      final manager = await buildManager();
      final a = await manager.saveConnection('Claw', 'localhost', 1, '');
      final b = await manager.saveConnection('Travel', 'localhost', 2, '');
      final owners = <String, ProfileWorkspaceController>{};
      ProfileWorkspaceController owner(SavedConnection connection) =>
          owners.putIfAbsent(connection.id, () {
            final value = ProfileWorkspaceController(
              connection: connection,
              connectionIdentity: connection.id,
              preferences: manager.prefs,
              gatewayFactory: ProfileBrowserFixture().gateway,
            );
            addTearDown(value.dispose);
            return value;
          });
      await manager.prefs.setString('last_connection_id', a.id);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(connManager: manager, profileController: owner),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-activity')));
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('workspace-connection-${b.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProfileWorkspaceScreen>(find.byType(ProfileWorkspaceScreen))
            .controller
            .connection
            .id,
        b.id,
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppDrawer>(find.byType(AppDrawer)).selected,
        AppDestination.activity,
      );
      expect(manager.prefs.getString('last_connection_id'), b.id);
      expect(owners[a.id]!.initialized, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
