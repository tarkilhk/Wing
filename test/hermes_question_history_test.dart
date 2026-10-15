import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/transcript_reading.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_question.dart';
import 'package:wing/core/models/gateway_sensitive_prompt.dart';
import 'package:wing/core/services/chat_runtime.dart';
import 'package:wing/core/services/hermes_question_history.dart';

void main() {
  late SharedPreferences preferences;
  late HermesQuestionHistory history;
  late ChatRuntime runtime;
  const request = {
    'request_id': 'request',
    'server_request_id': 'server-request',
    'command': "python -c 'print(1)'",
    'description': 'Run verification',
  };
  final messages = <Map<String, dynamic>>[
    {'id': 10, 'role': 'user', 'content': 'Before'},
    {'id': 11, 'role': 'assistant', 'content': 'After'},
    {'id': 12, 'role': 'user', 'content': 'Newer'},
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    history = HermesQuestionHistory(preferences, 'chat-owner');
    addTearDown(history.flush);
    runtime = ChatRuntime(runtimeId: 'runtime');
    addTearDown(runtime.dispose);
    runtime.onQuestion = (question) =>
        history.observe(question, afterMessage: 10);
  });

  void expireApproval() => runtime.cancelRequest({
    'id': 'server-request',
    'method': 'approval',
    'reason': 'timeout',
  });

  void answerQuestion() {
    runtime.receiveQuestions({
      'request_id': 'question',
      'question': 'Which source?',
    });
    final answer = runtime.beginQuestionAnswer(runtime.observation.questions)!;
    runtime.finishQuestionAnswer(
      answer,
      answer: 'the chosen source',
      remaining: null,
    );
  }

  test('pending requests do not duplicate the active question in history', () {
    runtime.receiveApproval(request);
    expect(history.questions.single.status, HermesQuestionStatus.pending);
    expect(history.project(messages), messages);
  });

  test('delayed approval replay cannot erase expiry or first appearance', () {
    runtime.receiveApproval(request);
    final appeared = history.questions.single.timestamp;
    expireApproval();
    runtime.receiveApproval(request);
    expect(history.questions.single.status, HermesQuestionStatus.expired);
    expect(history.questions.single.timestamp, appeared);
  });

  test('completed question keeps its original neighbor as messages arrive', () {
    runtime.receiveApproval(request);
    expireApproval();
    expect(history.project(messages.take(2).toList()).map((row) => row['id']), [
      10,
      'hermes-question:approval/request',
      11,
    ]);
    expect(history.project(messages).map((row) => row['id']), [
      10,
      'hermes-question:approval/request',
      11,
      12,
    ]);
  });

  test(
    'reopened history retains the saved outcome and message position',
    () async {
      runtime.receiveApproval(request);
      final appeared =
          history.questions.single.timestamp.millisecondsSinceEpoch;
      expireApproval();
      await history.flush();
      SharedPreferences.setMockInitialValues({
        for (final key in preferences.getKeys()) key: preferences.get(key)!,
      });
      final reopened = HermesQuestionHistory(
        await SharedPreferences.getInstance(),
        'chat-owner',
      );
      expect(reopened.questions.single.status, HermesQuestionStatus.expired);
      expect(
        reopened.questions.single.timestamp.millisecondsSinceEpoch,
        appeared,
      );
      expect(reopened.project(messages).map((row) => row['id']), [
        10,
        'hermes-question:approval/request',
        11,
        12,
      ]);
    },
  );

  test(
    'a different authenticated owner cannot read another question history',
    () {
      runtime.receiveApproval(request);
      expireApproval();
      expect(history.questions, isNotEmpty);
      expect(
        HermesQuestionHistory(preferences, 'another-owner').questions,
        isEmpty,
      );
    },
  );

  test(
    'room outcome retains the first sequence through replay and later answers',
    () {
      final question = HermesQuestion(
        id: 'approval',
        requestId: 'request',
        kind: HermesQuestionKind.approval,
        status: HermesQuestionStatus.pending,
        timestamp: DateTime(2026, 10, 15, 13, 27),
        description: 'Inspect source',
      );
      history.observe(question, groupSequence: 5);
      history.reconcile({});
      history.observe(question, groupSequence: 50);
      history.settle('approval', HermesQuestionStatus.approved);
      history.reconcile({});
      expect(history.questions.single.status, HermesQuestionStatus.approved);
      expect(
        history
            .project([
              {'id': 'old', 'sequence': 3},
              {'id': 'reply', 'sequence': 6},
              {'id': 'new', 'sequence': 51},
            ])
            .map((row) => row['id']),
        ['old', 'hermes-question:approval', 'reply', 'new'],
      );
    },
  );

  for (final (choice, status) in [
    ('once', HermesQuestionStatus.approved),
    ('deny', HermesQuestionStatus.rejected),
  ]) {
    test('accepted $choice decision records ${status.name}', () {
      runtime.receiveApproval({
        'request_id': choice,
        'command': 'echo $choice',
      });
      final answer = runtime.beginApprovalAnswer(choice, choice);
      runtime.finishApprovalAnswer(answer, choice, accepted: true);
      expect(history.questions.single.status, status);
    });
  }

  test('clarification response records an answered outcome', () {
    answerQuestion();
    expect(history.questions.single.status, HermesQuestionStatus.answered);
  });

  test(
    'native clarification history does not receive a second question row',
    () {
      answerQuestion();
      final native = <Map<String, dynamic>>[
        ...messages,
        {
          'id': 13,
          'role': 'tool',
          'name': 'clarify',
          'tool_call_id': 'native-clarify',
          'content': jsonEncode({
            'responses': [
              {
                'question': 'Which source?',
                'choices_offered': ['the chosen source'],
                'status': 'answered',
                'user_response': 'the chosen source',
              },
            ],
          }),
        },
      ];
      expect(history.project(native), native);
      expect(history.project(native).last['content'], native.last['content']);
    },
  );

  test('interrupted secure input records cancellation', () {
    runtime.receiveSecure(
      const GatewaySensitivePromptRequest(
        kind: GatewaySensitivePromptKind.secret,
        requestId: 'secret',
        title: 'Secret needed',
        description: 'Authenticate',
        fieldLabel: 'Secret',
      ),
    );
    runtime.cancelRequest({
      'id': 'secret',
      'method': 'secret',
      'reason': 'interrupted',
    });
    expect(history.questions.single.status, HermesQuestionStatus.cancelled);
  });

  test(
    'missing pending approval records closed without inventing an answer',
    () {
      runtime.receiveApproval(request);
      runtime.reconcileApprovals(runtime.captureApprovalRead(), []);
      expect(history.questions.single.status, HermesQuestionStatus.closed);
    },
  );

  test(
    'saved question history excludes clarification response values',
    () async {
      answerQuestion();
      await history.flush();
      final saved = jsonEncode({
        for (final key in preferences.getKeys()) key: preferences.get(key)!,
      });
      expect(saved, contains('Which source?'));
      expect(saved, isNot(contains('the chosen source')));
      expect(saved, isNot(contains('lockedAnswers')));
    },
  );
  test(
    'question presentation identity survives outcome updates and refreshed rows',
    () {
      final reading = TranscriptReading.passive(
        scope: WorkspaceScope(
          connectionId: 'host',
          connectionIdentity: 'identity',
          profileName: 'default',
        ),
      )..questionHistory = history;
      reading.installSavedHistory([
        {'id': 10, 'role': 'user', 'content': 'Before'},
      ]);
      runtime.receiveApproval(request);
      expireApproval();
      final first = reading.messages.firstWhere(
        (row) => row['_hermes_question'] != null,
      );
      final identity = reading.messagePresentationId(first);
      history.settle('approval/request', HermesQuestionStatus.approved);
      reading.installSavedHistory([
        {'id': 10, 'role': 'user', 'content': 'Before'},
        {'id': 11, 'role': 'assistant', 'content': 'After'},
      ]);
      final updated = reading.messages.firstWhere(
        (row) => row['_hermes_question'] != null,
      );
      expect(reading.messagePresentationId(updated), identity);
      expect(
        (updated['_hermes_question'] as HermesQuestion).status,
        HermesQuestionStatus.approved,
      );
    },
  );

  test(
    'an untimestamped later reply cannot drag an unconfirmed prompt anchor down',
    () {
      history.observe(
        HermesQuestion(
          id: 'late-id',
          requestId: 'request',
          kind: HermesQuestionKind.approval,
          status: HermesQuestionStatus.closed,
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
          description: '',
        ),
      );
      final projected = history.project([
        {'id': 'prompt', 'timestamp': 1},
        {'id': 'later-reply'},
        {'id': 'newer-prompt', 'timestamp': 3},
      ]);
      expect(projected.map((row) => row['id']), [
        'prompt',
        'hermes-question:late-id',
        'later-reply',
        'newer-prompt',
      ]);
    },
  );
  test(
    'pending command metadata updates without moving its original position',
    () {
      runtime.receiveApproval(request);
      final appeared = history.questions.single.timestamp;
      runtime.receiveApproval({...request, 'command': 'echo changed command'});
      expect(history.questions.single.command, 'echo changed command');
      expect(history.questions.single.timestamp, appeared);
      expireApproval();
      expect(
        history
            .project([
              {'id': 10},
              {'id': 11},
            ])
            .map((row) => row['id']),
        [10, 'hermes-question:approval/request', 11],
      );
    },
  );

  test(
    'restored locked clarification answers retain only the answered status',
    () {
      runtime.receiveQuestions({
        'request_id': 'batch',
        'questions': [
          {'qid': 'first', 'question': 'First question?'},
          {'qid': 'second', 'question': 'Second question?'},
        ],
        'answers': {'first': 'private response value'},
      });
      expect(history.questions.map((q) => q.status), [
        HermesQuestionStatus.answered,
        HermesQuestionStatus.pending,
      ]);
      expect(
        history.questions.map((q) => q.description).join(),
        isNot(contains('private response value')),
      );
    },
  );
}
