import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/models/backend_update.dart';

/// Read-only shell/navigation acceptance against the owner's running server.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'existing Hermes server exposes Administration through the app drawer',
    (tester) async {
      const port = int.fromEnvironment('HERMES_TEST_PORT');
      expect(port, greaterThan(0));
      SharedPreferences.setMockInitialValues({});
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'existing-local',
          label: 'Local Hermes',
          host: '127.0.0.1',
          port: port,
          dashboardPortOverride: port,
          apiKey: '',
        ),
        connectionIdentity: 'existing-admin-readonly',
        preferences: await SharedPreferences.getInstance(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(await controller.switchProfile('android-qa-a'), isTrue);
      var connectionsRequested = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: ProfileWorkspaceScreen(
            controller: controller,
            onConnections: () => connectionsRequested = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hermes administration'));
      await tester.pumpAndSettle();
      expect(find.text('Defaults'), findsOneWidget);
      expect(find.text('Identity'), findsOneWidget);
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle();
      expect(find.text('Providers'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();
      expect(connectionsRequested, isTrue);
      await tester.tap(find.text('Runtime'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates'));
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (find.text('Current version unavailable').evaluate().isNotEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final version = BackendUpdateCheck.fromJson(
        await controller.current!.gateway.read('hermes/update/check'),
      );
      expect(version.currentVersion, isNotNull);
      expect(find.text(version.currentVersion!), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Security audit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
