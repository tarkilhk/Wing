import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/config_backup.dart';
import 'package:wing/core/services/config_backup_io.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/compact_switch.dart';
import 'package:wing/main.dart';

// Run only on a disposable emulator. This uses real Android preferences,
// Keystore, sharing and document picking. When backup-qa-stage in the app's
// external files directory says share-*, save the shared JSON to Downloads.
// At pick-*, select that file in Android's document picker. A host UI driver
// can perform these native steps; Flutter's tester cannot tap other apps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CONFIG_BACKUP_NATIVE');
  if (enabled) SharedPreferences.setPrefix('backup_qa.');
  const expected = <String, Object>{
    'theme_mode': 'dark',
    'workspace_accent_v1': 'iris',
    'app_text_size_preference': 'large',
    'composer_running_action': 'queue',
    'completion_notifications': false,
    'attention_notifications': true,
    'notification_message_previews': false,
    'voice.input': 'local',
    'voice.output': 'hermes',
    'voice.android_language': 'en-US',
    'voice.android_voice': 'en-us-x-iom-local',
    'voice.android_rate': '1.2',
  };
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'wing_backup_qa'),
  );

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(done(), isTrue, reason: 'Native backup/restore step timed out.');
    await tester.pumpAndSettle();
  }

  Future<void> navigate(WidgetTester tester, String destination) async {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('nav-$destination')));
    await tester.pumpAndSettle();
  }

  for (final encrypted in [false, true]) {
    testWidgets(
      'native ${encrypted ? 'encrypted replace' : 'plain merge'} backup round trip',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await storage.deleteAll();
        final manager = await ConnectionManager.create(
          prefs,
          credentialStore: FlutterSecureCredentialStore(storage: storage),
        );
        for (final entry in expected.entries) {
          switch (entry.value) {
            case final String value:
              await prefs.setString(entry.key, value);
            case final bool value:
              await prefs.setBool(entry.key, value);
            case final double value:
              await prefs.setDouble(entry.key, value);
          }
        }
        await prefs.setBool('notification_permission_requested', true);
        final saved = await manager.saveConnection(
          'Backup QA instance',
          'https://backup-qa.invalid',
          8642,
          'qa-api-key',
          icon: ConnectionIcon.rocket,
          dashboardUsername: 'qa-user',
          dashboardPassword: 'qa-password',
          gatewayHeaders: {'X-QA': 'qa-header'},
        );
        final stage = File(
          '${(await getExternalStorageDirectory())!.path}/backup-qa-stage',
        );
        final label = encrypted ? 'encrypted' : 'plain';
        final passphrase = encrypted ? 'emulator-backup-passphrase' : '';
        final home = GlobalKey<HomeScreenState>();
        Future<void> show() async {
          await tester.pumpWidget(
            StatefulBuilder(
              builder: (context, rebuild) => MaterialApp(
                themeMode: WingApp.getThemeMode(prefs),
                theme: profileWorkspaceTheme(
                  wingTheme(Brightness.light),
                  accent: WorkspaceAccent.fromName(
                    prefs.getString(WorkspaceAccent.preferenceKey),
                  ),
                ),
                darkTheme: profileWorkspaceTheme(
                  wingTheme(Brightness.dark),
                  accent: WorkspaceAccent.fromName(
                    prefs.getString(WorkspaceAccent.preferenceKey),
                  ),
                ),
                home: HomeScreen(
                  key: home,
                  connManager: manager,
                  pickBackupFile: () async {
                    final contents = await ConfigBackupIo(
                      connectionManager: manager,
                    ).pickBackupFile();
                    expect(contents, isNotNull);
                    expect(
                      jsonDecode(contents!)['format'],
                      encrypted ? 'wing-config-encrypted' : 'wing-config',
                      reason:
                          'Select the backup exported in this test iteration.',
                    );
                    return contents;
                  },
                  enableProfileNotifications: () async {},
                  onPreferencesChanged: () => rebuild(() {}),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show();
        await navigate(tester, 'settings');
        await tester.tap(find.byTooltip('Backup configuration'));
        await tester.pumpAndSettle();
        if (encrypted) {
          await tester.enterText(
            find.byKey(const Key('export_passphrase_field')),
            passphrase,
          );
          await tester.enterText(
            find.byKey(const Key('export_passphrase_confirm_field')),
            passphrase,
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await stage.writeAsString('share-$label', flush: true);
        await tester.tap(find.byKey(const Key('export_confirm_button')));
        await waitFor(
          tester,
          () => find.textContaining('Backup exported').evaluate().isNotEmpty,
        );
        final cache = await getTemporaryDirectory();
        final exported =
            cache
                .listSync()
                .whereType<File>()
                .where(
                  (file) =>
                      file.uri.pathSegments.last.startsWith('wing-config-'),
                )
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        final contents = await exported.last.readAsString();
        final decoded = await ConfigBackupCodec.decode(
          contents,
          passphrase: passphrase,
        );
        expect(decoded.preferences, expected);
        expect(decoded.connections.single.apiKey, 'qa-api-key');
        if (encrypted) expect(contents, isNot(contains('qa-api-key')));

        // Replace saved settings and remove the original to prove actual
        // restoration, including overwriting true and false preference values.
        await manager.deleteConnection(saved.id);
        await manager.saveConnection(
          'Local only',
          'local.invalid',
          8642,
          'local',
        );
        await prefs.setString('theme_mode', 'light');
        await prefs.setString('workspace_accent_v1', 'coral');
        await prefs.setString('composer_running_action', 'stop');
        await prefs.setBool('completion_notifications', true);
        await prefs.setBool('attention_notifications', false);
        await prefs.setBool('notification_message_previews', true);
        await prefs.setString('app_text_size_preference', 'default');
        // Re-enter settings with the changed values cached in its controls.
        await navigate(tester, 'connections');
        home.currentState!.refreshConnections();
        await show();
        await navigate(tester, 'settings');
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Coral'))
              .selected,
          isTrue,
        );

        Future<void> restore(String attempt, String password) async {
          await stage.writeAsString('pick-$label$attempt', flush: true);
          await tester.tap(find.byTooltip('Restore configuration'));
          await waitFor(
            tester,
            () => find
                .byKey(const Key('import_passphrase_field'))
                .evaluate()
                .isNotEmpty,
          );
          await tester.enterText(
            find.byKey(const Key('import_passphrase_field')),
            password,
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          if (encrypted) {
            await tester.tap(find.byKey(const Key('import_mode_replace')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(const Key('import_confirm_button')));
        }

        if (encrypted) {
          await restore('-wrong', 'wrong-passphrase');
          await waitFor(
            tester,
            () => find.textContaining('Wrong passphrase').evaluate().isNotEmpty,
          );
          expect(manager.getConnections().single.label, 'Local only');
          expect(prefs.getString('workspace_accent_v1'), 'coral');
        }
        await restore('', passphrase);
        await waitFor(
          tester,
          () => find.textContaining('settings restored').evaluate().isNotEmpty,
        );
        await prefs.reload();
        for (final entry in expected.entries) {
          expect(prefs.get(entry.key), entry.value, reason: entry.key);
        }
        final reopened = await ConnectionManager.create(
          prefs,
          credentialStore: FlutterSecureCredentialStore(storage: storage),
        );
        final connections = await reopened.loadConnectionsWithSecrets();
        expect(connections.length, encrypted ? 1 : 2);
        final restored = connections.singleWhere((c) => c.id == saved.id);
        expect(restored.apiKey, 'qa-api-key');
        expect(restored.dashboardPassword, 'qa-password');
        expect(restored.gatewayHeaders, {'X-QA': 'qa-header'});
        expect(restored.icon, ConnectionIcon.rocket);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Iris'))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Queue'))
              .selected,
          isTrue,
        );
        expect(
          Theme.of(tester.element(find.byType(HomeScreen))).brightness,
          Brightness.dark,
        );
        for (final entry in {
          'Completed work': false,
          'Needs attention': true,
          'Show message previews': false,
        }.entries) {
          expect(
            tester
                .widget<CompactSwitchListTile>(
                  find.widgetWithText(CompactSwitchListTile, entry.key),
                )
                .value,
            entry.value,
          );
        }
        expect(tester.takeException(), isNull);
        await stage.writeAsString('done-$label', flush: true);
      },
      skip: !enabled,
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
