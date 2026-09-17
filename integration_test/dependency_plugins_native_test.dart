import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wing/core/services/turn_notification_service.dart';

/// Runs on an isolated Android emulator without a Hermes server.
/// Install the debug app and grant POST_NOTIFICATIONS before running this target.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native package metadata and app storage remain available', (
    tester,
  ) async {
    final info = await PackageInfo.fromPlatform();
    expect(info.packageName, 'com.tarkilhk.wing.dev');
    expect(info.version, isNotEmpty);
    expect(int.tryParse(info.buildNumber), greaterThan(0));

    for (final directory in [
      await getTemporaryDirectory(),
      await getApplicationSupportDirectory(),
    ]) {
      final probe = await directory.createTemp('wing-dependency-test-');
      addTearDown(() => probe.delete(recursive: true));
      final file = File('${probe.path}/probe.txt');
      await file.writeAsString('native storage round trip');
      expect(await file.readAsString(), 'native storage round trip');
    }
  });

  testWidgets(
    'native notifications preserve content and cancel only their ID',
    (tester) async {
      final plugin = FlutterLocalNotificationsPlugin();
      final sink = PluginTurnNotificationSink(plugin: plugin);
      const firstId = 170001;
      const secondId = 170002;
      addTearDown(() async {
        await sink.cancel(firstId);
        await sink.cancel(secondId);
      });
      await sink.initialize();
      expect(
        await sink.notificationsEnabled(),
        isTrue,
        reason: 'Grant POST_NOTIFICATIONS to com.tarkilhk.wing.dev first.',
      );
      for (final id in [firstId, secondId]) {
        await sink.show(
          TurnNotification(
            id: id,
            title: 'Dependency validation $id',
            body: 'Native notification $id',
            payload: 'synthetic-chat-$id',
            channel: TurnNotificationService.turnChannel,
          ),
        );
      }

      Future<List<ActiveNotification>> waitForIds(Set<int> expected) async {
        for (var attempt = 0; attempt < 50; attempt++) {
          final active = (await plugin.getActiveNotifications())
              .where((alert) => [firstId, secondId].contains(alert.id))
              .toList();
          if (active.map((alert) => alert.id).toSet().containsAll(expected) &&
              active.length == expected.length) {
            return active;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('Android notifications did not settle to IDs $expected');
      }

      final active = await waitForIds({firstId, secondId});
      for (final alert in active) {
        expect(alert.title, 'Dependency validation ${alert.id}');
        expect(alert.body, 'Native notification ${alert.id}');
      }
      await sink.cancel(firstId);
      await waitForIds({secondId});
      await sink.cancel(secondId);
      expect(await waitForIds({}), isEmpty);
    },
  );
}
