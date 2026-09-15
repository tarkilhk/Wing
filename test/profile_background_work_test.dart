import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_process.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/session_control.dart';
import 'package:wing/core/models/side_question_delivery.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

Map<String, dynamic> _process(String id, String status) => {
  'session_id': id,
  'command': 'python worker.py',
  'status': status,
  'output_tail': 'latest output',
  if (status == 'exited') 'exit_code': 0,
};

Map<String, dynamic> _controlResponse(String revision) => {
  'control': {
    'goal': null,
    'loop': null,
    'heartbeat': null,
    'revision': revision,
    'updated_at': 1,
  },
  'dispatch': {
    'type': 'exec',
    'output': null,
    'notice': null,
    'message': null,
    'display': null,
  },
};

class _BackgroundHost extends Host {
  Map<String, dynamic> listResponse = {'processes': <Object>[]};
  Map<String, dynamic> killResponse = {
    'status': 'killed',
    'session_id': 'bg-1',
  };
  Completer<Map<String, dynamic>>? pendingList;
  Completer<Map<String, dynamic>>? pendingKill;
  bool listFails = false;
  int controlRevision = 0;
  Object? sideTasks = const {'retention': 'live_session', 'tasks': <Object>[]};
  bool includeSideTasks = true;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return gateways[scope.profileName] = ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      close: base.close,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'process.list') {
          calls.add((scope.profileName, method, params));
          final pending = pendingList;
          if (pending != null) return pending.future;
          if (listFails) throw TimeoutException('list acknowledgement lost');
          return listResponse;
        }
        if (method == 'process.kill') {
          calls.add((scope.profileName, method, params));
          final pending = pendingKill;
          return pending?.future ?? killResponse;
        }
        if (method == 'session.control') {
          calls.add((scope.profileName, method, params));
          return _controlResponse('control-${++controlRevision}');
        }
        final result = await base.call(method, params);
        if (method == 'session.resume') {
          return {...result, if (includeSideTasks) 'side_tasks': sideTasks};
        }
        return result;
      },
    );
  }
}

void main() {
  late _BackgroundHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _BackgroundHost();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'background-work-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  test(
    'refresh is scoped and a stale read cannot replace a newer list',
    () async {
      final pending = host.pendingList = Completer<Map<String, dynamic>>();
      final stale = controller.refreshProcesses(chat);

      host.pendingList = null;
      host.listResponse = {
        'processes': [_process('new', 'running')],
      };
      await controller.refreshProcesses(chat);
      pending.complete({
        'processes': [_process('old', 'running')],
      });
      await stale;
      expect(chat.processes.single.id, 'new');
      expect(host.calls.where((call) => call.$2 == 'process.list').last.$3, {
        'session_id': 'a-runtime',
        'profile': 'a',
      });
    },
  );

  test(
    'malformed snapshot preserves confirmed processes and reports an error',
    () async {
      host.listResponse = {
        'processes': [
          {'session_id': 'live', 'status': 'running'},
        ],
      };
      await controller.refreshProcesses(chat);

      expect(chat.processes.single.id, 'live');
      expect(chat.processes.single.command, 'Background process');
      expect(chat.processesError, isNull);

      host.listResponse = {
        'processes': [
          {'status': 'running'},
        ],
      };
      await controller.refreshProcesses(chat);

      expect(chat.processes.single.id, 'live');
      expect(chat.processes.single.isRunning, isTrue);
      expect(chat.processesError, contains('could not be refreshed'));

      host.listResponse = {
        'processes': [
          {'session_id': 'new-live', 'status': 'running'},
          'not a process row',
        ],
      };
      await controller.refreshProcesses(chat);

      expect(chat.processes.single.id, 'live');
      expect(chat.processesError, contains('could not be refreshed'));
    },
  );

  test('session info authoritatively hydrates side-task history', () {
    chat.status = ProfileTurnStatus.idle;
    host.event('a', 'session.info', {
      'side_tasks': {
        'retention': 'live_session',
        'tasks': [
          {
            'task_id': 'running',
            'kind': 'background',
            'prompt': 'Check deployment',
            'prompt_truncated': false,
            'status': 'running',
            'result': null,
            'result_truncated': false,
          },
          {
            'task_id': 'answered',
            'kind': 'btw',
            'prompt': 'What changed?',
            'prompt_truncated': true,
            'status': 'completed',
            'result': 'The server changed.',
            'result_truncated': false,
          },
          {
            'task_id': 'failed',
            'kind': 'background',
            'prompt': 'Deploy',
            'prompt_truncated': false,
            'status': 'error',
            'result': 'Deployment failed.',
            'result_truncated': true,
          },
        ],
      },
    });

    expect(chat.sideQuestionDeliveries, hasLength(3));
    expect(
      chat.sideQuestionDeliveries[0].state,
      SideQuestionDeliveryState.pending,
    );
    expect(chat.sideQuestionDeliveries[1].questionTruncated, isTrue);
    expect(
      chat.sideQuestionDeliveries[2].state,
      SideQuestionDeliveryState.failed,
    );
    expect(chat.sideQuestionDeliveries[2].resultTruncated, isTrue);
    expect(chat.status, ProfileTurnStatus.idle);

    host.event('a', 'session.info', {'model': 'fixture-model'});
    expect(chat.sideQuestionDeliveries, hasLength(3));
  });

  test('resume restores tasks and malformed snapshots clear them', () async {
    host.sideTasks = {
      'retention': 'live_session',
      'tasks': [
        {
          'task_id': 'recovered',
          'kind': 'btw',
          'prompt': 'Recovered question',
          'prompt_truncated': false,
          'status': 'running',
          'result': null,
          'result_truncated': false,
        },
      ],
    };
    await controller.reconnect(chat.key.workspace);
    expect(chat.sideQuestionDeliveries.single.taskId, 'recovered');
    expect(chat.busy, isTrue);
    expect(chat.status, ProfileTurnStatus.running);

    host.sideTasks = const {'retention': 'live_session', 'tasks': <Object>[]};
    await controller.reconnect(chat.key.workspace);
    expect(chat.sideQuestionDeliveries, isEmpty);

    host.event('a', 'session.info', {
      'side_tasks': {'retention': 'wrong', 'tasks': <Object>[]},
    });
    expect(chat.sideQuestionDeliveries, isEmpty);
  });

  test(
    'same-runtime resume preserves side-task cards when the field is absent',
    () async {
      host.event('a', 'background.complete', {
        'task_id': 'live-task',
        'question': 'Check deployment',
        'text': 'Deployment complete.',
      });
      host.includeSideTasks = false;

      await controller.reconnect(chat.key.workspace);

      expect(chat.sideQuestionDeliveries.single.taskId, 'live-task');
      expect(
        chat.sideQuestionDeliveries.single.state,
        SideQuestionDeliveryState.completed,
      );
    },
  );

  test(
    'changed-runtime resume clears side-task cards when the field is absent',
    () async {
      host.event('a', 'background.complete', {
        'task_id': 'old-task',
        'question': 'Check deployment',
        'text': 'Deployment complete.',
      });
      host.includeSideTasks = false;
      host.running = false;
      chat.runtimeId = 'old-runtime';

      await controller.reconnect(chat.key.workspace);

      expect(chat.runtimeId, 'a-runtime');
      expect(chat.sideQuestionDeliveries, isEmpty);
    },
  );

  test(
    'stop validates the acknowledgement and refreshes the exited row',
    () async {
      host.listResponse = {
        'processes': [_process('bg-1', 'running')],
      };
      await controller.refreshProcesses(chat);
      host.listResponse = {
        'processes': [_process('bg-1', 'exited')],
      };

      expect(await controller.stopProcess(chat, 'bg-1'), isTrue);
      expect(chat.processes.single.status, GatewayProcessStatus.exited);
      expect(host.calls.where((call) => call.$2 == 'process.kill').single.$3, {
        'session_id': 'a-runtime',
        'process_id': 'bg-1',
        'profile': 'a',
      });

      host.listResponse = {
        'processes': [_process('bg-1', 'running')],
      };
      await controller.refreshProcesses(chat);
      host.killResponse = {'status': 'error', 'session_id': 'bg-1'};
      expect(await controller.stopProcess(chat, 'bg-1'), isFalse);
      expect(chat.processes.single.isRunning, isTrue);
      expect(chat.processesError, contains('did not confirm'));

      host.killResponse = {'status': 'already_exited', 'exit_code': 0};
      host.listResponse = {
        'processes': [_process('bg-1', 'exited')],
      };
      expect(await controller.stopProcess(chat, 'bg-1'), isTrue);

      host.listResponse = {
        'processes': [_process('bg-1', 'running')],
      };
      await controller.refreshProcesses(chat);
      host.killResponse = {
        'status': 'already_exited',
        'session_id': 'another-process',
      };
      expect(await controller.stopProcess(chat, 'bg-1'), isFalse);
    },
  );

  test(
    'stop is single-flight, survives a list refresh, and stays scoped',
    () async {
      host.listResponse = {
        'processes': [_process('bg-1', 'running')],
      };
      await controller.refreshProcesses(chat);
      final pending = host.pendingKill = Completer<Map<String, dynamic>>();
      final first = controller.stopProcess(chat, 'bg-1');
      expect(await controller.stopProcess(chat, 'bg-1'), isFalse);

      await controller.refreshProcesses(chat);
      host.listResponse = {
        'processes': [_process('bg-1', 'exited')],
      };
      pending.complete({'status': 'killed', 'session_id': 'bg-1'});
      expect(await first, isTrue);

      host.listResponse = {
        'processes': [_process('bg-1', 'running')],
      };
      await controller.refreshProcesses(chat);
      final scopedPending = host.pendingKill =
          Completer<Map<String, dynamic>>();
      final scoped = controller.stopProcess(chat, 'bg-1');

      chat.runtimeId = 'replacement-runtime';
      scopedPending.complete({'status': 'killed', 'session_id': 'bg-1'});
      expect(await scoped, isFalse);
    },
  );

  test(
    'dismissed exited rows stay hidden only while the server reports them',
    () async {
      host.listResponse = {
        'processes': [_process('done', 'exited'), _process('live', 'running')],
      };
      await controller.refreshProcesses(chat);
      controller.dismissProcess(chat, 'live');
      expect(chat.processes.map((item) => item.id), contains('live'));

      controller.dismissProcess(chat, 'done');
      expect(chat.processes.map((item) => item.id), isNot(contains('done')));
      await controller.refreshProcesses(chat);
      expect(chat.processes.map((item) => item.id), isNot(contains('done')));

      host.listResponse = {'processes': <Object>[]};
      await controller.refreshProcesses(chat);
      host.listResponse = {
        'processes': [_process('done', 'exited')],
      };
      await controller.refreshProcesses(chat);
      expect(chat.processes.single.id, 'done');
    },
  );

  test('acknowledged stop reports a failed authoritative refresh', () async {
    host.listResponse = {
      'processes': [_process('bg-1', 'running')],
    };
    await controller.refreshProcesses(chat);
    host.listFails = true;

    expect(await controller.stopProcess(chat, 'bg-1'), isTrue);
    expect(chat.processes.single.isRunning, isTrue);
    expect(chat.processesError, contains('acknowledged'));
  });

  test(
    'loop and heartbeat actions use the shared scoped control RPC',
    () async {
      expect(
        await controller.controlSession(chat, SessionControlAction.loopPause),
        isTrue,
      );
      expect(
        await controller.controlSession(
          chat,
          SessionControlAction.heartbeatClear,
        ),
        isTrue,
      );
      final actions = host.calls
          .where((call) => call.$2 == 'session.control')
          .map((call) => call.$3['action']);
      expect(actions, ['loop.pause', 'heartbeat.clear']);
      expect(chat.sessionControlNotice, 'Session controls updated.');
    },
  );
}
