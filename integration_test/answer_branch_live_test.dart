import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

/// Real Android UI and local gateway. One short Luna turn in a disposable chat.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = int.fromEnvironment('HERMES_TEST_PORT');
  testWidgets(
    'fork buttons copy exact boundaries and continue independently',
    (tester) async {
      expect(port, greaterThan(0));
      SharedPreferences.setMockInitialValues({});
      final connection = SavedConnection(
        id: 'fork-device-qa',
        label: 'Fork QA',
        host: '127.0.0.1',
        port: port,
        dashboardPortOverride: port,
        apiKey: '',
      );
      final controller = ProfileWorkspaceController(
        connectionIdentity: 'fork-qa-settings',
        connection: connection,
        preferences: await SharedPreferences.getInstance(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.switchProfile('android-qa-a');
      expect(controller.error, isNull);
      final resource = controller.current!;
      final parents = await resource.gateway.sessions();
      expect(parents.rows, isNotEmpty);
      final seed = await resource.gateway.call('session.create', {
        'parent_session_id': parents.rows.first['id'],
        'source': 'desktop',
        'title': 'Android fork device QA',
        'messages': [
          {
            'role': 'user',
            'content': 'Remember my test token JADE-42. Reply Saved.',
          },
          {'role': 'assistant', 'content': 'Saved.'},
          {'role': 'user', 'content': '[System: model changed for QA]'},
          {'role': 'user', 'content': 'What is my test token?'},
          {'role': 'assistant', 'content': 'JADE-42'},
          {'role': 'user', 'content': 'Change my test token to AMBER-99.'},
          {'role': 'assistant', 'content': 'Your token is now AMBER-99.'},
        ],
      });
      // A seeded session may still be finishing its asynchronous agent startup.
      for (var attempt = 0; attempt < 30; attempt++) {
        final result = await resource.gateway.call('session.resume', {
          'session_id': seed['stored_session_id'],
        });
        if (result['info']?['profile_name'] == resource.scope.profileName) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await controller.openSession(
        ProfileSessionKey(resource.scope, seed['stored_session_id'] as String),
      );
      final source = resource.chat!;
      final original = jsonEncode(
        await resource.gateway.fullHistory(source.runtimeId),
      );
      final expected = source.messages
          .where((m) => !isHiddenAnswerMessage(m))
          .map(answerMessageText)
          .toList();
      expect(expected.length, 6);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await binding.convertFlutterSurfaceToImage();
      final directory = await getExternalStorageDirectory();
      Future<void> screenshot(String name) async {
        await tester.pumpAndSettle();
        final bytes = await binding.takeScreenshot(name);
        await File('${directory!.path}/$name.png').writeAsBytes(bytes);
      }

      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(minutes: 2));
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(condition(), isTrue);
      }

      ProfileChat? middle;
      final children = <String>{};
      for (final answer in [0, 2, 1]) {
        await controller.openSession(source.key);
        await tester.pumpAndSettle();
        final selectedRow = source.messages
            .where((m) => m['role'] == 'assistant')
            .elementAt(answer);
        final button = find.descendant(
          of: find.byKey(
            ValueKey('answer-actions-${answerMessageId(selectedRow)}'),
          ),
          matching: find.byTooltip('Branch in new session'),
        );
        await tester.scrollUntilVisible(
          button,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ProfileTranscript),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(button);
        await until(() => !source.changingAnswer);
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: 'Fork must not show an error toast',
        );
        final child = resource.chat!;
        expect(child.key, isNot(source.key));
        expect(children.add(child.key.sessionId), isTrue);
        expect(
          child.messages
              .where((m) => !isHiddenAnswerMessage(m))
              .map(answerMessageText),
          expected.take((answer + 1) * 2),
        );
        expect(
          jsonEncode(await resource.gateway.fullHistory(source.runtimeId)),
          original,
        );
        // Open via a fresh socket to check what was saved, beyond the UI cache.
        final verifier = ProfileGateway.forConnection(
          connection,
          resource.scope,
        );
        try {
          await verifier.connect();
          final saved = await verifier.call('session.resume', {
            'session_id': child.key.sessionId,
          });
          expect(jsonEncode(saved['info']), contains('gpt-5.6-luna'));
          expect(
            ProfileGateway.records(saved['messages']).map(answerMessageText),
            expected.take((answer + 1) * 2),
          );
        } finally {
          verifier.close();
        }
        if (answer == 1) middle = child;
        debugPrint(
          'fork-qa: answer ${answer + 1} copied and independently reloaded',
        );
      }
      await screenshot('fork-middle-boundary');
      final child = middle!;
      final composer = find.byKey(const Key('profile-message-composer'));
      await tester.enterText(
        composer,
        'What is my test token? Reply with only the token. Do not use tools.',
      );
      await tester.pumpAndSettle();
      expect(child.draft, contains('What is my test token?'));
      debugPrint('fork-qa: continuation entered; tapping Send');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(child.busy, isTrue, reason: 'Send must start the continuation');
      await until(() => !child.busy);
      expect(child.error, isNull);
      expect(child.messages.length, greaterThan(4));
      final response = answerMessageText(child.messages.last);
      expect(response, contains('JADE-42'));
      expect(response, isNot(contains('AMBER-99')));
      expect(find.text('[System: model changed for QA]'), findsNothing);
      expect(
        jsonEncode(await resource.gateway.fullHistory(source.runtimeId)),
        original,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await screenshot('fork-independent-continuation');
      final continued = child.messages
          .where((m) => !isHiddenAnswerMessage(m))
          .map(answerMessageText)
          .toList();
      final rebranch = find.descendant(
        of: find.byKey(
          ValueKey('answer-actions-${answerMessageId(child.messages.last)}'),
        ),
        matching: find.byTooltip('Branch in new session'),
      );
      await tester.ensureVisible(rebranch);
      await tester.tap(rebranch);
      await until(() => !child.changingAnswer);
      expect(find.byType(SnackBar), findsNothing);
      expect(resource.chat!.key, isNot(child.key));
      expect(
        resource.chat!.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        continued,
      );
      await controller.openSession(source.key);
      await tester.pumpAndSettle();
      expect(
        source.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        expected,
      );
      await screenshot('fork-original-unchanged');
      expect(tester.takeException(), isNull);
      debugPrint(
        'fork-qa: PASS: all three boundaries, saved reloads, Luna context, fork after continuation, unchanged source',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
