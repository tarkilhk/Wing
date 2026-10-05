import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'helpers/pump_markdown_widget.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/widgets/answer_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/process_batch_fixture.dart';

class AnswerHost {
  final gateways = <String, ProfileGateway>{};
  final histories = <String, List<Map<String, dynamic>>>{};
  final parents = <String, String>{};
  final calls = <(String, Map<String, dynamic>)>[];
  Completer<void>? branchDelay;
  void Function(List<Map<String, dynamic>>)? alterBranch;
  List<Map<String, dynamic>>? branchReplyMessages;
  Completer<void>? submitDelay;
  Completer<void>? resumeDelay;
  Object? submitError;
  bool submitErrorAfterAcceptance = false;
  bool omitRowIds = false;
  bool omitSessionParent = false;
  bool clearSessionParent = false;
  bool omitListParent = false;
  bool clearListParent = false;
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

  ProfileGateway gateway(WorkspaceScope scope) {
    late final ProfileGateway gateway;
    gateway = ProfileGateway(
      scope: scope,
      connect: () async {
        // Short-lived project readers have no event subscription. Keep emitted
        // turn events addressed to the controller's live transport.
        if (gateway.onEvent != null) gateways[scope.profileName] = gateway;
      },
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
                    if (clearListParent)
                      'parent_session_id': null
                    else if (!omitListParent)
                      'parent_session_id': entry.value,
                  },
              ],
            }
          : historyPage(scope.profileName, path, query),
      rpc: (method, params) async {
        calls.add((method, params));
        final profile = scope.profileName;
        final id = (params['session_id'] as String? ?? 'original').replaceFirst(
          'runtime-',
          '',
        );
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
            await resumeDelay?.future;
            return session(id);
          case 'session.history':
            return {
              'messages': history(profile, id)
                  .where(shown)
                  .where((m) => m['compacted'] != true)
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
              histories['$profile/$child']![i]['row_id'] = next * 1000 + i + 1;
            }
            parents[child] = id;
            alterBranch?.call(histories['$profile/$child']!);
            return {
              ...session(child),
              'parent': id,
              if (branchReplyMessages != null) 'messages': branchReplyMessages,
            };
          case 'prompt.submit':
            await submitDelay?.future;
            if (submitError != null && !submitErrorAfterAcceptance) {
              throw submitError!;
            }
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
            if (submitError != null) throw submitError!;
            return {'status': 'streaming'};
        }
        return {};
      },
    );
    return gateway;
  }

  Future<void> complete(ProfileChat chat) async {
    gateways[chat.key.workspace.profileName]!.onEvent!(
      StreamEvent(
        type: 'message.complete',
        sessionId: chat.runtime.runtimeId,
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
  late AppPreferences appPreferences;
  late ProfileChat original;

  ProfileWorkspaceController makeController() => ProfileWorkspaceController(
    connectionIdentity: 'host-settings',
    access: ConnectionAccess(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      dashboardOAuth: null,
    ),
    preferences: preferences,
    appPreferences: appPreferences,
    gatewayFactory: host.gateway,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    host = AnswerHost();
    controller = makeController();
    await controller.initialize();
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'original'),
    );
    original = controller.current!.chat!;
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  for (final delivery in [
    processBatchEnvelope,
    '[IMPORTANT: Background process 1 completed normally (exit code 0).\nCommand: private\nOutput:\n]',
    'Message from 🤖 Hermes: private delivery',
  ]) {
    test(
      'internal delivery cannot be edited or replayed: ${delivery.substring(0, 20)}',
      () async {
        host.history('a', 'original')[0]['text'] = delivery;
        await controller.refreshHistory(original);
        await expectLater(
          controller.editSavedPrompt(
            original,
            original.reading.messages.first,
            'replacement',
          ),
          throwsStateError,
        );
        await expectLater(
          controller.branchAnswer(original, 2, regenerate: true),
          throwsStateError,
        );
        expect(host.calls.where((call) => call.$1 == 'prompt.submit'), isEmpty);
        expect(host.history('a', 'original').first['text'], delivery);
      },
    );
  }

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
      child.reading.messages
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
    'fork opens after copying archived turns omitted by RPC history',
    () async {
      host.history('a', 'original').insertAll(0, [
        {
          'role': 'user',
          'text': 'Archived prompt',
          'row_id': 6,
          'compacted': true,
        },
        {
          'role': 'assistant',
          'text': 'Archived answer',
          'row_id': 7,
          'compacted': true,
        },
      ]);
      final child = (await controller.branchAnswer(original, 2))!;
      expect(controller.current!.chat, same(child));
      expect(child.reading.messages.map(answerMessageText), [
        'Archived prompt',
        'Archived answer',
        'Original prompt',
        'Original answer',
      ]);
      expect(host.parents.length, 1);
      expect(host.history('a', 'original').length, 7);
    },
  );

  test('fork can target a saved archived answer', () async {
    host.history('a', 'original')[2]['compacted'] = true;
    final child = (await controller.branchAnswer(original, 2))!;
    expect(controller.current!.chat, same(child));
    expect(child.reading.messages.map(answerMessageText), [
      'Original prompt',
      'Original answer',
    ]);
  });

  test(
    'fork verifies saved text instead of the RPC display projection',
    () async {
      host.branchReplyMessages = [
        {'role': 'user', 'text': 'Projected prompt'},
        {'role': 'assistant', 'text': 'Original answer'},
      ];
      final child = (await controller.branchAnswer(original, 2))!;
      expect(controller.current!.chat, same(child));
      expect(child.reading.messages.map(answerMessageText), [
        'Original prompt',
        'Original answer',
      ]);
    },
  );

  for (final fault in ['missing', 'extra', 'changed']) {
    test(
      'fork rejects $fault saved content and keeps the child reachable',
      () async {
        host.alterBranch = (rows) {
          switch (fault) {
            case 'missing':
              rows.removeLast();
            case 'extra':
              rows.add({
                'role': 'assistant',
                'text': 'Later answer',
                'row_id': 9999,
              });
            case 'changed':
              rows.last['text'] = 'Different answer';
          }
        };
        await expectLater(
          controller.branchAnswer(original, 2),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('The fork was created'),
            ),
          ),
        );
        expect(controller.current!.chat, same(original));
        expect(controller.current!.chats, contains('child-1'));
        expect(
          controller.current!.sessions.any((row) => row['id'] == 'child-1'),
          isTrue,
        );
        expect(host.parents.length, 1);
        expect(host.history('a', 'original').length, 5);
        expect(original.runtime.changingAnswer, isFalse);
      },
    );
  }

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
        child.reading.messages
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
        original.reading.messages.any(isHiddenAnswerMessage),
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
      child.composer.editText('Continue the fork');
      await controller.send(child);
      await host.complete(child);
      final grandchild = (await controller.branchAnswer(
        child,
        child.reading.messages.length - 1,
      ))!;
      expect(
        grandchild.reading.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        child.reading.messages
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
        child.reading.messages
            .where((m) => !isHiddenAnswerMessage(m))
            .map(answerMessageText),
        ['Original prompt', 'Original answer'],
      );
      expect(original.reading.messages.length, 5);
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
    original.composer.editText('Unsent draft');
    final regenerated = (await controller.branchAnswer(
      original,
      2,
      regenerate: true,
    ))!;
    await host.complete(regenerated);
    final submit = host.calls.lastWhere((c) => c.$1 == 'prompt.submit').$2;
    expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
    expect(submit, {
      'session_id': original.runtime.runtimeId,
      'profile': 'a',
      'text': 'Original prompt',
      'truncate_before_row_id': 1,
      'confirm_truncate': true,
      'confirm_empty_truncate': true,
    });
    expect(
      regenerated.reading.messages
          .where((m) => !isHiddenAnswerMessage(m))
          .map(answerMessageText),
      ['Original prompt', 'New answer 0'],
    );
    expect(regenerated, same(original));
    expect(regenerated.parentSessionId, isNull);
    expect(original.composer.observation.text, 'Unsent draft');
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
      original.reading.installSavedHistory([
        Map<String, dynamic>.from(original.reading.messages.first)
          ..remove('text')
          ..['content'] = persisted,
        ...original.reading.messages.skip(1),
      ]);
      original.composer.editText('Keep this draft');

      final regenerated = (await controller.branchAnswer(
        original,
        2,
        regenerate: true,
      ))!;

      final submit = host.calls.lastWhere((call) => call.$1 == 'prompt.submit');
      expect(regenerated, same(original));
      expect(submit.$2['session_id'], original.runtime.runtimeId);
      expect(submit.$2['truncate_before_row_id'], 1);
      expect(submit.$2['text'], visible);
      expect(submit.$2['text'], isNot(contains(marker)));
      expect(submit.$2['text'], isNot(contains('fixture-value-amber-729')));
      expect(original.composer.observation.text, 'Keep this draft');
    },
  );

  test(
    'duplicate regeneration taps keep one replay while a fresh Send waits',
    () async {
      host.submitDelay = Completer<void>();
      final pending = controller.branchAnswer(original, 2, regenerate: true);
      await Future<void>.delayed(Duration.zero);
      expect(
        await controller.branchAnswer(original, 2, regenerate: true),
        isNull,
      );
      await controller.updateDraft(original, 'Queued follow-up');
      await controller.send(original);
      await controller.send(original);
      expect(original.composer.observation.text, isEmpty);
      expect(
        original.composer.observation.queue.single.text,
        'Queued follow-up',
      );
      expect(
        original.composer.observation.queue.single.submissionUncertain,
        isFalse,
      );
      expect(host.calls.where((c) => c.$1 == 'prompt.submit').length, 1);
      await controller.updateDraft(original, 'Separate fresh draft');
      host.submitDelay!.complete();
      final regenerated = (await pending)!;
      expect(host.calls.where((c) => c.$1 == 'prompt.submit').length, 1);
      expect(
        original.composer.observation.queue.single.text,
        'Queued follow-up',
      );
      await host.complete(regenerated);
      await Future<void>(() async {
        while (original.composer.observation.queue.isNotEmpty ||
            original.composer.observation.sending) {
          await Future<void>.delayed(Duration.zero);
        }
      }).timeout(const Duration(seconds: 10));
      expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
      final submissions = host.calls
          .where((call) => call.$1 == 'prompt.submit')
          .toList();
      expect(submissions, hasLength(2));
      expect(submissions.first.$2['truncate_before_row_id'], 1);
      expect(submissions.first.$2['text'], 'Original prompt');
      expect(submissions.last.$2['text'], 'Queued follow-up');
      expect(submissions.last.$2['queued'], isTrue);
      expect(
        submissions.last.$2.containsKey('truncate_before_row_id'),
        isFalse,
      );
      expect(original.composer.observation.text, 'Separate fresh draft');
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
    original.reading.installSavedHistory([
      ...original.reading.messages.take(2),
      {...original.reading.messages[2], 'content': 'Stale answer'},
      ...original.reading.messages.skip(3),
    ]);
    await expectLater(controller.branchAnswer(original, 2), throwsStateError);
    expect(host.calls.where((c) => c.$1 == 'session.branch'), isEmpty);
    expect(original.runtime.changingAnswer, isFalse);
  });

  test(
    'a paged transcript uses the saved row rather than its local position',
    () async {
      original.reading.installSavedHistory(
        original.reading.messages.sublist(3),
      );
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
        regenerated.reading.messages
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
      host.omitListParent = true;
      expect(await controller.switchProfile('a'), isTrue);
      expect(
        controller.current!.sessions
            .firstWhere((row) => row['id'] == child.key.sessionId)
            .containsKey('parent_session_id'),
        isFalse,
      );
      expect(controller.parentSessionId(child), original.key.sessionId);

      host.clearListParent = true;
      expect(await controller.switchProfile('a'), isTrue);
      final row = controller.current!.sessions.firstWhere(
        (row) => row['id'] == child.key.sessionId,
      );
      expect(row.containsKey('parent_session_id'), isTrue);
      expect(row['parent_session_id'], isNull);
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
    host.submitError = JsonRpcError(
      'prompt.submit',
      'Session busy',
      code: 4009,
    );
    await expectLater(
      controller.branchAnswer(original, 1, regenerate: true),
      throwsStateError,
    );
    expect(controller.current!.chat, same(original));
    expect(original.runtime.execution, ChatExecution.failed);
    expect(
      original.runtime.error,
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

      expect(original.runtime.execution, ChatExecution.failed);
      expect(
        original.runtime.error,
        'Hermes could not match this saved prompt. The conversation is unchanged. Send a new message to continue.',
      );
      expect(original.runtime.error, isNot(contains('JsonRpcError')));
      expect(controller.current!.chat, same(original));
      expect(original.reading.messages.last['text'], 'Later answer');
    },
  );

  test(
    'missing durable row IDs refuses regeneration without changing the chat',
    () async {
      final originalStatus = original.runtime.execution;
      host.omitRowIds = true;
      await expectLater(
        controller.branchAnswer(original, 2, regenerate: true),
        throwsStateError,
      );
      expect(original.runtime.execution, originalStatus);
      expect(
        original.runtime.error,
        'Hermes did not accept the regeneration. The conversation is unchanged.',
      );
      expect(original.reading.messages.last['text'], 'Later answer');
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
      expect(original.runtime.reconnecting, isTrue);
      expect(original.parentSessionId, isNull);
      await controller.reconnect(original.key.workspace);
      expect(host.calls.where((c) => c.$1 == 'prompt.submit').length, 1);
      expect(original.reading.messages.map(answerMessageText), [
        'Original prompt',
        'Tool output',
        'Original answer',
        'Follow-up',
        'Later answer',
      ]);
    },
  );

  for (final failure in [
    JsonRpcError('prompt.submit', 'Timeout', reason: 'request_timeout'),
    JsonRpcError(
      'prompt.submit',
      'Connection closed',
      reason: 'connection_closed',
    ),
    JsonRpcError('prompt.submit', 'Internal error', code: -32603),
    JsonRpcError(
      'prompt.submit',
      'Session storage could not be written',
      code: 5071,
    ),
  ]) {
    test(
      'regeneration reconciles accepted history after ${failure.reason ?? failure.code}',
      () async {
        // Hermes has already rewound the durable history before the reply fails.
        host.submitError = failure;
        host.submitErrorAfterAcceptance = true;
        final regenerated = await controller.branchAnswer(
          original,
          2,
          regenerate: true,
        );

        expect(regenerated, same(original));
        expect(original.runtime.reconnecting, isTrue);
        expect(original.runtime.error, contains('uncertain'));
        expect(original.runtime.error, isNot(contains('unchanged')));
        expect(original.reading.messages.map(answerMessageText), [
          'Original prompt',
        ]);

        host.resumeDelay = Completer<void>();
        final recovery = controller.reconnect(original.key.workspace);
        await controller.updateDraft(original, 'New draft during recovery');
        host.resumeDelay!.complete();
        await recovery;

        expect(original.reading.messages.map(answerMessageText), [
          'Original prompt',
          'New answer 0',
        ]);
        expect(original.composer.observation.text, 'New draft during recovery');
        expect(original.runtime.execution, ChatExecution.completed);
        expect(
          host.calls.where((call) => call.$1 == 'prompt.submit'),
          hasLength(1),
        );
        expect(
          host.calls.where((call) => call.$1 == 'session.branch'),
          isEmpty,
        );
      },
    );
  }

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
          if (controller.current!.chat!.runtime.execution ==
              ChatExecution.running) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      await tester.pump();
      final regenerated = controller.current!.chat!;
      expect(regenerated, same(original));
      expect(regenerated.runtime.execution, ChatExecution.running);
      await tester.runAsync(() => host.complete(regenerated));
      await tester.pumpAndSettle();
      await tester.settleMarkdown();
      expect(regenerated.runtime.execution, ChatExecution.completed);
      expect(
        regenerated.reading.messages
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

  testWidgets('notice shares actions for the preceding saved answer', (
    tester,
  ) async {
    host.history('a', 'original').insert(3, {
      'role': 'user',
      'text': 'Background result',
      'row_id': 6,
      'display_kind': 'async_delegation_complete',
      'display_metadata': {'task_count': 1},
    });
    await controller.refreshHistory(original);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    final actions = find.byKey(const ValueKey('answer-actions-3'));
    final notice = find.text('1 background agent finished');
    expect(actions, findsOneWidget);
    expect(notice, findsOneWidget);
    expect(tester.getRect(actions).overlaps(tester.getRect(notice)), isFalse);
    expect(
      tester.getTopLeft(actions).dy,
      lessThan(tester.getBottomLeft(notice).dy),
    );
    await tester.tap(
      find.descendant(
        of: actions,
        matching: find.byTooltip('Branch in new session'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      host.calls.lastWhere((call) => call.$1 == 'session.branch').$2['count'],
      2,
    );
    expect(
      controller.current!.chat!.reading.messages.last['text'],
      'Original answer',
    );
  });

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
