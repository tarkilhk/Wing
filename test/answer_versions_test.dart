import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/answer_versions.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/services/profiles_repository.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/answer_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnswerHost {
  final gateways = <String, ProfileGateway>{};
  final histories = <String, List<Map<String, dynamic>>>{};
  final parents = <String, String>{};
  final calls = <(String, Map<String, dynamic>)>[];
  Completer<void>? branchDelay;
  Completer<void>? submitDelay;
  Object? submitError;
  bool omitRowIds = false;
  bool omitSessionParent = false;
  bool clearSessionParent = false;
  int next = 0;
  int nextRow = 10000;

  bool shown(Map<String, dynamic> message) => !isHiddenAnswerMessage(message);

  List<Map<String, dynamic>> history(String profile, String id) =>
      histories.putIfAbsent(
        '$profile/$id',
        () => [
          {'role': 'user', 'text': 'Original prompt', 'row_id': 1},
          {'role': 'tool', 'text': 'Tool output', 'row_id': 2},
          {'role': 'assistant', 'text': 'Original answer', 'row_id': 3},
          {'role': 'user', 'text': 'Follow-up', 'row_id': 4},
          {'role': 'assistant', 'text': 'Later answer', 'row_id': 5},
        ],
      );

  Map<String, dynamic> historyPage(
    String profile,
    String path,
    Map<String, String> query,
  ) {
    final id = Uri.decodeComponent(path.split('/')[1]);
    final rows = history(profile, id);
    final offset = int.parse(query['offset']!);
    final limit = int.parse(query['limit']!);
    final selected = query['order'] == 'oldest'
        ? rows.skip(offset).take(limit).toList()
        : rows.reversed.skip(offset).take(limit).toList().reversed.toList();
    return {
      'session_id': id,
      'pagination': {
        'limit': limit,
        'offset': offset,
        'order': query['order'],
        'returned': selected.length,
      },
      'messages': answerHistoryRows(selected),
    };
  }

  ProfileGateway gateway(WorkspaceScope scope) =>
      gateways[scope.profileName] = ProfileGateway(
        scope: scope,
        discover: () async => const ProfileDiscovery(
          profiles: [
            HermesProfile(name: 'a'),
            HermesProfile(name: 'b'),
          ],
          currentName: 'a',
          activeName: 'a',
        ),
        get: (path, query) async => path == 'sessions'
            ? {
                'offset': int.parse(query['offset']!),
                'limit': int.parse(query['limit']!),
                'total': 1 + parents.length,
                'sessions': [
                  {
                    'id': 'original',
                    'title': 'Original chat',
                    'profile': scope.profileName,
                  },
                  for (final entry in parents.entries)
                    {
                      'id': entry.key,
                      'title': 'Branched chat',
                      'profile': scope.profileName,
                      'parent_session_id': entry.value,
                    },
                ],
              }
            : historyPage(scope.profileName, path, query),
        rpc: (method, params) async {
          calls.add((method, params));
          final profile = scope.profileName;
          final id = (params['session_id'] as String? ?? 'original')
              .replaceFirst('runtime-', '');
          Map<String, dynamic> session(String child) => {
            'session_id': 'runtime-$child',
            'stored_session_id': child,
            if (clearSessionParent)
              'parent_session_id': null
            else if (!omitSessionParent && parents.containsKey(child))
              'parent_session_id': parents[child],
            'messages': history(
              profile,
              child,
            ).where(shown).map((m) => Map<String, dynamic>.from(m)).toList(),
            'info': {'profile_name': profile},
            'title': 'Branched chat',
          };
          switch (method) {
            case 'projects.tree':
              return {'projects': <Map<String, dynamic>>[]};
            case 'session.resume':
              return session(id);
            case 'session.history':
              return {
                'messages': history(profile, id)
                    .where(shown)
                    .map(
                      (m) => {
                        ...m,
                        if (omitRowIds && m['role'] == 'user') 'row_id': null,
                      },
                    )
                    .toList(),
              };
            case 'session.branch':
              await branchDelay?.future;
              final child = 'child-${++next}';
              histories['$profile/$child'] = history(profile, id)
                  .where(isBranchMessage)
                  .take(params['count'] as int)
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList();
              for (var i = 0; i < histories['$profile/$child']!.length; i++) {
                histories['$profile/$child']![i]['row_id'] =
                    next * 1000 + i + 1;
              }
              parents[child] = id;
              return {...session(child), 'parent': id};
            case 'prompt.submit':
              await submitDelay?.future;
              if (submitError != null) throw submitError!;
              final rows = history(profile, id);
              final cut = params['truncate_before_row_id'];
              if (cut != null) {
                final index = rows.indexWhere((m) => m['row_id'] == cut);
                rows.removeRange(index, rows.length);
              }
              rows.add({
                'role': 'user',
                'text': params['text'],
                'row_id': nextRow++,
              });
              rows.add({
                'role': 'assistant',
                'text': 'New answer $next',
                'row_id': nextRow++,
              });
              return {'status': 'streaming'};
          }
          return {};
        },
      );

  Future<void> complete(ProfileChat chat) async {
    gateways[chat.key.workspace.profileName]!.onEvent!(
      StreamEvent(
        type: 'message.complete',
        sessionId: chat.runtimeId,
        data: const {},
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late AnswerHost host;
  late SharedPreferences preferences;
  late ProfileWorkspaceController controller;
  late ProfileChat original;

  ProfileWorkspaceController makeController() => ProfileWorkspaceController(
    connectionIdentity: 'host-settings',
    connection: SavedConnection(
      id: 'host',
      label: 'Host',
      host: 'localhost',
      port: 1,
      apiKey: '',
    ),
    preferences: preferences,
    gatewayFactory: host.gateway,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    host = AnswerHost();
    controller = makeController();
    await controller.initialize();
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'original'),
    );
    original = controller.current!.chat!;
  });
  tearDown(() => controller.dispose());

  test('stored multimodal rows use the gateway text projection', () {
    expect(
      answerMessageText({
        'content': [
          'one',
          {'type': 'text', 'text': 'two'},
        ],
      }),
      'onetwo',
    );
    expect(
      isBranchMessage({
        'role': 'user',
        'content': [
          {
            'type': 'image_url',
            'image_url': {'url': 'https://example.test/qa.png'},
          },
        ],
      }),
      isTrue,
    );
    expect(
      isBranchMessage({
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {'id': 'qa-tool'},
        ],
      }),
      isFalse,
    );
  });

  test('saved user prompts use the Desktop attached-context projection', () {
    const marker = '--- Attached Context ---';
    const block = '''📄 @file:fixture.txt (4 tokens)
```text
fixture-value-amber-729
```''';
    final expanded =
        '@file:fixture.txt\n\nSummarize this file.\n\n$marker\n\n$block';
    final duplicated = '$expanded\n\n$marker\n\n$block\n\n$block';

    expect(
      answerMessageDisplayText({'role': 'user', 'content': expanded}),
      '@file:fixture.txt\n\nSummarize this file.',
    );
    expect(
      answerMessageDisplayText({'role': 'user', 'content': duplicated}),
      '@file:fixture.txt\n\nSummarize this file.',
      reason: 'Desktop treats the first producer marker as the boundary',
    );
    expect(
      answerMessageDisplayText({
        'role': 'user',
        'content': 'Look here\n\n$marker\n\n$block',
      }),
      '@file:fixture.txt\n\nLook here',
      reason: 'References stripped by older producers are restored once',
    );
  });

  test('user display projection preserves non-context message forms', () {
    expect(
      answerMessageDisplayText({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'serialized '},
          {'type': 'input_text', 'text': 'prompt'},
        ],
      }),
      'serialized prompt',
    );
    expect(
      answerMessageDisplayText({
        'role': 'user',
        'content': 'Email me at qa@example.test',
      }),
      'Email me at qa@example.test',
    );
    expect(
      answerMessageDisplayText({
        'role': 'user',
        'content': 'Visible\n\n--- Context Warnings ---\n- unavailable',
      }),
      'Visible',
    );
    expect(
      answerMessageDisplayText({
        'role': 'user',
        'content': 'wire text',
        'display_content': 'visible text',
      }),
      'visible text',
    );
    expect(
      answerMessageDisplayText({
        'role': 'user',
        'content': 'fallback text',
        'display_content': null,
      }),
      'fallback text',
    );
  });

  test(
    'saved multimodal user display hides image bytes but retains raw text',
    () {
      const encoded = 'data:image/png;base64,QA_IMAGE_BYTES';
      final saved = <String, dynamic>{
        'role': 'user',
        'row_id': 17,
        'content': [
          {'type': 'text', 'text': 'Read this image'},
          {
            'type': 'image_url',
            'image_url': {'url': encoded},
          },
        ],
      };
      final row = answerHistoryRows([saved]).single;
      expect(answerMessageDisplayText(row), 'Read this image\n[image]');
      expect(answerMessageText(row), answerMessageText(saved));
      expect(answerMessageText(row), contains(encoded));
      expect(answerMessageId(row), 17);
      expect(
        answerMessageDisplayText({...saved, 'display_content': 'Visible'}),
        'Visible',
      );
      expect(
        answerMessageDisplayText({...saved, 'display_content': null}),
        'Read this image\n[image]',
      );
      expect(
        answerMessageDisplayText({'role': 'user', 'content': encoded}),
        encoded,
        reason: 'Do not remove data URLs authored as plain text',
      );
      final assistant = {...saved, 'role': 'assistant'};
      expect(
        answerMessageDisplayText(answerHistoryRows([assistant]).single),
        answerMessageText(assistant),
      );
    },
  );

  test('assistant content is never treated as attached user context', () {
    const content = '''Answer code:
--- Attached Context ---
```dart
void main() {}
```''';
    expect(
      answerMessageDisplayText({'role': 'assistant', 'content': content}),
      content,
    );
  });

  test('hidden notices count toward the persisted fork boundary', () async {
    host.history('a', 'original').insert(1, {
      'role': 'user',
      'text': '[System: model changed]',
      'row_id': 8,
    });
    final child = (await controller.branchAnswer(original, 2))!;
    expect(
      child.messages
          .where((m) => !isHiddenAnswerMessage(m))
          .map(answerMessageText),
      ['Original prompt', 'Original answer'],
    );
    expect(
      host.calls.lastWhere((c) => c.$1 == 'session.branch').$2['count'],
      3,
    );
    expect(host.history('a', 'original').length, 6);
  });

  test(
    'resolves saved fork boundaries beyond the first history page',
    () async {
      host
          .history('a', 'original')
          .insertAll(
            0,
            List.generate(
              505,
              (i) => {
                'role': 'user',
                'text': '[System: notice $i]',
                'row_id': 1000 + i,
              },
            ),
          );
      final child = (await controller.branchAnswer(original, 2))!;
      expect(
        child.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        ['Original prompt', 'Original answer'],
      );
      expect(
        host.calls.lastWhere((c) => c.$1 == 'session.branch').$2['count'],
        507,
      );
    },
  );

  test('a missing saved answer refuses before creating a child', () async {
    host.history('a', 'original')[2].remove('row_id');
    await expectLater(controller.branchAnswer(original, 2), throwsStateError);
    expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
  });

  testWidgets(
    'raw history keeps hidden gateway notices out of the transcript',
    (tester) async {
      host.history('a', 'original').insert(1, {
        'role': 'user',
        'text': '[System: model changed]',
        'row_id': 8,
      });
      await controller.refreshHistory(original);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('[System: model changed]'), findsNothing);
      expect(
        host.calls.where((call) => call.$1 == 'session.answer_versions'),
        isEmpty,
        reason: 'Reading answers uses only existing Hermes APIs',
      );
      expect(
        original.messages.any(isHiddenAnswerMessage),
        isTrue,
        reason:
            'Raw rows remain available for pagination and branch addressing',
      );
    },
  );

  test(
    'a continued fork can be forked again without exposing hidden notices',
    () async {
      host.history('a', 'original').insert(1, {
        'role': 'user',
        'text': '[System: model changed]',
        'row_id': 8,
      });
      final child = (await controller.branchAnswer(original, 2))!;
      child.draft = 'Continue the fork';
      await controller.send(child);
      await host.complete(child);
      final grandchild = (await controller.branchAnswer(
        child,
        child.messages.length - 1,
      ))!;
      expect(
        grandchild.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        child.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
      );
    },
  );

  test(
    'branches at the selected answer, ignoring tools and later turns',
    () async {
      final child = (await controller.branchAnswer(original, 2))!;
      expect(
        child.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        ['Original prompt', 'Original answer'],
      );
      expect(original.messages.length, 5);
      expect(controller.current!.chat, same(child));
      expect(host.calls.lastWhere((c) => c.$1 == 'session.branch').$2, {
        'session_id': 'runtime-original',
        'count': 2,
        'profile': 'a',
      });
      expect(host.calls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
    },
  );

  test('regenerates in place without creating a branch', () async {
    original.draft = 'Unsent draft';
    final regenerated = (await controller.branchAnswer(
      original,
      2,
      regenerate: true,
    ))!;
    await host.complete(regenerated);
    final submit = host.calls.lastWhere((c) => c.$1 == 'prompt.submit').$2;
    expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
    expect(submit, {
      'session_id': original.runtimeId,
      'profile': 'a',
      'text': 'Original prompt',
      'truncate_before_row_id': 1,
      'confirm_truncate': true,
      'confirm_empty_truncate': true,
    });
    expect(
      regenerated.messages
          .where((m) => !isHiddenAnswerMessage(m))
          .map(answerMessageText),
      ['Original prompt', 'New answer 0'],
    );
    expect(regenerated, same(original));
    expect(regenerated.parentSessionId, isNull);
    expect(original.draft, 'Unsent draft');
    expect(
      preferences.getKeys().where((k) => k.startsWith('answer_versions')),
      isEmpty,
    );
  });

  test(
    'regeneration replays visible text from duplicated persisted context',
    () async {
      const marker = '--- Attached Context ---';
      const block = '''📄 @file:fixture.txt (4 tokens)
```text
fixture-value-amber-729
```''';
      const visible = '@file:fixture.txt\n\nSummarize this file.';
      const persisted =
          '$visible\n\n$marker\n\n$block\n\n$marker\n\n$block\n\n$block';
      host.history('a', 'original')[0]
        ..remove('text')
        ..['content'] = persisted;
      original.messages[0]
        ..remove('text')
        ..['content'] = persisted;
      original.draft = 'Keep this draft';

      final regenerated = (await controller.branchAnswer(
        original,
        2,
        regenerate: true,
      ))!;

      final submit = host.calls.lastWhere((call) => call.$1 == 'prompt.submit');
      expect(regenerated, same(original));
      expect(submit.$2['session_id'], original.runtimeId);
      expect(submit.$2['truncate_before_row_id'], 1);
      expect(submit.$2['text'], visible);
      expect(submit.$2['text'], isNot(contains(marker)));
      expect(submit.$2['text'], isNot(contains('fixture-value-amber-729')));
      expect(original.draft, 'Keep this draft');
    },
  );

  test('startup purges only obsolete local answer relationships', () async {
    controller.dispose();
    await preferences.setString('answer_versions_v1_old-host', 'obsolete');
    await preferences.setString('answer_versions_v10_keep', 'other');
    await preferences.setString('composer_draft_v1_keep', 'draft');
    controller = makeController();

    await controller.initialize();

    expect(preferences.containsKey('answer_versions_v1_old-host'), isFalse);
    expect(preferences.getString('answer_versions_v10_keep'), 'other');
    expect(preferences.getString('composer_draft_v1_keep'), 'draft');
  });

  test(
    'duplicate taps and sending during regeneration do not submit twice',
    () async {
      host.submitDelay = Completer<void>();
      final pending = controller.branchAnswer(original, 2, regenerate: true);
      await Future<void>.delayed(Duration.zero);
      expect(
        await controller.branchAnswer(original, 2, regenerate: true),
        isNull,
      );
      original.draft = 'Do not send yet';
      await controller.send(original);
      expect(host.calls.where((c) => c.$1 == 'prompt.submit').length, 1);
      host.submitDelay!.complete();
      final regenerated = (await pending)!;
      await host.complete(regenerated);
      expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
      expect(host.calls.where((c) => c.$1 == 'prompt.submit').length, 1);
    },
  );

  test(
    'profile switch during regeneration keeps navigation and owners isolated',
    () async {
      host.submitDelay = Completer<void>();
      final pending = controller.branchAnswer(original, 2, regenerate: true);
      await Future<void>.delayed(Duration.zero);
      await controller.switchProfile('b');
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'original'),
      );
      host.submitDelay!.complete();
      final regenerated = (await pending)!;
      await host.complete(regenerated);
      expect(controller.current!.scope.profileName, 'b');
      expect(
        host.calls.lastWhere((c) => c.$1 == 'prompt.submit').$2['profile'],
        'a',
      );
    },
  );

  test('leaving the chat during a branch does not reopen it', () async {
    host.branchDelay = Completer<void>();
    final pending = controller.branchAnswer(original, 2);
    await Future<void>.delayed(Duration.zero);
    controller.showList();
    host.branchDelay!.complete();
    await pending;
    expect(controller.current!.chat, isNull);
  });

  test('stale history refuses the branch before mutation', () async {
    original.messages[2]['content'] = 'Stale answer';
    await expectLater(controller.branchAnswer(original, 2), throwsStateError);
    expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
    expect(original.changingAnswer, isFalse);
  });

  test(
    'a paged transcript uses the saved row rather than its local position',
    () async {
      original.messages = original.messages.sublist(3);
      final regenerated = (await controller.branchAnswer(
        original,
        1,
        regenerate: true,
      ))!;
      await host.complete(regenerated);
      expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
      expect(
        host.calls.lastWhere((c) => c.$1 == 'prompt.submit').$2['text'],
        'Follow-up',
      );
      expect(
        host.calls
            .lastWhere((c) => c.$1 == 'prompt.submit')
            .$2['truncate_before_row_id'],
        4,
      );
      expect(
        regenerated.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        [
          'Original prompt',
          'Tool output',
          'Original answer',
          'Follow-up',
          'New answer 0',
        ],
      );
      expect(regenerated, same(original));
    },
  );

  test(
    'parent navigation uses the server lineage in the captured profile',
    () async {
      final child = (await controller.branchAnswer(original, 2))!;
      await controller.switchProfile('b');

      await controller.openParentChat(child);

      expect(controller.current!.scope.profileName, 'a');
      expect(controller.current!.chat, same(original));
    },
  );

  test(
    'explicit server parent state wins while omitted metadata falls back',
    () async {
      final child = (await controller.branchAnswer(original, 2))!;
      final row = controller.current!.sessions.firstWhere(
        (row) => row['id'] == child.key.sessionId,
      );
      row.remove('parent_session_id');
      expect(controller.parentSessionId(child), original.key.sessionId);

      row['parent_session_id'] = null;
      expect(controller.parentSessionId(child), isNull);
    },
  );

  test(
    'server parent lineage restores without phone relationship state',
    () async {
      final child = (await controller.branchAnswer(original, 2))!;
      final key = child.key;
      host.omitSessionParent = true;
      controller.dispose();
      controller = makeController();
      await controller.initialize();

      await controller.openSession(key);

      final restored = controller.current!.chat!;
      expect(restored.parentSessionId, original.key.sessionId);
      expect(
        preferences.getKeys().where((key) => key.startsWith('answer_versions')),
        isEmpty,
      );
    },
  );

  testWidgets('explicit null resume parent clears stale list navigation', (
    tester,
  ) async {
    final child = (await controller.branchAnswer(original, 2))!;
    final key = child.key;
    controller.dispose();
    host.clearSessionParent = true;
    controller = makeController();
    await controller.initialize();

    await controller.openSession(key);
    final restored = controller.current!.chat!;
    expect(controller.parentSessionId(restored), isNull);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pumpAndSettle();
    expect(find.text('Parent chat'), findsNothing);
  });

  test('rejected regeneration restores the same chat', () async {
    final regenerated = (await controller.branchAnswer(
      original,
      2,
      regenerate: true,
    ))!;
    await host.complete(regenerated);
    host.submitError = JsonRpcError('prompt.submit', 'Session busy');
    await expectLater(
      controller.branchAnswer(original, 1, regenerate: true),
      throwsStateError,
    );
    expect(controller.current!.chat, same(original));
    expect(original.status, ProfileTurnStatus.failed);
    expect(
      original.error,
      'Hermes did not accept the regeneration. The conversation is unchanged.',
    );
  });

  test(
    'stale saved prompt rejection stays actionable and hides RPC text',
    () async {
      host.submitError = JsonRpcError(
        'prompt.submit',
        'target user message is no longer in session history',
        code: 4018,
      );

      await expectLater(
        controller.branchAnswer(original, 2, regenerate: true),
        throwsStateError,
      );

      expect(original.status, ProfileTurnStatus.failed);
      expect(
        original.error,
        'Hermes could not match this saved prompt. The conversation is unchanged. Send a new message to continue.',
      );
      expect(original.error, isNot(contains('JsonRpcError')));
      expect(controller.current!.chat, same(original));
      expect(original.messages.last['text'], 'Later answer');
    },
  );

  test(
    'missing durable row IDs refuses regeneration without changing the chat',
    () async {
      host.omitRowIds = true;
      await expectLater(
        controller.branchAnswer(original, 2, regenerate: true),
        throwsStateError,
      );
      expect(original.status, ProfileTurnStatus.failed);
      expect(
        original.error,
        'Hermes did not accept the regeneration. The conversation is unchanged.',
      );
      expect(original.messages.last['text'], 'Later answer');
      expect(host.calls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
      expect(controller.current!.chat, same(original));
    },
  );

  test(
    'uncertain regenerate keeps the same chat and does not resubmit',
    () async {
      host.submitError = TimeoutException('connection lost');
      final regenerated = (await controller.branchAnswer(
        original,
        2,
        regenerate: true,
      ))!;
      expect(regenerated, same(original));
      expect(original.status, ProfileTurnStatus.reconnecting);
      expect(original.parentSessionId, isNull);
      await controller.reconnect(original.key.workspace);
      expect(host.calls.where((c) => c.$1 == 'prompt.submit').length, 1);
      expect(original.messages.map(answerMessageText), [
        'Original prompt',
        'Tool output',
        'Original answer',
        'Follow-up',
        'Later answer',
      ]);
    },
  );

  testWidgets(
    'regenerate updates the same chat without parent navigation or carousel',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      final originalActions = find.byKey(const ValueKey('answer-actions-3'));
      await tester.ensureVisible(originalActions);
      await tester.tap(
        find.descendant(
          of: originalActions,
          matching: find.byTooltip('Regenerate response'),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          if (controller.current!.chat!.status == ProfileTurnStatus.running) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      await tester.pump();
      final regenerated = controller.current!.chat!;
      expect(regenerated, same(original));
      expect(regenerated.status, ProfileTurnStatus.running);
      await tester.runAsync(() => host.complete(regenerated));
      await tester.pumpAndSettle();
      expect(regenerated.status, ProfileTurnStatus.completed);
      expect(
        regenerated.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        ['Original prompt', 'New answer 0'],
      );
      expect(find.text('New answer 0'), findsOneWidget);
      expect(find.byTooltip('Previous answer'), findsNothing);
      expect(find.byTooltip('Next answer'), findsNothing);
      await tester.tap(find.byTooltip('Chat actions'));
      await tester.pumpAndSettle();
      expect(find.text('Parent chat'), findsNothing);
      expect(find.text('Original answer'), findsNothing);
      expect(find.text('Later answer'), findsNothing);
    },
  );

  testWidgets(
    'server branch controls fit a narrow phone without version arrows',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerActions(onBranch: () {}, onRegenerate: () {}),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Branch in new session'), findsOneWidget);
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );
}
