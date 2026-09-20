import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_workspace_controller_test.dart' show Host;

Map<String, dynamic> approval(String id, {String? serverId}) => {
  'request_id': id,
  'server_request_id': ?serverId,
  'command': 'echo $id',
  'choices': ['once', 'deny'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Host host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  late List<ProfileNotification> alerts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host();
    alerts = [];
    controller = ProfileWorkspaceController(
      connectionIdentity: 'host',
      connection: SavedConnection(
        id: 'host',
        label: 'Home',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
      onAttention: (notification) async => alerts.add(notification),
    );
    await controller.initialize();
    chat = await controller.createChat();
  });
  tearDown(() => controller.dispose());

  test(
    'duplicate live delivery updates metadata without re-alerting or reordering',
    () {
      host.event('a', 'approval', approval('one', serverId: 'srq-one'));
      host.event('a', 'approval', approval('two', serverId: 'srq-two'));
      host.event('a', 'approval', approval('one', serverId: 'srq-replay'));
      expect(chat.approvals.requests, hasLength(2));
      expect(chat.approval?['server_request_id'], 'srq-replay');
      expect((chat.approvals.position, chat.approvals.total), (1, 2));
      expect(alerts, hasLength(2));
    },
  );

  test(
    'approval arriving during a response survives and keeps input status',
    () async {
      host.event('a', 'approval', approval('one'));
      host.approvalDelay = Completer<void>();
      final response = controller.approve(
        chat,
        'once',
        requestId: chat.approval!['request_id'] as String,
      );
      host.event('a', 'approval', approval('two'));
      await expectLater(
        controller.approve(
          chat,
          'once',
          requestId: chat.approval!['request_id'] as String,
        ),
        throwsStateError,
      );
      host.approvalDelay!.complete();
      await response;
      expect(chat.approval?['request_id'], 'two');
      expect((chat.approvals.position, chat.approvals.total), (2, 2));
      expect(chat.status, ProfileTurnStatus.attention);
      expect(chat.approvalResponding, isFalse);
    },
  );

  test('cancellation removes only its matching server request', () {
    host.event('a', 'approval', approval('one', serverId: 'srq-one'));
    host.event('a', 'approval', approval('two', serverId: 'srq-two'));
    host.event('a', 'request.cancel', {
      'id': 'unrelated',
      'method': 'approval',
    });
    expect(chat.approvals.requests, hasLength(2));
    host.event('a', 'request.cancel', {'id': 'srq-one', 'method': 'approval'});
    expect(chat.approval?['request_id'], 'two');
    expect(chat.status, ProfileTurnStatus.attention);
    host.event('a', 'request.cancel', {
      'id': 'srq-two',
      'method': 'approval',
      'reason': 'timeout',
    });
    expect(chat.approval, isNull);
    expect(chat.status, ProfileTurnStatus.running);
    expect(chat.error, contains('expired'));
  });

  test(
    'resume restores every pending approval and preserves live reply ownership',
    () async {
      host.pendingApprovals = [approval('one'), approval('two')];
      host.approvalOpenRequests = [
        {
          'method': 'approval',
          'id': 'srq-one',
          'params': {...approval('one'), 'session_id': chat.runtimeId},
        },
      ];
      await controller.openSession(chat.key);
      await Future<void>.delayed(Duration.zero);
      expect(chat.approvals.requests, hasLength(2));
      expect(chat.approval?['server_request_id'], 'srq-one');
      expect(chat.approvals.total, 2);
      expect(alerts, hasLength(2));
      // The next authoritative read must not clobber the live request metadata.
      await controller.openSession(chat.key);
      await Future<void>.delayed(Duration.zero);
      expect(chat.approval?['server_request_id'], 'srq-one');
      expect(alerts, hasLength(2));
    },
  );

  test(
    'response reads pending queue to recover an approval whose delivery was missed',
    () async {
      host.pendingApprovals = [approval('one'), approval('two')];
      host.event('a', 'approval', approval('one'));
      await controller.approve(
        chat,
        'once',
        requestId: chat.approval!['request_id'] as String,
      );
      expect(chat.approval?['request_id'], 'two');
      expect(chat.status, ProfileTurnStatus.attention);
      await controller.approve(
        chat,
        'deny',
        requestId: chat.approval!['request_id'] as String,
      );
      expect(chat.approval, isNull);
      expect(chat.status, ProfileTurnStatus.running);
    },
  );

  test('stale pending read cannot erase a newer live approval', () async {
    host.pendingApprovals = [];
    host.pendingApprovalDelay = Completer<void>();
    host.event('a', 'approval', approval('one'));
    final response = controller.approve(
      chat,
      'once',
      requestId: chat.approval!['request_id'] as String,
    );
    await Future<void>.delayed(Duration.zero);
    host.pendingApprovals = [approval('two')];
    host.event('a', 'approval', approval('two'));
    host.pendingApprovalDelay!.complete();
    await response;
    expect(chat.approval?['request_id'], 'two');
    expect(chat.status, ProfileTurnStatus.attention);
  });

  test('a failed response retains the whole queue for retry', () async {
    host.event('a', 'approval', approval('one'));
    host.event('a', 'approval', approval('two'));
    host.approvalFails = true;
    await expectLater(
      controller.approve(
        chat,
        'once',
        requestId: chat.approval!['request_id'] as String,
      ),
      throwsException,
    );
    expect(chat.approvals.requests.map((r) => r['request_id']), ['one', 'two']);
    expect(chat.approvalResponding, isFalse);
  });

  test('a stale button cannot approve the next command', () async {
    host.event('a', 'approval', approval('one', serverId: 'srq-one'));
    host.event('a', 'approval', approval('two'));
    host.event('a', 'request.cancel', {'id': 'srq-one', 'method': 'approval'});
    await expectLater(
      controller.approve(chat, 'once', requestId: 'one'),
      throwsStateError,
    );
    expect(chat.approval?['request_id'], 'two');
    expect(host.calls.where((c) => c.$2 == 'approval.respond'), isEmpty);
  });

  test('turn completion clears all pending approvals', () async {
    host.event('a', 'approval', approval('one'));
    host.event('a', 'approval', approval('two'));
    host.event('a', 'message.complete', {'text': 'Done'});
    await Future<void>.delayed(Duration.zero);
    expect(chat.approvals.requests, isEmpty);
    expect(chat.approvals.total, 0);
  });
}
