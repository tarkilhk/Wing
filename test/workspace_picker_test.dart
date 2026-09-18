import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/widgets/server_connection_label.dart';
import 'package:wing/main.dart';

import 'home_config_restore_test.dart' show buildManager;
import 'support/profile_browser_fixture.dart';

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
    testWidgets('${destination.name} splits status from profile selection', (
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
      expect(work, findsOneWidget);
      await tester.tap(work);
      await tester.pumpAndSettle();
      expect(controller.current!.scope.profileName, 'work');
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
    'chat profile switch preserves its draft and opens the new list',
    (tester) async {
      final chat = await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'newest'),
      );
      await controller.updateDraft(chat!, 'Keep this draft');
      await show(tester);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(work);
      await tester.pumpAndSettle();
      expect(controller.current!.scope.profileName, 'work');
      expect(controller.current!.chat, isNull);
      expect(chat.composerText, 'Keep this draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile selection leaves a recovering notification chat', (
    tester,
  ) async {
    fixture.failHistory = true;
    await controller.openNotification(
      ProfileSessionKey(controller.current!.scope, 'newest'),
    );
    expect(controller.notificationChat, isNotNull);
    await show(tester);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(controller.current!.scope.profileName, 'work');
    expect(controller.notificationChat, isNull);
    expect(controller.current!.chat, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed profile switch retains confirmed scope', (tester) async {
    await show(tester);
    fixture.failWork = true;
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(work);
    await tester.pumpAndSettle();
    expect(controller.current!.scope.profileName, 'personal');
    expect(controller.error, isNotNull);
  });

  testWidgets(
    'nested administration scope returns to section before switching',
    (tester) async {
      await show(tester, destination: AppDestination.administration);
      final context = tester.element(find.byType(ServerConnectionLabel));
      adminPush(
        context,
        const AdminPage(
          title: 'Details',
          scope: 'Claw / personal',
          child: Text('Scoped details'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(work);
      await tester.pumpAndSettle();
      expect(find.text('Scoped details'), findsNothing);
      expect(controller.current!.scope.profileName, 'work');
    },
  );

  testWidgets('nested editor guard blocks workspace change', (tester) async {
    await show(tester, destination: AppDestination.administration);
    final context = tester.element(find.byType(ServerConnectionLabel));
    var guarded = false;
    adminPush(
      context,
      PopScope(
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
    expect(guarded, isTrue);
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
