import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/app_settings_content.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'profile_notification_coverage_test.dart' show NotificationCoverageHost;
import 'package:wing/core/services/background_monitoring_service.dart';
import 'package:wing/core/widgets/compact_switch.dart';

void main() {
  testWidgets(
    'connected workspace settings expose monitoring and battery controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      PackageInfo.setMockInitialValues(
        appName: 'Wing',
        packageName: 'com.tarkilhk.wing',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      final host = NotificationCoverageHost();
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        connectionIdentity: 'monitoring-settings',
        preferences: preferences,
        gatewayFactory: host.gateway,
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      final state = ValueNotifier(BackgroundMonitoringState.batteryRestricted);
      addTearDown(state.dispose);
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileWorkspaceScreen(
            controller: controller,
            initialDestination: AppDestination.settings,
            enableNotifications: () async {},
            backgroundMonitoringState: state,
            openMonitoringBatterySettings: () async => requests++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final battery = find.text('Allow background activity');
      await tester.scrollUntilVisible(battery, 350);
      await tester.pumpAndSettle();
      expect(find.text('Monitor in background'), findsNothing);
      await tester.tap(battery);
      await tester.pumpAndSettle();
      expect(requests, 1);
      state.value = BackgroundMonitoringState.disabled;
      await tester.pumpAndSettle();
      expect(find.text('Notifications may be delayed.'), findsNothing);
      state.value = BackgroundMonitoringState.permissionRequired;
      await tester.pumpAndSettle();
      expect(find.text('Enable notifications'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'monitoring controls work at 320dp and 200% text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        PackageInfo.setMockInitialValues(
          appName: 'Wing',
          packageName: 'com.tarkilhk.wing',
          version: '1',
          buildNumber: '1',
          buildSignature: '',
        );
        final state = ValueNotifier(
          BackgroundMonitoringState.batteryRestricted,
        );
        addTearDown(state.dispose);
        var changes = 0;
        var batteryRequests = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: AppSettingsContent(
                preferences: preferences,
                onChanged: () => changes++,
                enableNotifications: () async {},
                backgroundMonitoringState: state,
                openMonitoringBatterySettings: () async => batteryRequests++,
              ),
            ),
          ),
        );
        final battery = find.text('Allow background activity');
        await tester.scrollUntilVisible(battery, 250);
        await tester.pumpAndSettle();
        await tester.tap(battery);
        await tester.pumpAndSettle();
        expect(batteryRequests, 1);
        expect(find.text('Monitor in background'), findsNothing);
        expect(find.byType(CompactSwitchListTile), findsNWidgets(3));
        expect(changes, 0);
        state.value = BackgroundMonitoringState.active;
        await tester.pumpAndSettle();
        expect(find.text('Allow background activity'), findsNothing);
        expect(find.text('Notifications may be delayed.'), findsNothing);
        expect(find.textContaining('monitoring'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
