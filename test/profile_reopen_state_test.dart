import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_workspace_controller_test.dart' show Host;

class ReopenHost extends Host {
  Map<String, dynamic> pending = {};
  bool loseSubmitAcknowledgement = false;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      close: base.close,
      get: base.read,
      rpc: (method, params) async {
        final result = await base.call(method, params);
        if (method == 'prompt.submit' && loseSubmitAcknowledgement) {
          throw TimeoutException('Acknowledgement lost');
        }
        return {...result, if (method == 'session.resume') ...pending};
      },
    );
  }
}

void main() {
  late ReopenHost host;
  late ProfileWorkspaceController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ReopenHost();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'reopen',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  test(
    'reopening a cached chat reads current run and pending-input state',
    () async {
      final chat = await controller.createChat();
      chat.draft = 'An unsent follow-up';
      controller.showList();
      host.pending = {
        'pending_approval': {'command': 'example'},
      };
      await controller.openSession(chat.key);
      expect(chat.status, ProfileTurnStatus.attention);
      expect(chat.approval?['command'], 'example');
      expect(chat.draft, 'An unsent follow-up');

      controller.showList();
      host.pending = {
        'open_requests': [
          {
            'id': 'q',
            'method': 'clarify',
            'params': {
              'session_id': chat.runtimeId,
              'question': 'Which result?',
            },
          },
        ],
      };
      await controller.openSession(chat.key);
      expect(chat.approval, isNull);
      expect(chat.clarification?['request_id'], 'q');
      expect(chat.status, ProfileTurnStatus.attention);

      controller.showList();
      host.pending = {};
      host.running = false;
      await controller.openSession(chat.key);
      expect(chat.clarification, isNull);
      expect(chat.busy, isFalse);
      expect(chat.messages.single['content'], 'a completed');
      expect(host.calls.where((c) => c.$2 == 'prompt.submit'), isEmpty);
    },
  );

  test(
    'a lost submit acknowledgement is reconciled without resending',
    () async {
      final chat = await controller.createChat();
      chat.draft = 'Send this once';
      host.loseSubmitAcknowledgement = true;
      await controller.send(chat);
      expect(chat.status, ProfileTurnStatus.reconnecting);
      await controller.reconnect(chat.key.workspace);
      expect(chat.status, ProfileTurnStatus.running);
      expect(host.calls.where((c) => c.$2 == 'prompt.submit'), hasLength(1));
    },
  );

  test(
    'resume restores unanswered batch questions from open_requests',
    () async {
      final chat = await controller.createChat();
      host.pending = {
        'open_requests': [
          {
            'id': 'foreign',
            'method': 'clarify',
            'params': {
              'session_id': 'other-runtime',
              'question': 'Wrong owner',
            },
          },
          {
            'id': 'batch-request',
            'method': 'clarify',
            'params': {
              'session_id': chat.runtimeId,
              'questions': [
                {'qid': 'q0', 'question': 'Which room?'},
                {'qid': 'q1', 'question': 'What budget?'},
              ],
              'answers': {'q0': 'Bedroom'},
            },
          },
        ],
      };
      await controller.reconnect(chat.key.workspace);
      expect(chat.status, ProfileTurnStatus.attention);
      expect(chat.pendingQuestion!['question'], 'What budget?');
      await controller.clarify(chat, '250');
      final reply = host.calls.last;
      expect(reply.$2, 'clarify.lock');
      expect(reply.$3['request_id'], 'batch-request');
      expect(reply.$3['question_id'], 'q1');
      expect(reply.$3['answer'], '250');
    },
  );

  test(
    'reopening does not replace a submission awaiting acknowledgement',
    () async {
      final chat = await controller.createChat();
      chat.status = ProfileTurnStatus.submitting;
      controller.showList();
      await controller.openSession(chat.key);
      expect(controller.current!.chat, same(chat));
      expect(chat.status, ProfileTurnStatus.submitting);
      expect(host.calls.where((c) => c.$2 == 'session.resume'), isEmpty);
    },
  );
}
