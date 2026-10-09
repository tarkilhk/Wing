import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/health_alert.dart';
import 'package:wing/core/models/health_alert_evaluator.dart';
import 'package:wing/core/models/host_thresholds.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/services/health_alert_settings_session.dart';
import 'package:wing/core/services/health_alert_settings_store.dart';
import 'package:wing/core/services/health_alerts_session.dart';
import 'package:wing/core/services/host_resources_session.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'support/host_resources_fixture.dart';

class _HeldStore extends HealthAlertSettingsStore {
  _HeldStore(super.preferences);
  final gate = Completer<void>();
  bool fail = false;
  int writes = 0;
  @override
  Future<void> write(HealthAlertSettings settings) async {
    writes++;
    await gate.future;
    if (fail) throw StateError('disk unavailable');
    await super.write(settings);
  }
}

void main() {
  final start = DateTime.utc(2026, 10, 9);
  final ram = HostMetric.memoryUsedPercent;
  late HealthAlertEvaluator evaluator;
  late HealthAlertRule rule;
  setUp(() {
    evaluator = HealthAlertEvaluator(
      connectionIdentity: 'exact-endpoint',
      connectionLabel: 'Home',
    );
    rule = HealthAlertRule(
      enabled: true,
      warnAbove: 90,
      clearBelow: 85,
      minutes: 2,
    );
  });
  void sample(int seconds, double? value, {bool critical = false}) =>
      evaluator.host(
        metric: ram,
        rule: rule,
        now: start.add(Duration(seconds: seconds)),
        sampledAt: value == null && !critical
            ? null
            : start.add(Duration(seconds: seconds)),
        value: value,
        critical: critical,
      );
  void period(int first, int last, double value) {
    for (var i = first; i <= last; i += 15) {
      sample(i, value);
    }
  }

  test(
    'requires sustained fresh samples, ignores duplicate receipts, and uses strict limits',
    () {
      period(0, 120, 90);
      expect(evaluator.alerts, isEmpty);
      sample(135, 93);
      for (var i = 0; i < 20; i++) {
        sample(135, 93);
      }
      expect(evaluator.alerts, isEmpty);
      period(150, 255, 93);
      expect(evaluator.alerts.single.severity, HealthAlertSeverity.warning);
      period(270, 390, 85);
      expect(evaluator.alerts, hasLength(1));
      period(405, 525, 84);
      expect(evaluator.alerts, isEmpty);
    },
  );
  test(
    'gaps/unknown break pending periods and never clear a known incident',
    () {
      period(0, 105, 93);
      sample(180, 93);
      expect(evaluator.alerts, isEmpty);
      period(195, 300, 93);
      expect(evaluator.alerts, hasLength(1));
      sample(315, null);
      expect(evaluator.alerts.single.lastKnown, isTrue);
      period(330, 435, 80);
      sample(500, 80);
      expect(evaluator.alerts, hasLength(1));
      period(515, 620, 80);
      expect(evaluator.alerts, isEmpty);
    },
  );
  test(
    'critical pressure bypasses duration and does not require a percentage',
    () {
      sample(0, null, critical: true);
      expect(evaluator.alerts.single.severity, HealthAlertSeverity.critical);
      final id = evaluator.alerts.single.id;
      evaluator.acknowledge(id);
      expect(evaluator.alerts.single.acknowledged, isTrue);
      sample(15, 99, critical: true);
      expect(evaluator.alerts.single.acknowledged, isTrue);
      period(30, 150, 80);
      expect(evaluator.alerts, isEmpty);
      sample(165, 99, critical: true);
      expect(evaluator.alerts.single.acknowledged, isFalse);
    },
  );
  test(
    'escalation starts a new occurrence and snooze preserves current count',
    () {
      period(0, 120, 93);
      final initial = evaluator.alerts.single;
      evaluator.acknowledge(initial.id);
      sample(135, 99, critical: true);
      final escalated = evaluator.alerts.single;
      expect(escalated.occurrence, greaterThan(initial.occurrence));
      expect(escalated.acknowledged, isFalse);
      evaluator.snooze(escalated.id, start.add(const Duration(minutes: 30)));
      expect(evaluator.alerts, hasLength(1));
      expect(evaluator.alerts.single.remindsAt(start), isFalse);
      expect(
        evaluator.alerts.single.remindsAt(
          start.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
    },
  );
  test(
    'profile incidents remain attached to their original scope; unknown is not recovery',
    () {
      for (final name in ['default', 'Research']) {
        evaluator.finding(
          key: 'endpoint:profile:$name:access',
          title: 'Model access',
          detail: 'Expired',
          scope: HealthAlertScope.profile,
          at: start,
          failed: true,
          profileName: name,
        );
      }
      evaluator.finding(
        key: 'endpoint:profile:Research:access',
        title: 'Model access',
        detail: 'Unknown',
        scope: HealthAlertScope.profile,
        at: null,
        failed: null,
        profileName: 'Research',
      );
      expect(evaluator.alerts, hasLength(2));
      expect(
        evaluator.alerts
            .where((a) => a.profileName == 'Research')
            .single
            .lastKnown,
        isTrue,
      );
      evaluator.finding(
        key: 'endpoint:profile:default:access',
        title: 'Model access',
        detail: 'Available',
        scope: HealthAlertScope.profile,
        at: start,
        failed: false,
        profileName: 'default',
      );
      expect(evaluator.alerts.single.profileName, 'Research');
    },
  );
  test(
    'settings have one serialized durable owner; failed save preserves policy',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = _HeldStore(prefs)..fail = true;
      final session = HealthAlertSettingsSession(store);
      final original = session.settings,
          draft = original.copyWith(enabled: false);
      final save = session.save(draft, expected: original);
      expect(session.saving, isTrue);
      expect(session.settings, same(original));
      expect(await session.save(draft, expected: original), isFalse);
      expect(store.writes, 1);
      store.gate.complete();
      expect(await save, isFalse);
      expect(session.settings, same(original));
      expect(session.error, isNotNull);
      store.fail = false;
      expect(await session.save(draft, expected: original), isTrue);
      expect(HealthAlertSettingsStore(prefs).read().enabled, isFalse);
      session.dispose();
    },
  );
  test('stale editor cannot replace another window’s saved policy', () async {
    SharedPreferences.setMockInitialValues({});
    final session = HealthAlertSettingsSession(
      HealthAlertSettingsStore(await SharedPreferences.getInstance()),
    );
    final baseline = session.settings;
    final newer = baseline.copyWith(showNotice: false);
    expect(await session.save(newer, expected: baseline), isTrue);
    expect(
      await session.save(baseline.copyWith(enabled: false), expected: baseline),
      isFalse,
    );
    expect(session.settings, same(newer));
    expect(session.error, contains('another window'));
    session.dispose();
  });
  test('corrupt policy fails closed with a repair path', () async {
    SharedPreferences.setMockInitialValues({
      HealthAlertSettingsStore.key: 'broken',
    });
    final prefs = await SharedPreferences.getInstance();
    final session = HealthAlertSettingsSession(HealthAlertSettingsStore(prefs));
    expect(session.settings.enabled, isFalse);
    expect(session.error, isNotNull);
    expect(
      await session.save(HealthAlertSettings(), expected: session.settings),
      isTrue,
    );
    expect(session.settings.enabled, isTrue);
    session.dispose();
  });
  testWidgets(
    'saved limits immediately retire incidents under the replaced rule',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fixture = HostResourcesFixture();
      fixture.stats['memory']['percent'] = 93.0;
      var now = start;
      final host = HostResourcesSession(fixture.server, now: () => now);
      final health = AdministrationHealth(fixture.server, now: () => now);
      final connection = ServerConnectionStatus('Home');
      final settings = HealthAlertSettingsSession(
        HealthAlertSettingsStore(prefs),
      );
      final session = HealthAlertsSession(
        host: host,
        health: health,
        connection: connection,
        settings: settings,
        now: () => now,
      );
      var publications = 0;
      session.addListener(() => publications++);
      session.setActive(true);
      for (var seconds = 0; seconds <= 120; seconds += 15) {
        now = start.add(Duration(seconds: seconds));
        fixture.pressure = hostPressurePayload(now: now);
        await host.refresh();
      }
      expect(session.alerts.single.severity, HealthAlertSeverity.warning);
      final before = publications;
      await host.refresh();
      expect(publications, before);
      final policy = settings.settings;
      await settings.save(
        policy.copyWith(
          rules: {
            ...policy.rules,
            ram: HealthAlertRule(
              enabled: true,
              warnAbove: 96,
              clearBelow: 85,
              minutes: 2,
            ),
          },
        ),
        expected: policy,
      );
      expect(session.alerts, isEmpty);
      session.dispose();
      host.dispose();
      health.dispose();
      connection.dispose();
      settings.dispose();
      fixture.server.close();
    },
  );
  testWidgets(
    'shared watch pauses; late reads cannot create incidents while inactive',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fixture = HostResourcesFixture();
      var now = start;
      fixture.pressure = hostPressurePayload(now: now);
      fixture.pressure['memory']['pressure'] = 'critical';
      final host = HostResourcesSession(fixture.server, now: () => now);
      final health = AdministrationHealth(fixture.server, now: () => now);
      final connection = ServerConnectionStatus('Home');
      final settings = HealthAlertSettingsSession(
        HealthAlertSettingsStore(prefs),
      );
      final session = HealthAlertsSession(
        host: host,
        health: health,
        connection: connection,
        settings: settings,
        now: () => now,
      );
      expect(fixture.requests, isEmpty);
      fixture.statsGate = Completer();
      session.setActive(true);
      expect(fixture.requests, hasLength(2));
      session.setActive(false);
      fixture.statsGate!.complete();
      await host.refresh();
      expect(session.alerts, isEmpty);
      await tester.pump(const Duration(minutes: 3));
      expect(fixture.requests, hasLength(2));
      now = now.add(const Duration(minutes: 3));
      fixture.pressure = hostPressurePayload(now: now);
      fixture.pressure['memory']['pressure'] = 'critical';
      session.setActive(true);
      await host.refresh();
      expect(session.alerts.single.severity, HealthAlertSeverity.critical);
      fixture.statsError = StateError('stats unavailable');
      await host.refresh();
      expect(session.alerts.single.severity, HealthAlertSeverity.critical);
      session.setActive(false);
      await tester.pump(const Duration(minutes: 1));
      expect(session.alerts.single.lastKnown, isTrue);
      await settings.save(
        settings.settings.copyWith(enabled: false),
        expected: settings.settings,
      );
      expect(session.alerts, isEmpty);
      session.dispose();
      host.dispose();
      health.dispose();
      connection.dispose();
      settings.dispose();
      fixture.server.close();
    },
  );
}
