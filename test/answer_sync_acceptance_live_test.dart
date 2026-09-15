import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

// Actual model turns and saved readback through separate local Hermes clients.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const port = int.fromEnvironment('HERMES_TEST_PORT');
  test(
    'regenerate replaces the saved answer and fork remains a separate chat',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final clients = <ProfileWorkspaceController>[];
      ProfileChat? original;
      try {
        Future<ProfileWorkspaceController> connect(String id) async {
          final client = ProfileWorkspaceController(
            connectionIdentity: id,
            connection: SavedConnection(
              id: id,
              label: 'Answer sync QA',
              host: '127.0.0.1',
              port: port,
              dashboardPortOverride: port,
              apiKey: '',
            ),
            preferences: await SharedPreferences.getInstance(),
          );
          clients.add(client);
          await client.initialize();
          expect(await client.switchProfile('android-qa-a'), isTrue);
          expect(client.error, isNull);
          return client;
        }

        Future<void> settle(ProfileChat chat) async {
          final deadline = DateTime.now().add(const Duration(seconds: 70));
          while (chat.busy && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          expect(chat.status, ProfileTurnStatus.completed);
          expect(chat.error, isNull);
        }

        final writer = await connect('answer-sync-writer');
        final chat = await writer.createChat();
        original = chat;
        await writer.updateDraft(
          chat,
          'Reply exactly ANSWER_SYNC_QA. Do not use tools.',
        );
        await writer.send(chat);
        await settle(chat);
        final index = chat.messages.lastIndexWhere(
          (row) => row['role'] == 'assistant',
        );
        expect(index, greaterThanOrEqualTo(0));
        final before = await writer.current!.gateway.read(
          'sessions/${chat.key.sessionId}/messages',
        );
        final oldAnswerId = (before['messages'] as List)
            .where((row) => row['role'] == 'assistant')
            .last['id'];
        expect(oldAnswerId, isA<int>());
        final branch = await writer.branchAnswer(chat, index);
        expect(branch, isNotNull);
        expect(branch!.key, isNot(chat.key));
        final regenerated = await writer.branchAnswer(
          chat,
          index,
          regenerate: true,
        );
        expect(regenerated?.key, chat.key);
        await settle(chat);

        final reader = await connect('answer-sync-fresh-reader');
        final fresh = await reader.openSession(
          ProfileSessionKey(reader.current!.scope, chat.key.sessionId),
        );
        expect(fresh, isNotNull);
        final answers = fresh!.messages
            .where((row) => row['role'] == 'assistant')
            .toList();
        expect(answers, hasLength(1));
        expect(answerMessageText(answers.single).trim(), 'ANSWER_SYNC_QA');
        final after = await reader.current!.gateway.read(
          'sessions/${chat.key.sessionId}/messages',
        );
        final newAnswerId = (after['messages'] as List)
            .where((row) => row['role'] == 'assistant')
            .single['id'];
        expect(newAnswerId, isA<int>());
        expect(newAnswerId, isNot(oldAnswerId));
        final freshBranch = await reader.openSession(
          ProfileSessionKey(reader.current!.scope, branch.key.sessionId),
        );
        expect(freshBranch, isNotNull);
        expect(
          freshBranch!.messages.where((row) => row['role'] == 'assistant'),
          hasLength(1),
        );
        expect(freshBranch.key.sessionId, isNot(fresh.key.sessionId));
        // Superseded alternatives are absent from fresh server hydration.
        // This verifies normal sync/branch behavior, not a shared version carousel.
        // ignore: avoid_print
        print(
          'ANSWER_SYNC_QA: regeneration saved one replacement; independent client reopened original and fork',
        );
      } finally {
        try {
          if (original?.busy == true) await clients.first.stop(original!);
        } finally {
          for (final client in clients) {
            client.dispose();
          }
          HttpOverrides.global = previous;
        }
      }
    },
    skip: port == 0,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
