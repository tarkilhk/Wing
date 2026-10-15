/// Driven by scripts/test_native_process_recovery.py. The same APK executes
/// both phases; Android force-stop, not Dart owner disposal, separates them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/composer_action_button.dart';
import 'package:wing/core/widgets/profile_queued_messages.dart';

import '../test/profile_workspace_controller_test.dart' show Host;

const _runId = String.fromEnvironment('PROCESS_RECOVERY_RUN_ID');
const _text = 'Keep this uncertain submission';
const _draft = 'Keep this newer draft';
const _bytes = 'Attachment survives Android process death.\n';

Future<void> _checkpoint(String phase, Map<String, Object?> evidence) async {
  final destination = File(
    '${Directory.systemTemp.path}/wing-process-recovery.json',
  );
  final temporary = File('${destination.path}.tmp');
  await temporary.writeAsString(
    jsonEncode({'run_id': _runId, 'phase': phase, 'pid': pid, ...evidence}),
    flush: true,
  );
  await temporary.rename(destination.path);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Map<String, Object?>? restoredEvidence;
  unawaited(
    binding.allTestsPassed.future.then((passed) async {
      await _checkpoint(
        passed && restoredEvidence != null ? 'restored' : 'failed',
        restoredEvidence ?? const {},
      );
    }),
  );
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'uncertain outbox and attachment survive Android force-stop',
    (tester) async {
      expect(_runId, isNotEmpty);
      final preferences = await SharedPreferences.getInstance();
      final phaseKey = 'process_recovery_qa.$_runId';
      final identity = 'process-recovery-$_runId';
      final savedPhase = preferences.getString(phaseKey);
      final restarting = savedPhase != null;
      final originalKeys = savedPhase == null
          ? preferences.getKeys()
          : (jsonDecode(savedPhase) as List).cast<String>().toSet();
      final host = Host()
        ..running = false
        ..promptSubmitFails = !restarting;
      final owner = AppPreferences(preferences);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: SavedConnection(
            id: identity,
            label: 'Process recovery',
            host: 'localhost',
            port: 1,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        connectionIdentity: identity,
        preferences: preferences,
        appPreferences: owner,
        gatewayFactory: host.gateway,
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) {
          controller.dispose();
          owner.dispose();
        }
      });
      await controller.initialize();
      expect(controller.error, isNull);
      final key = ProfileSessionKey(controller.current!.scope, 'same');
      final chat = (await controller.openSession(key))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          home: ProfileWorkspaceScreen(
            controller: controller,
            createBotsSession: () => BotsSession((_) async => const []),
          ),
        ),
      );
      Future<void> until(bool Function() condition, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(condition(), isTrue, reason: reason);
        expect(tester.takeException(), isNull);
      }

      final editor = find.byKey(const Key('profile-message-composer'));
      final store = ComposerDraftStore(
        preferences,
        connectionIdentity: identity,
      );
      await until(() => editor.evaluate().isNotEmpty, 'Conversation opens');
      if (!restarting) {
        final source = File(
          '${Directory.systemTemp.path}/process-recovery-$_runId.txt',
        );
        await source.writeAsString(_bytes, flush: true);
        await controller.addAttachments(chat, [
          (path: source.path, name: 'recovery.txt'),
        ]);
        await source.delete();
        await tester.enterText(editor, _text);
        await tester.pump();
        await tester.tap(find.byType(ComposerActionButton));
        await until(
          () =>
              chat.composer.observation.paused &&
              !chat.composer.observation.saving &&
              !chat.composer.observation.draining &&
              chat.composer.observation.queue.any(
                (item) => item.submissionUncertain,
              ),
          'Lost acknowledgement retains the attachment and pauses the outbox',
        );
        await tester.enterText(editor, _draft);
        await tester.pump();
        await chat.composer.admittedWrites;
        final saved = (await store.read(profileName: 'a', sessionId: 'same'))!;
        expect(saved.text, _draft);
        expect(saved.queuedPrompts.single.text, _text);
        expect(saved.queuePaused, isTrue);
        final attachment = saved.queuedPrompts.single.attachments.single;
        expect(await File(attachment.cachedPath).readAsString(), _bytes);
        expect(
          host.calls.where((call) => call.$2 == 'prompt.submit'),
          hasLength(1),
        );
        expect(
          host.calls.where((call) => call.$2 == 'file.attach'),
          hasLength(1),
        );
        expect(
          await preferences.setString(
            phaseKey,
            jsonEncode(originalKeys.toList()),
          ),
          isTrue,
        );
        await _checkpoint('ready_for_stop', {'submissions': 1, 'uploads': 1});
        // No finally/dispose path runs: the driver kills this Android process.
        while (true) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      expect(tester.widget<TextField>(editor).controller!.text, _draft);
      Finder queued() => find.descendant(
        of: find.byType(ProfileQueuedMessages),
        matching: find.text(_text),
      );
      expect(queued().hitTestable(), findsOneWidget);
      expect(find.text('Queue paused'), findsOneWidget);
      expect(
        chat.composer.observation.queue.single.submissionUncertain,
        isTrue,
      );
      final restored = (await store.read(profileName: 'a', sessionId: 'same'))!;
      final attachment = restored.queuedPrompts.single.attachments.single;
      expect(await File(attachment.cachedPath).readAsString(), _bytes);
      // Reopening through the browser must also preserve uncertain admission.
      await tester.tap(find.byTooltip('Back'));
      await until(
        () => find.text('a chat').evaluate().isNotEmpty,
        'Chats opens',
      );
      await tester.tap(find.text('a chat'));
      await until(() => editor.evaluate().isNotEmpty, 'Conversation reopens');
      expect(tester.widget<TextField>(editor).controller!.text, _draft);
      expect(queued().hitTestable(), findsOneWidget);
      expect(find.text('Queue paused'), findsOneWidget);
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      expect(host.calls.where((call) => call.$2 == 'file.attach'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      owner.dispose();
      disposed = true;
      await File(attachment.cachedPath).delete();
      await store.write(
        profileName: 'a',
        sessionId: 'same',
        text: '',
        attachments: const [],
      );
      for (final key in preferences.getKeys().difference(originalKeys)) {
        expect(await preferences.remove(key), isTrue);
      }
      restoredEvidence = {
        'submissions': 0,
        'uploads': 0,
        'draft_restored': true,
        'attachment_restored': true,
        'outbox_paused': true,
      };
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
