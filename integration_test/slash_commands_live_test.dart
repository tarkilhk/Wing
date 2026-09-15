import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/main.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_selection_store.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/widgets/slash_command_suggestions.dart';

/// Real emulator + Prestige's installed gateway. No model prompts are submitted.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = int.fromEnvironment('HERMES_TEST_PORT');
  testWidgets(
    'live mobile command discovery, completion and read-only execution',
    (tester) async {
      expect(port, greaterThan(0), reason: 'Supply the local QA gateway port');
      final preferences = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(preferences);
      final connection = SavedConnection(
        id: 'prestige-local-slash-qa',
        label: 'Prestige local QA',
        host: '127.0.0.1',
        port: port,
        dashboardPortOverride: port,
        apiKey: '',
      );
      await manager.importConnections([connection], replaceExisting: false);
      await preferences.setString('last_connection_id', connection.id);
      await ProfileSelectionStore(preferences).write(
        await ProfileConnectionIdentity().resolve(connection),
        'android-qa-a',
      );
      await tester.pumpWidget(WingApp(connManager: manager));

      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(condition(), isTrue);
      }

      await until(
        () => find.byType(ProfileWorkspaceScreen).evaluate().isNotEmpty,
      );
      final controller = tester
          .widget<ProfileWorkspaceScreen>(find.byType(ProfileWorkspaceScreen))
          .controller;
      await until(() => controller.current != null || controller.error != null);
      expect(controller.error, isNull, reason: 'Initial profile discovery');
      debugPrint('slash-qa: connected to the real gateway');
      expect(controller.current!.scope.profileName, 'android-qa-a');
      await controller.createChat();
      await tester.pump();
      final chat = controller.current!.chat!;
      final catalog = await controller.commandCatalog(chat);
      expect(catalog.commands, isNotEmpty);

      await binding.convertFlutterSurfaceToImage();
      final directory = await getExternalStorageDirectory();
      Future<void> screenshot(String name) async {
        await tester.pumpAndSettle();
        final bytes = await binding.takeScreenshot(name);
        await File('${directory!.path}/$name.png').writeAsBytes(bytes);
      }

      final composer = find.byKey(const Key('profile-message-composer'));
      await tester.enterText(composer, '/model');
      final modelSuggestion = find.descendant(
        of: find.byType(SlashCommandSuggestions),
        matching: find.text('/model'),
      );
      await until(() => modelSuggestion.evaluate().isNotEmpty);
      expect(find.byType(SlashCommandSuggestions), findsOneWidget);
      await screenshot('slash-command-picker');
      debugPrint('slash-qa: command picker screenshot saved');
      await tester.tap(modelSuggestion.first);
      await tester.pump();
      expect(chat.draft, '/model ');
      await tester.tap(find.byTooltip('Send'));
      await until(() => !chat.commandRunning);
      expect(chat.error, isNull, reason: '/model execution');
      expect(chat.commandOutput.join('\n'), contains('Current model:'));
      expect(chat.busy, isFalse);
      await screenshot('slash-command-result');
      debugPrint('slash-qa: /model result screenshot saved');

      // Dispatch temporarily disables the field. Tap it to reconnect Android's
      // text input before typing the next command, as a user would.
      await tester.tap(composer);
      await tester.pump();
      await tester.enterText(composer, '/status');
      expect(
        chat.draft,
        '/status',
        reason: 'Second command reaches chat draft',
      );
      await tester.pump();
      expect(chat.draft, '/status', reason: 'Second command survives rebuild');
      final outputCount = chat.commandOutput.length;
      await tester.tap(find.byTooltip('Send'));
      expect(
        chat.commandRunning,
        isTrue,
        reason: 'Second Send starts dispatch',
      );
      await until(
        () => !chat.commandRunning && chat.commandOutput.length > outputCount,
      );
      expect(chat.error, isNull, reason: '/status execution');
      expect(chat.commandOutput.last, isNot('Status unavailable.'));

      // Expansion is a read-only RPC; verify the actual installed skill body is
      // returned without submitting it to a model or executing its instructions.
      final skills = catalog.commands
          .where((c) => c.category == 'Skills')
          .toList();
      expect(
        skills,
        isNotEmpty,
        reason: 'QA profile must expose installed skills',
      );
      final result = await controller.current!.gateway
          .call('command.dispatch', {
            'session_id': chat.runtimeId,
            'name': skills.first.text.substring(1),
            'arg': 'Android mobile command contract check',
          });
      expect(result['type'], 'skill');
      expect(result['message'], isA<String>());
      expect((result['message'] as String).isNotEmpty, isTrue);
      await screenshot('slash-command-status');
      debugPrint('slash-qa: screenshots saved in ${directory!.path}');
      const holdSeconds = int.fromEnvironment('HERMES_SCREENSHOT_HOLD_SECONDS');
      if (holdSeconds > 0) {
        await Future<void>.delayed(Duration(seconds: holdSeconds));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
