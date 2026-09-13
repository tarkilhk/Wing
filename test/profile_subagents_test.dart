import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

class _SubagentHost extends Host {
  Map<String, dynamic> listResponse = {'subagents': <Map<String, dynamic>>[]};
  Map<String, dynamic> tailResponse = {
    'subagent_id': 'child',
    'available': true,
    'text': 'tail',
    'truncated': false,
  };
  Map<String, dynamic> steerResponse = {
    'status': 'queued',
    'subagent_id': 'child',
  };
  Map<String, dynamic> interruptResponse = {
    'found': true,
    'subagent_id': 'child',
  };
  Completer<Map<String, dynamic>>? pendingList;
  Completer<Map<String, dynamic>>? pendingTail;
  Completer<Map<String, dynamic>>? pendingControl;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return gateways[scope.profileName] = ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      close: base.close,
      get: base.read,
      rpc: (method, params) {
        if (method.startsWith('subagent.')) {
          calls.add((scope.profileName, method, params));
          return switch (method) {
            'subagent.list' =>
              pendingList?.future ?? Future.value(listResponse),
            'subagent.tail' =>
              pendingTail?.future ?? Future.value(tailResponse),
            'subagent.steer' || 'subagent.interrupt' =>
              pendingControl?.future ??
                  Future.value(
                    method == 'subagent.steer'
                        ? steerResponse
                        : interruptResponse,
                  ),
            _ => Future.value(<String, dynamic>{}),
          };
        }
        return base.call(method, params);
      },
    );
  }
}

void main() {
  late _SubagentHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _SubagentHost();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'subagent-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  test('events merge sparse updates and normalize terminal status', () {
    host.event('a', 'subagent.start', {
      'subagent_id': 'child',
      'goal': 'Inspect transport',
      'accepting_steer': true,
    });
    host.event('a', 'subagent.tool', {
      'subagent_id': 'child',
      'tool_name': 'read_file',
    });

    expect(chat.subagents.single.goal, 'Inspect transport');
    expect(chat.subagents.single.lastTool, 'read_file');
    expect(chat.subagents.single.acceptingSteer, isTrue);

    host.event('a', 'subagent.complete', {
      'subagent_id': 'child',
      'status': 'timeout',
      'summary': 'Timed out',
    });
    expect(chat.subagents.single.status, GatewaySubagentStatus.failed);
    expect(chat.subagents.single.isTerminal, isTrue);

    host.event('a', 'subagent.progress', {'text': 'missing owner'});
    expect(chat.subagents, hasLength(1));
  });

  test(
    'partial snapshot keeps known children and uses the parent runtime',
    () async {
      host.event('a', 'subagent.complete', {
        'subagent_id': 'done',
        'goal': 'Finished task',
        'status': 'completed',
      });
      host.event('a', 'subagent.start', {
        'subagent_id': 'stale',
        'goal': 'No longer active',
      });
      host.listResponse = {
        'subagents': [
          {
            'subagent_id': 'active',
            'parent_id': 'root',
            'depth': 1,
            'goal': 'Current task',
            'delegation_id': 'batch',
            'model': 'model-a',
            'status': 'running',
            'started_at': 12.5,
            'tool_count': 3,
            'last_tool': 'search',
            'accepting_steer': true,
          },
        ],
        'delegations': <Object>[],
      };

      await controller.refreshSubagents(chat);

      expect(chat.subagents.map((item) => item.id), [
        'done',
        'stale',
        'active',
      ]);
      final active = chat.subagents.last;
      expect(chat.unconfirmedSubagentIds, {'stale'});
      expect(active.parentId, 'root');
      expect(active.delegationId, 'batch');
      expect(active.acceptingSteer, isTrue);
      expect(host.calls.last.$2, 'subagent.list');
      expect(host.calls.last.$3, {'session_id': 'a-runtime', 'profile': 'a'});
    },
  );

  test(
    'malformed snapshot preserves confirmed active rows and reports an error',
    () async {
      host.listResponse = {
        'subagents': [
          {'subagent_id': 'child'},
        ],
      };
      await controller.refreshSubagents(chat);

      expect(chat.subagents.single.id, 'child');
      expect(chat.subagents.single.status, GatewaySubagentStatus.running);
      expect(chat.subagentsError, isNull);

      host.listResponse = {
        'subagents': [
          {'goal': 'Malformed row without a subagent identity'},
        ],
      };
      await controller.refreshSubagents(chat);

      expect(chat.subagents.single.id, 'child');
      expect(chat.subagents.single.status, GatewaySubagentStatus.running);
      expect(chat.subagentsError, contains('could not be refreshed'));

      host.listResponse = {
        'subagents': [
          {'subagent_id': 'new-child'},
          'not a subagent row',
        ],
      };
      await controller.refreshSubagents(chat);

      expect(chat.subagents.single.id, 'child');
      expect(chat.subagentsError, contains('could not be refreshed'));
    },
  );

  test(
    'list rejects newer events while tail ignores unrelated progress',
    () async {
      host.pendingList = Completer<Map<String, dynamic>>();
      final list = controller.refreshSubagents(chat);
      host.event('a', 'subagent.start', {
        'subagent_id': 'child',
        'goal': 'Live child',
      });
      host.pendingList!.complete({
        'subagents': [
          {'subagent_id': 'old', 'goal': 'Old child', 'status': 'running'},
        ],
      });
      await list;
      expect(chat.subagents.map((item) => item.id), ['child']);

      host.pendingTail = Completer<Map<String, dynamic>>();
      final tail = controller.loadSubagentTail(chat, 'child');
      host.event('a', 'subagent.progress', {
        'subagent_id': 'other',
        'text': 'Unrelated progress',
      });
      host.pendingTail!.complete({
        'subagent_id': 'child',
        'available': true,
        'text': 'older tail',
        'truncated': false,
      });
      expect((await tail)?.text, 'older tail');

      host.pendingTail = Completer<Map<String, dynamic>>();
      final staleTail = controller.loadSubagentTail(chat, 'child');
      host.event('a', 'subagent.complete', {
        'subagent_id': 'child',
        'status': 'completed',
      });
      host.pendingTail!.complete({
        'subagent_id': 'child',
        'available': true,
        'text': 'pre-completion tail',
        'truncated': false,
      });
      expect(await staleTail, isNull);
    },
  );

  test(
    'completion before interrupt acknowledgement preserves acceptance',
    () async {
      host.event('a', 'subagent.start', {'subagent_id': 'child'});
      host.pendingControl = Completer<Map<String, dynamic>>();
      final interrupt = controller.interruptSubagent(chat, 'child');
      host.event('a', 'subagent.complete', {
        'subagent_id': 'child',
        'status': 'interrupted',
      });
      host.pendingControl!.complete({'found': true, 'subagent_id': 'child'});
      expect(await interrupt, isTrue);
      expect(chat.subagents.single.status, GatewaySubagentStatus.interrupted);
    },
  );

  test(
    'missing children recover on fresh events and settle only on completion',
    () async {
      host.event('a', 'subagent.start', {
        'subagent_id': 'child',
        'goal': 'Research',
      });
      await controller.refreshSubagents(chat);
      expect(chat.subagents.single.isTerminal, isFalse);
      expect(chat.unconfirmedSubagentIds, {'child'});
      host.event('a', 'subagent.tool', {
        'subagent_id': 'child',
        'tool_name': 'browser_snapshot',
      });
      expect(chat.unconfirmedSubagentIds, isEmpty);
      expect(chat.subagents.single.lastTool, 'browser_snapshot');
      await controller.refreshSubagents(chat);
      expect(chat.unconfirmedSubagentIds, {'child'});
      host.event('a', 'subagent.complete', {
        'subagent_id': 'child',
        'status': 'completed',
        'summary': 'Research saved',
      });
      expect(chat.unconfirmedSubagentIds, isEmpty);
      expect(chat.subagents.single.isTerminal, isTrue);
      expect(chat.subagents.single.recentActivity.last, 'Research saved');
    },
  );

  test(
    'recent activity keeps bounded tool previews and server output tails',
    () async {
      for (var index = 0; index < 45; index++) {
        host.event('a', 'subagent.progress', {
          'subagent_id': 'child',
          'text': 'Progress $index',
        });
      }
      host.event('a', 'subagent.tool', {
        'subagent_id': 'child',
        'tool_name': 'read_file',
        'tool_preview': 'Checking build.gradle',
        'output_tail': [
          {'tool': 'browser_snapshot', 'preview': 'Found the booking page'},
        ],
      });
      expect(
        chat.subagents.single.recentActivity,
        hasLength(GatewaySubagentActivity.maxRecentActivity),
      );
      expect(
        chat.subagents.single.recentActivity,
        contains('Tool: browser_snapshot · Found the booking page'),
      );
      expect(
        chat.subagents.single.recentActivity.last,
        'Tool: read_file · Checking build.gradle',
      );
      final before = chat.subagents.single.recentActivity;
      host.listResponse = {
        'subagents': [
          {
            'subagent_id': 'child',
            'last_tool': 'read_file',
            'status': 'running',
          },
        ],
      };
      await controller.refreshSubagents(chat);
      expect(chat.subagents.single.recentActivity, before);
    },
  );

  test('controls stay scoped and accept only exact acknowledgements', () async {
    host.event('a', 'subagent.start', {
      'subagent_id': 'child',
      'goal': 'Owned child',
    });
    host.tailResponse = {
      'subagent_id': 'child',
      'available': true,
      'text': List.filled(GatewaySubagentTail.maxTextLength + 8, 'x').join(),
      'truncated': false,
    };
    final clipped = await controller.loadSubagentTail(chat, 'child');
    expect(clipped!.text, hasLength(GatewaySubagentTail.maxTextLength));
    expect(clipped.truncated, isTrue);

    expect(await controller.steerSubagent(chat, 'child', ' redirect '), isTrue);
    expect(host.calls.last.$3, {
      'session_id': 'a-runtime',
      'subagent_id': 'child',
      'text': 'redirect',
      'profile': 'a',
    });

    host.steerResponse = {'status': 'rejected'};
    expect(await controller.steerSubagent(chat, 'child', 'again'), isFalse);
    host.interruptResponse = {'found': true, 'subagent_id': 'other'};
    expect(await controller.interruptSubagent(chat, 'child'), isFalse);

    host.pendingControl = Completer<Map<String, dynamic>>();
    final scoped = controller.steerSubagent(chat, 'child', 'scoped');
    await controller.switchProfile('b');
    host.pendingControl!.complete({'status': 'queued', 'subagent_id': 'child'});
    expect(await scoped, isTrue);
    expect(host.calls.lastWhere((call) => call.$2 == 'subagent.steer').$1, 'a');

    host.pendingControl = Completer<Map<String, dynamic>>();
    final late = controller.steerSubagent(chat, 'child', 'late');
    chat.runtimeId = 'replacement-runtime';
    host.pendingControl!.complete({'status': 'queued', 'subagent_id': 'child'});
    expect(await late, isFalse);
    expect(host.calls.last.$1, 'a');
  });
}
