import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/gateway_insight.dart';
import 'package:wing/core/models/notification_focus.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/models/side_question_delivery.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_paging_fixture.dart';

class RetentionFixture extends ProfilePagingFixture {
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    for (var i = 0; i < 50; i++)
      {'id': i, 'role': 'assistant', 'content': List.filled(1024, 'x').join()},
  ];
}

void main() {
  late RetentionFixture fixture;
  late ProfileWorkspaceController owner;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = RetentionFixture()..count = 200;
    owner = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'retention',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await owner.initialize();
  });
  tearDown(() => owner.dispose());

  test(
    'increasing navigation dataset plateaus transcript payload and owned chats',
    () async {
      final observations = <(int, int)>[];
      for (var i = 0; i < 100; i++) {
        await owner.openSession(
          ProfileSessionKey(owner.current!.scope, 'chat-$i'),
        );
        owner.showList();
        await Future<void>.delayed(Duration.zero);
        owner.pruneSettledState();
        final contentUnits = owner.current!.chats.values.fold<int>(
          0,
          (sum, chat) =>
              sum +
              chat.messages.fold<int>(
                0,
                (size, row) => size + (row['content'] as String).length,
              ),
        );
        observations.add((owner.retainedChatCount, contentUnits));
      }
      expect(observations.skip(20).map((item) => item.$1).toSet(), {20});
      expect(observations.skip(20).map((item) => item.$2).toSet(), {
        20 * 50 * 1024,
      });
      expect(owner.current!.chats.containsKey('chat-0'), isFalse);
      final firstReads = fixture.calls
          .where((call) => call.$2 == 'session.resume')
          .length;
      await owner.openSession(
        ProfileSessionKey(owner.current!.scope, 'chat-0'),
      );
      expect(
        fixture.calls.where((call) => call.$2 == 'session.resume').length,
        firstReads + 1,
      );
      expect(owner.current!.chat!.messages, hasLength(50));
    },
  );

  final obligations = <String, void Function(ProfileChat)>{
    'running turn': (chat) => chat.status = ProfileTurnStatus.running,
    'recovery': (chat) => chat.status = ProfileTurnStatus.reconnecting,
    'draft': (chat) => chat.draft = 'Unsent',
    'uncertain draft': (chat) => chat.draftSubmissionUncertain = true,
    'attachment': (chat) => chat.attachments.add(
      AttachmentDraft(
        id: 'file',
        cachedPath: '/staged/file',
        name: 'file',
        byteLength: 1,
        mediaType: 'text/plain',
        kind: AttachmentDraftKind.genericFile,
      ),
    ),
    'queue': (chat) => chat.queuedPrompts.add(QueuedPromptDraft(text: 'Next')),
    'queue editor': (chat) =>
        chat.editingQueuedPrompt = QueuedPromptDraft(text: 'Next'),
    'approval': (chat) =>
        chat.approvals.add({'request_id': 'approval', 'command': 'cmd'}),
    'question': (chat) =>
        chat.clarification = {'request_id': 'question', 'question': 'Which?'},
    'mutation': (chat) => chat.changingAnswer = true,
    'command': (chat) => chat.commandRunning = true,
    'notification': (chat) => chat.notificationReadTarget =
        const NotificationFocus('answer', 'result'),
    'subagent': (chat) => chat.subagents = [
      const GatewaySubagentActivity(
        id: 'child',
        goal: 'Work',
        phase: GatewaySubagentPhase.running,
      ),
    ],
    'unconfirmed child': (chat) => chat.unconfirmedSubagentIds.add('child'),
    'side question': (chat) => chat.sideQuestionDeliveries.add(
      const SideQuestionDelivery(
        taskId: 'side',
        question: 'Work',
        state: SideQuestionDeliveryState.pending,
      ),
    ),
  };
  for (final obligation in obligations.entries) {
    test(
      '${obligation.key} survives cache pressure and retains obsolete owner',
      () async {
        final resource = owner.current!;
        final protected = ProfileChat(
          key: ProfileSessionKey(resource.scope, 'protected'),
          runtimeId: 'protected',
          title: 'Protected',
        )..draftRestored = true;
        obligation.value(protected);
        resource.chats['protected'] = protected;
        for (var i = 0; i < 30; i++) {
          resource.chats['idle-$i'] =
              ProfileChat(
                  key: ProfileSessionKey(resource.scope, 'idle-$i'),
                  runtimeId: 'idle-$i',
                  title: 'Idle',
                )
                ..draftRestored = true
                ..lastActive = protected.lastActive + i + 1;
        }
        owner.pruneSettledState();
        expect(resource.chats['protected'], same(protected));
        expect(owner.retainedChatCount, 21);
        expect(owner.hasRetentionObligations, isTrue);
        resource.chats.remove('protected');
        expect(owner.hasRetentionObligations, isFalse);
      },
    );
  }
}
