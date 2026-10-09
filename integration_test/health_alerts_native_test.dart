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
  final administration = AdministrationDesignFixture();
  final stats = hostStatsPayload();
  bool memoryCritical = false, diskCritical = false;
  late ProfileWorkspaceController owner;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final browser = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: browser.discover,
      rpc: browser.call,
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
      if (method == 'GET' && path == 'system/stats') return stats;
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
        await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await _capture('$label-conversation-healthy');

      observations.memoryCritical = true;
      observations.stats['memory']['percent'] = 94.0;
      observations.stats['memory']['used'] =
          (observations.stats['memory']['total'] * .94).round();
      observations.stats['memory']['available'] =
          observations.stats['memory']['total'] -
          observations.stats['memory']['used'];
      await observations.owner.hostResources().refresh();
      // The first native frame establishes the ticker's start timestamp.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(bell, findsOneWidget);
      expect(MediaQuery.disableAnimationsOf(tester.element(bell)), isFalse);
      final rotation = find.descendant(
        of: bell,
        matching: find.byType(Transform),
      );
      expect(
        tester.widget<Transform>(rotation).transform.storage[1].abs(),
        greaterThan(0),
      );
      expect(find.byType(Dialog), findsNothing);
      await _capture('$label-notice');
      await tester.tap(find.byTooltip('Dismiss health notice'));
      await tester.pumpAndSettle();
      expect(tester.widget<Transform>(rotation).transform.storage[1], 0);
      await _capture('$label-bell');
      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.text('Critical memory pressure'), findsOneWidget);
      expect(find.byTooltip('Alert settings'), findsNothing);
      await _capture('$label-alert');
      await tester.tap(find.byTooltip('Pause reminders for 30 minutes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reminders paused'), findsOneWidget);
      await tester.tap(find.byTooltip('Open Hermes health'));
      await tester.pumpAndSettle();
      await _capture('$label-health');
      await tester.tap(
        find.byKey(const ValueKey('health-alert-settings-entry')),
      );
      await tester.pumpAndSettle();
      await _capture('$label-settings');
      await tester.ensureVisible(find.text('Memory usage'));
      await tester.tap(find.text('Memory usage'));
      await tester.pumpAndSettle();
      await _capture('$label-rule');
      final fields = find.byType(TextField);
      await tester.tap(fields.at(0));
      await tester.enterText(fields.at(0), '96.5');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      // Dialog removes inherited insets after applying them to its own padding.
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      expect(
        find.byTooltip('Apply this rule to the settings draft').hitTestable(),
        findsOneWidget,
      );
      await _capture('$label-keyboard');
      await tester.tap(find.byTooltip('Apply this rule to the settings draft'));
      await tester.pumpAndSettle();
      observations.memoryCritical = false;
      await observations.owner.hostResources().refresh();
      await tester.tap(find.byTooltip('Save health alert settings'));
      await tester.pumpAndSettle();
      expect(prefs.getString('wing-health-alert-settings'), contains('96.5'));
      expect(bell, findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Improve the conversation list'), findsWidgets);
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      if (find.byTooltip('Dismiss health notice').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Dismiss health notice'));
      }
      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.text('Critical disk pressure'), findsOneWidget);
      expect(find.text('Critical memory pressure'), findsNothing);
      await tester.tap(find.byTooltip('Next issue'));
      await tester.pumpAndSettle();
      expect(find.text('Critical memory pressure'), findsOneWidget);
      expect(find.text('Critical disk pressure'), findsNothing);
      await tester.tap(find.byTooltip('Acknowledge issue'));
      await tester.pumpAndSettle();
      await _capture('$label-multiple-issues');
      await tester.tap(find.byTooltip('Close alerts'));
      await tester.pumpAndSettle();
      final chatsCenter = tester.getCenter(find.text('Chats').first).dy;
      for (final destination in [
        AppDestination.activity,
        AppDestination.settings,
        AppDestination.health,
      ]) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final row = find.byKey(ValueKey('nav-${destination.name}'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(bell, findsOneWidget);
        final title = find.descendant(
          of: find.byType(AppBar),
          matching: find.text(destination.label),
        );
        if (!large) {
          expect(tester.getCenter(title).dy, closeTo(chatsCenter, .01));
        }
        await _capture('$label-${destination.name}-header');
        expect(tester.takeException(), isNull);
      }
    });
  }
}
