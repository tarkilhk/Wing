import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/app_preferences.dart';
import 'package:wing/core/models/health_alert.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/screens/administration/admin_usage_dashboard.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/health_alert_settings_store.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_workspace_registry.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/main.dart';

import '../test/support/administration_design_fixture.dart';
import '../test/support/host_resources_fixture.dart';
import '../test/support/profile_browser_fixture.dart';

class _Credentials implements CredentialStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Only the transport is synthetic. The app, registry, alert owners, routes,
/// Android viewport and native keyboard are the shipped implementations.
class _Observations extends ProfileBrowserFixture {
  _Observations() {
    liveSessions['personal'] = [
      {
        'id': 'native-live-runtime',
        'session_key': 'native-live-durable',
        'status': 'working',
      },
    ];
  }

  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    ...super.sessions(profile),
    if (profile == 'personal')
      {
        'id': 'native-live-durable',
        'profile': 'personal',
        'title': 'Active native QA conversation',
        'last_active': now - 30,
      },
  ];

  @override
  List<Map<String, dynamic>> searchRows(String profile, String query) =>
      query == 'native-live-durable' && profile == 'personal'
      ? [
          {
            'session_id': 'native-live-compression-tip',
            'profile': 'personal',
            'title': 'Active native QA conversation',
          },
        ]
      : super.searchRows(profile, query);
  final administration = AdministrationDesignFixture();
  final stats = hostStatsPayload();
  bool memoryCritical = false, diskCritical = false;
  bool analyticsUnavailable = false;
  int hostReads = 0;
  final analyticsReads = <String>[];
  late ProfileWorkspaceController owner;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final browser = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: browser.discover,
      rpc: (method, params) async {
        final response = await browser.call(method, params);
        if (method == 'session.resume' &&
            params['session_id'] == 'native-live-durable') {
          return {...response, 'running': true};
        }
        return response;
      },
      get: (path, query) => path.startsWith('sessions')
          ? browser.read(path, query)
          : administration.send('GET', path, query, null),
    );
  }

  AdministrationRepository server(
    SavedConnection connection,
    String identity,
  ) => AdministrationRepository(
    connectionId: connection.id,
    connectionIdentity: identity,
    connectionLabel: connection.label,
    gateway: (name) => gateway(
      WorkspaceScope(
        connectionId: connection.id,
        connectionIdentity: identity,
        profileName: name,
      ),
    ),
    settingsWrite: (_, _, _, _) async => throw StateError('Unexpected write'),
    ownedMutation: (_, _, _, _, _, _) async =>
        throw StateError('Unexpected mutation'),
    request: (method, path, query, body) async {
      if (method == 'GET' && path.startsWith('analytics/')) {
        analyticsReads.add(path);
        if (analyticsUnavailable) {
          throw DashboardHttpException(503, path);
        }
      }
      if (method == 'GET' && path == 'system/stats') {
        hostReads++;
        return stats;
      }
      if (method == 'GET' && path == 'status') {
        final value = hostPressurePayload();
        value['memory']['pressure'] = memoryCritical ? 'critical' : 'ok';
        value['disk']['pressure'] = diskCritical ? 'critical' : 'ok';
        return value;
      }
      return administration.send(method, path, query, body);
    },
  );
}

/// An optional host capture driver takes an actual Android screencap and releases
/// this checkpoint. Bounded, uniquely named checkpoints cannot reuse old captures.
Future<void> _capture(String name) async {
  if (!const bool.fromEnvironment('ALERT_NATIVE_CAPTURE')) return;
  final cache = Directory.systemTemp.path;
  final receipt = File('$cache/wing-health-alert-capture-ack');
  final token = '$name-${DateTime.now().microsecondsSinceEpoch}';
  await File(
    '$cache/wing-health-alert-stage.json',
  ).writeAsString(jsonEncode({'token': token, 'name': name}));
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(end)) {
    if (await receipt.exists() && await receipt.readAsString() == token) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Android screenshot driver did not capture $name');
}

/// Ongoing work intentionally animates. Waiting for every frame to stop would
/// never finish; allow route transitions to finish, then assert the visible state.
Future<void> _settleScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (target.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(target, findsWidgets);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Keep the native frame clock running through capture and I/O waits. Working
  // rows animate continuously, so route checks use bounded pumps, not settling.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const large = bool.fromEnvironment('ALERT_EXPECT_LARGE');
  for (final theme in [AppThemePreference.dark, AppThemePreference.light]) {
    testWidgets('Android health alerts ${theme.name}, large=$large', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'notification_permission_requested': true,
        'microphone_permission_requested': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final preferences = AppPreferences(prefs);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await _settleScreen(tester);
        preferences.dispose();
      });
      await preferences.setTheme(theme);
      await preferences.setTextSize(AppTextSizePreference.system);
      await HealthAlertSettingsStore(
        prefs,
      ).write(HealthAlertSettings(server: false, profile: false));
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _Credentials(),
      );
      final connection = await manager.saveConnection(
        'Health UI QA',
        'localhost',
        1,
        '',
      );
      preferences.admitWorkspaceEntry(connection.id);
      await preferences.settleWorkspaceEntry();
      final observations = _Observations();
      final registry = ProfileWorkspaceRegistry(
        identities: ProfileConnectionIdentity(),
        create: (connection, identity) {
          final owner = observations.owner = ProfileWorkspaceController(
            access: manager.accessFor(connection),
            connectionIdentity: identity,
            preferences: prefs,
            appPreferences: preferences,
            gatewayFactory: observations.gateway,
          );
          owner.hostResources(
            repository: observations.server(connection, identity),
          );
          return owner;
        },
      );
      final label = '${theme.name}-${large ? 'large' : 'normal'}';
      await tester.pumpWidget(
        WingApp(
          connManager: manager,
          appPreferences: preferences,
          profileControllers: registry,
        ),
      );
      await _settleScreen(tester);
      await _waitFor(tester, find.text('Chats'));
      final bell = find.byKey(const ValueKey('health-alert-bell'));
      expect(bell, findsNothing);
      expect(find.text('Chats'), findsWidgets);
      final context = tester.element(find.byType(AppBar).last);
      expect(MediaQuery.textScalerOf(context).scale(16) >= 24, large);
      expect(
        MediaQuery.sizeOf(context).width,
        large ? 320 : closeTo(411.43, 1),
      );
      await _capture('$label-chats-healthy');
      await tester.scrollUntilVisible(
        find.text('Improve the conversation list'),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('chat-list-false')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Improve the conversation list'));
      await _settleScreen(tester);
      await _capture('$label-conversation-healthy');

      final rotation = find.descendant(
        of: bell,
        matching: find.byType(Transform),
      );
      var observedRotation = 0.0;
      var observingMotion = true;
      void observeFrame(Duration _) {
        final elements = rotation.evaluate();
        if (elements.length == 1) {
          final widget = elements.single.widget;
          if (widget is Transform) {
            final angle = widget.transform.storage[1].abs();
            if (angle > observedRotation) observedRotation = angle;
          }
        }
        if (observingMotion) binding.addPostFrameCallback(observeFrame);
      }

      // Observe rendered native frames from before the incident arrives. A
      // one-shot can finish while asynchronous refresh/capture work is awaited;
      // sampling only after that await can miss motion that was displayed.
      await tester.pump();
      await tester.pump();
      binding.addPostFrameCallback(observeFrame);
      try {
        observations.memoryCritical = true;
        observations.stats['memory']['percent'] = 94.0;
        observations.stats['memory']['used'] =
            (observations.stats['memory']['total'] * .94).round();
        observations.stats['memory']['available'] =
            observations.stats['memory']['total'] -
            observations.stats['memory']['used'];
        await observations.owner.hostResources().refresh();
        await tester.pump();
        expect(bell, findsOneWidget);
        expect(MediaQuery.disableAnimationsOf(tester.element(bell)), isFalse);
        for (var frame = 0; frame < 20 && observedRotation == 0; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(observedRotation, greaterThan(0));
      } finally {
        observingMotion = false;
      }
      expect(find.byType(Dialog), findsNothing);
      final dismissNotice = find.byTooltip('Dismiss health notice');
      expect(dismissNotice, findsOneWidget);
      await _capture('$label-notice');
      // The real transient notice can expire while the host captures Android.
      // Its presence was checked before waiting; the persistent bell remains.
      if (dismissNotice.evaluate().isNotEmpty) {
        await tester.tap(dismissNotice);
      }
      await _settleScreen(tester);
      expect(tester.widget<Transform>(rotation).transform.storage[1], 0);
      await _capture('$label-bell');
      await tester.tap(bell);
      await _settleScreen(tester);
      expect(find.text('Critical memory pressure'), findsOneWidget);
      expect(find.byTooltip('Alert settings'), findsNothing);
      await _capture('$label-alert');
      expect(find.byTooltip('Acknowledge issue'), findsNothing);
      expect(find.byTooltip('Pause reminders for 30 minutes'), findsNothing);
      await tester.tap(find.byTooltip('Open Hermes health'));
      await _settleScreen(tester);
      await _capture('$label-health');
      await tester.tap(
        find.byKey(const ValueKey('health-alert-settings-entry')),
      );
      await _settleScreen(tester);
      await _capture('$label-settings');
      await tester.ensureVisible(find.text('Memory usage'));
      await tester.tap(find.text('Memory usage'));
      await _settleScreen(tester);
      await _capture('$label-rule');
      // Disable native critical alerts independently before editing the Wing
      // warning. Changing warning limits must not retire a native incident.
      observations.memoryCritical = false;
      await observations.owner.hostResources().refresh();
      final nativeMemory = find.widgetWithText(
        SwitchListTile,
        'Native Hermes critical pressure alert (95%)',
      );
      await tester.ensureVisible(nativeMemory);
      await tester.tap(nativeMemory);
      await _settleScreen(tester);
      final fields = find.byType(TextField);
      await tester.ensureVisible(fields.at(1));
      await tester.tap(fields.at(1));
      await tester.enterText(fields.at(1), '96.5');
      await tester.showKeyboard(fields.at(1));
      final keyboardDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (tester.view.viewInsets.bottom == 0 &&
          DateTime.now().isBefore(keyboardDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _settleScreen(tester);
      // Dialog removes inherited insets after applying them to its own padding.
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      expect(find.byTooltip('Close rule editor').hitTestable(), findsOneWidget);
      await _capture('$label-keyboard');
      expect(prefs.getString('wing-health-alert-settings'), contains('96.5'));
      expect(find.byTooltip('Save health alert settings'), findsNothing);
      final nativeMemorySwitch = find.descendant(
        of: nativeMemory,
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(nativeMemorySwitch);
      await tester.tap(nativeMemorySwitch);
      await _settleScreen(tester);
      await tester.tap(find.byTooltip('Close rule editor'));
      await _settleScreen(tester);
      expect(prefs.getString('wing-health-alert-settings'), contains('96.5'));
      expect(bell, findsNothing);
      await tester.pageBack();
      await _settleScreen(tester);
      await tester.pageBack();
      await _settleScreen(tester);
      expect(find.text('Improve the conversation list'), findsWidgets);
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await _settleScreen(tester);
      expect(find.text('Chats'), findsWidgets);

      observations.memoryCritical = true;
      observations.diskCritical = true;
      observations.stats['disk']['percent'] = 97.0;
      observations.stats['disk']['used'] =
          (observations.stats['disk']['total'] * .97).round();
      observations.stats['disk']['free'] =
          observations.stats['disk']['total'] -
          observations.stats['disk']['used'];
      await observations.owner.hostResources().refresh();
      await _settleScreen(tester);
      if (find.byTooltip('Dismiss health notice').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Dismiss health notice'));
      }
      await tester.tap(bell);
      await _settleScreen(tester);
      expect(find.text('Critical disk pressure'), findsOneWidget);
      expect(find.text('Critical memory pressure'), findsNothing);
      await tester.tap(find.byTooltip('Next issue'));
      await _settleScreen(tester);
      expect(find.text('Critical memory pressure'), findsOneWidget);
      expect(find.text('Critical disk pressure'), findsNothing);
      await _capture('$label-multiple-issues');
      await tester.tap(find.byTooltip('Close alerts'));
      await _settleScreen(tester);
      final chatsCenter = tester.getCenter(find.text('Chats').first).dy;
      for (final destination in [
        AppDestination.activity,
        AppDestination.settings,
        AppDestination.health,
      ]) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await _settleScreen(tester);
        final row = find.byKey(ValueKey('nav-${destination.name}'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await _settleScreen(tester);
        expect(bell, findsOneWidget);
        final title = find.descendant(
          of: find.byType(AppBar),
          matching: find.text(destination.label),
        );
        if (!large) {
          expect(tester.getCenter(title).dy, closeTo(chatsCenter, .01));
        }
        if (destination == AppDestination.activity) {
          await observations.owner.refreshActivity();
          await _settleScreen(tester);
          expect(find.text('Active native QA conversation'), findsOneWidget);
          expect(
            find.textContaining('profile could not be verified'),
            findsNothing,
          );
        }
        await _capture('$label-${destination.name}-header');
        expect(tester.takeException(), isNull);
      }
      expect(observations.hostReads, greaterThan(0));
      observations.analyticsUnavailable = true;
      await tester.tap(find.byTooltip('Open navigation menu'));
      await _settleScreen(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('nav-analytics')));
      await tester.tap(find.byKey(const ValueKey('nav-analytics')));
      await _settleScreen(tester);
      await _waitFor(
        tester,
        find.textContaining('Could not load model totals.'),
      );
      expect(
        find.textContaining('Could not load model totals.'),
        findsOneWidget,
      );
      expect(find.text('Unavailable'), findsWidgets);
      await _capture('$label-analytics-unavailable');

      observations.analyticsUnavailable = false;
      final refresh = find.widgetWithText(TextButton, 'Refresh');
      final analyticsScroll = find
          .descendant(
            of: find.byType(UsageDashboard),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        refresh,
        250,
        scrollable: analyticsScroll,
      );
      await tester.tap(refresh);
      await _settleScreen(tester);
      await tester.scrollUntilVisible(
        find.text('639K'),
        -250,
        scrollable: analyticsScroll,
      );
      expect(find.textContaining('Could not load model totals.'), findsNothing);
      expect(find.text('Unavailable'), findsNothing);
      expect(find.text('639K'), findsOneWidget);
      expect(
        observations.analyticsReads
            .where((p) => p == 'analytics/models')
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(
        observations.analyticsReads.where((p) => p == 'analytics/usage').length,
        greaterThanOrEqualTo(4),
      );
      expect(bell, findsOneWidget);
      await _capture('$label-analytics-recovered');
      expect(tester.takeException(), isNull);
    });
  }
}
