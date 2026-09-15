import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/background_monitoring_service.dart';
import 'package:wing/core/services/turn_notification_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late BackgroundMonitoringService service;
  late List<String> calls;
  late bool activeChats;
  late bool allowed;
  late bool unrestricted;
  late bool running;
  Completer<void>? startGate;
  Object? failure;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    calls = [];
    activeChats = allowed = unrestricted = running = true;
    startGate = null;
    failure = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BackgroundMonitoringService.channel,
      (call) async {
        calls.add(call.method);
        if (failure != null) throw failure!;
        if (call.method == 'start') {
          await startGate?.future;
          return {'running': running, 'batteryUnrestricted': unrestricted};
        }
        return null;
      },
    );
    service = BackgroundMonitoringService(
      preferences: preferences,
      hasActiveChats: () => activeChats,
      notificationsEnabled: () async => allowed,
      supported: true,
    );
  });

  tearDown(() {
    service.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      BackgroundMonitoringService.channel,
      null,
    );
  });

  test(
    'idle by default, starts with work, and stops after the last chat',
    () async {
      activeChats = false;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.idle);
      activeChats = true;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.active);
      activeChats = false;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.idle);
      expect(calls, ['stop', 'start', 'stop']);
    },
  );

  test('starts direct monitoring without Firebase configuration', () async {
    await service.sync();
    expect(calls, ['start']);
    expect(service.state.value, BackgroundMonitoringState.active);
  });

  test(
    'disabling while start is in flight finishes with the service stopped',
    () async {
      startGate = Completer<void>();
      final first = service.sync();
      await Future<void>.delayed(Duration.zero);
      await preferences.setBool(completionNotificationsKey, false);
      await preferences.setBool(attentionNotificationsKey, false);
      final second = service.sync();
      startGate!.complete();
      await Future.wait([first, second]);
      expect(calls, ['start', 'stop']);
      expect(service.state.value, BackgroundMonitoringState.disabled);
    },
  );

  test(
    'permission revocation and last active chat finishing stop monitoring',
    () async {
      await service.sync();
      allowed = false;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.permissionRequired);
      allowed = true;
      activeChats = false;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.idle);
      expect(calls, ['start', 'stop', 'stop']);
    },
  );

  test('both alert categories off stops monitoring', () async {
    await preferences.setBool(completionNotificationsKey, false);
    await service.sync();
    expect(calls, ['start']);
    await preferences.setBool(attentionNotificationsKey, false);
    await service.sync();
    expect(calls, ['start', 'stop']);
    expect(service.state.value, BackgroundMonitoringState.disabled);
  });

  test(
    'reports battery restrictions separately from a running service',
    () async {
      unrestricted = false;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.batteryRestricted);
      await service.openBatterySettings();
      expect(calls, ['start', 'openBatterySettings']);
      unrestricted = true;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.active);
    },
  );

  test(
    'a background start deferred by Android never claims monitoring is active',
    () async {
      running = false;
      await service.sync();
      expect(service.state.value, BackgroundMonitoringState.waitingForApp);
    },
  );

  test('native startup failure can be retried', () async {
    failure = PlatformException(code: 'monitoring_start_failed');
    await service.sync();
    expect(service.state.value, BackgroundMonitoringState.failed);
    failure = null;
    await service.sync();
    expect(service.state.value, BackgroundMonitoringState.active);
  });

  test(
    'obsolete monitoring off preference cannot prevent automatic startup',
    () async {
      await preferences.setBool('background_monitoring_enabled', false);
      await service.sync();
      expect(calls, ['start']);
      expect(service.state.value, BackgroundMonitoringState.active);
    },
  );

  test(
    'enabling either alert category automatically restarts monitoring',
    () async {
      await preferences.setBool(completionNotificationsKey, false);
      await preferences.setBool(attentionNotificationsKey, false);
      await service.sync();
      await preferences.setBool(attentionNotificationsKey, true);
      await service.sync();
      expect(calls, ['stop', 'start']);
      expect(service.state.value, BackgroundMonitoringState.active);
    },
  );
}
