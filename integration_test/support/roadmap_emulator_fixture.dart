import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/ws_client.dart';

import '../../test/support/profile_history_fixture.dart';

/// In-memory gateway data for the roadmap emulator suite.
///
/// Every transport boundary is replaced. The widgets and workspace controller
/// are the production implementations, but this fixture cannot reach a Hermes
/// host or submit work to a model.
class RoadmapEmulatorFixture extends ProfileHistoryFixture {
  final gateways = <String, ProfileGateway>{};
  final configWrites = <Map<String, dynamic>>[];
  final approvalResponses = <Map<String, dynamic>>[];
  final commandDispatches = <Map<String, dynamic>>[];
  final projectCreates = <Map<String, dynamic>>[];
  final projectUpdates = <Map<String, dynamic>>[];
  final projectDeletes = <Map<String, dynamic>>[];
  final sensitiveResponses = <Map<String, dynamic>>[];
  final supervisionRequests = <(String, Map<String, dynamic>)>[];
  final administrationReads = <(String, Map<String, String>)>[];
  final administrationRequests = <(String, Map<String, dynamic>)>[];
  final profileConfigureRequests = <Map<String, dynamic>>[];
  final backendUpdatePosts = <(String, Map<String, dynamic>)>[];
  final answerActionRequests = <(String, Map<String, dynamic>)>[];
  final createdProjects = <String, List<Map<String, dynamic>>>{};
  final answerHistories = <String, List<Map<String, dynamic>>>{};
  final answerParents = <String, String>{};
  final answerRuntimes = <String, String>{};
  String goalStatus = 'active';
  String loopStatus = 'active';
  bool runningProcess = true;
  String profileDescription = 'Roadmap profile';
  String profileSoul = 'Be exact.';
  int updateCheckCount = 0;
  bool updateAvailable = true;
  bool answerActionsEnabled = false;
  bool supervisionEnabled = false;
  int _nextAnswerChild = 0;
  int _nextAnswerRow = 1000;

  @override
  List<Map<String, dynamic>> projects(String profile) => [
    ...super.projects(profile),
    ...createdProjects[profile] ?? const [],
  ];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) =>
      answerActionsEnabled
      ? _answerHistory(profile, id)
      : [
          for (var i = 1; i <= messageCount; i++)
            {
              'id': i,
              'role': i.isEven ? 'assistant' : 'user',
              'content': i == 618
                  ? 'Roadmap needle: the emulator found this saved answer.'
                  : i == 616
                  ? 'Saved /tmp/roadmap-notes.md for the emulator review.'
                  : '$profile message $i',
              'display_content': i == 618
                  ? 'Roadmap needle: the emulator found this saved answer.'
                  : i == 616
                  ? 'Saved /tmp/roadmap-notes.md for the emulator review.'
                  : '$profile message $i',
            },
        ];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    late final ProfileGateway fixtureGateway;
    fixtureGateway = ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      close: base.close,
      get: (path, query) async {
        if (path == 'analytics/models') {
          administrationReads.add((path, Map<String, String>.from(query)));
          return {
            'models': const [
              {
                'model': 'openai-codex/gpt-6-astra',
                'provider': 'openai-codex',
                'sessions': 12,
                'api_calls': 34,
                'input_tokens': 5600,
                'output_tokens': 780,
                'estimated_cost': 1.25,
              },
              {'model': 'local/missing-cost', 'sessions': 1},
            ],
          };
        }
        if (path == 'hermes/update/check') {
          administrationReads.add((path, Map<String, String>.from(query)));
          updateCheckCount++;
          return {
            'current_version': '1.2.3',
            'install_method': 'pipx',
            'behind': updateAvailable ? 2 : 0,
            'update_available': updateAvailable,
            'can_apply': true,
          };
        }
        if (path == 'health') {
          return {'ok': true, 'version': '1.2.3'};
        }
        if (path == 'model/info') {
          return {'model': 'gpt-6-astra', 'provider': 'openai-codex'};
        }
        if (path == 'model/options') {
          return {
            'providers': [
              {
                'slug': 'openai-codex',
                'name': 'OpenAI subscription',
                'models': ['gpt-6-astra', 'gpt-5.6-sol'],
              },
            ],
          };
        }
        return base.read(path, query);
      },
      patch: (path, body) async {
        if (!path.startsWith('sessions/') || body['unread'] != false) {
          throw StateError('Unexpected journey mutation: $path');
        }
        return {'ok': true, ...body};
      },
      post: (path, body) async {
        backendUpdatePosts.add((path, Map<String, dynamic>.from(body)));
        return {
          'ok': true,
          'name': 'hermes-update',
          'pid': 4242,
          'action_id': 'roadmap-update',
        };
      },
      rpc: (method, params) async {
        switch (method) {
          case 'setup.status':
            administrationRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            return {'provider_configured': false};
          case 'setup.runtime_check':
            administrationRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            throw StateError('private roadmap runtime detail');
          case 'profiles.describe':
            administrationRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            return {
              'name': scope.profileName,
              'description': profileDescription,
              'soul': profileSoul,
              'skills': const [],
              'toolsets': const [],
            };
          case 'profiles.configure':
            administrationRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            profileConfigureRequests.add(Map<String, dynamic>.from(params));
            if (params['description'] case final String description) {
              profileDescription = description.trim();
            }
            return {
              'ok': false,
              'applied': const {'description': true, 'soul': false},
            };
          case 'session.context_breakdown':
            return {
              'context_used': 32768,
              'context_max': 131072,
              'context_percent': 25,
            };
          case 'config.get':
            return {'value': 'high'};
          case 'config.set':
            configWrites.add(Map<String, dynamic>.from(params));
            return {'status': 'ok'};
          case 'commands.catalog':
            return {
              'pairs': [
                ['/roadmap-check', 'Run the isolated roadmap check'],
              ],
              'canon': <String, String>{},
              'categories': [
                {
                  'name': 'Checks',
                  'pairs': [
                    ['/roadmap-check', 'Run the isolated roadmap check'],
                  ],
                },
              ],
            };
          case 'complete.slash':
            return {'items': <Map<String, dynamic>>[], 'replace_from': 0};
          case 'command.dispatch':
            commandDispatches.add(Map<String, dynamic>.from(params));
            return {
              'type': 'exec',
              'output': 'Roadmap fixture command complete',
            };
          case 'approval.respond':
            approvalResponses.add(Map<String, dynamic>.from(params));
            return {'status': 'ok'};
          case 'projects.discover_repos':
            return {
              'repos': const [
                {'root': '/srv/wing', 'label': 'Wing'},
              ],
            };
          case 'projects.create':
            projectCreates.add(Map<String, dynamic>.from(params));
            createdProjects.putIfAbsent(scope.profileName, () => []).add({
              'id': 'roadmap-created',
              'name': params['name'],
              'label': params['name'],
              'path': params['primary_path'],
              'lastActive': now + 1,
            });
            return {
              'project': {'id': 'roadmap-created'},
            };
          case 'projects.update':
            projectUpdates.add(Map<String, dynamic>.from(params));
            final project = createdProjects[scope.profileName]!.singleWhere(
              (project) => project['id'] == params['id'],
            );
            if (params.containsKey('name')) {
              project['name'] = params['name'];
              project['label'] = params['name'];
            }
            return {'project': Map<String, dynamic>.from(project)};
          case 'projects.delete':
            projectDeletes.add(Map<String, dynamic>.from(params));
            createdProjects[scope.profileName]!.removeWhere(
              (project) => project['id'] == params['id'],
            );
            return {'projects': projects(scope.profileName), 'active_id': null};
          case 'request.answer':
            sensitiveResponses.add(Map<String, dynamic>.from(params));
            return {'status': 'ok'};
          case 'subagent.list':
            supervisionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            return {
              'subagents': const [
                {
                  'subagent_id': 'roadmap-child',
                  'goal': 'Inspect the emulator release',
                  'status': 'running',
                  'model': 'gpt-5.6-sol',
                  'last_tool': 'read_file',
                  'accepting_steer': true,
                },
              ],
              'delegations': const [],
            };
          case 'subagent.tail':
            supervisionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            return {
              'subagent_id': 'roadmap-child',
              'available': true,
              'text': 'Emulator child is checking the release.',
              'truncated': false,
            };
          case 'subagent.steer':
            supervisionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            return {'status': 'queued', 'subagent_id': params['subagent_id']};
          case 'session.control.read':
            supervisionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            return {'control': _sessionControl};
          case 'session.control':
            supervisionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            if (params['action'] == 'goal.pause') goalStatus = 'paused';
            if (params['action'] == 'loop.pause') loopStatus = 'paused';
            return {
              'control': _sessionControl,
              'dispatch': const {
                'type': 'exec',
                'output': 'Roadmap supervision updated.',
                'notice': null,
                'message': null,
                'display': null,
              },
            };
          case 'process.list':
            supervisionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            return {
              'processes': [
                if (runningProcess)
                  const {
                    'session_id': 'roadmap-process-running',
                    'command': 'dart run roadmap_worker.dart',
                    'status': 'running',
                    'pid': 4242,
                  },
                const {
                  'session_id': 'roadmap-process-finished',
                  'command': 'dart test roadmap_check.dart',
                  'status': 'exited',
                  'exit_code': 0,
                },
              ],
            };
          case 'process.kill':
            supervisionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            runningProcess = false;
            return {'status': 'killed', 'session_id': params['process_id']};
          case 'session.branch' when answerActionsEnabled:
            answerActionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            final source = answerRuntimes[params['session_id']]!;
            final child = 'roadmap-branch-${++_nextAnswerChild}';
            final copied = _answerHistory(scope.profileName, source)
                .take(params['count'] as int)
                .map((row) => Map<String, dynamic>.from(row))
                .toList();
            for (final row in copied) {
              row['id'] = ++_nextAnswerRow;
            }
            answerHistories['${scope.profileName}/$child'] = copied;
            answerParents[child] = source;
            final runtime = 'runtime-$child';
            answerRuntimes[runtime] = child;
            return {
              'session_id': runtime,
              'stored_session_id': child,
              'parent': source,
              'parent_session_id': source,
              'title': 'Roadmap branch $_nextAnswerChild',
              'messages': _answerRpcRows(copied),
              'info': {'profile_name': scope.profileName},
            };
          case 'session.history' when answerActionsEnabled:
            final id = answerRuntimes[params['session_id']]!;
            return {
              'messages': _answerRpcRows(_answerHistory(scope.profileName, id)),
            };
          case 'prompt.submit' when answerActionsEnabled:
            answerActionRequests.add((
              method,
              Map<String, dynamic>.from(params),
            ));
            final id = answerRuntimes[params['session_id']]!;
            final rows = _answerHistory(scope.profileName, id);
            final truncateBefore = params['truncate_before_row_id'];
            if (truncateBefore != null) {
              final index = rows.indexWhere(
                (row) => row['id'] == truncateBefore,
              );
              rows.removeRange(index, rows.length);
            }
            rows.add({
              'id': ++_nextAnswerRow,
              'role': 'user',
              'content': params['text'],
              'display_content': params['text'],
            });
            rows.add({
              'id': ++_nextAnswerRow,
              'role': 'assistant',
              'content': 'Acknowledged ${params['text']}',
              'display_content': 'Acknowledged ${params['text']}',
            });
            return {'status': 'streaming'};
          case 'session.resume':
          case 'session.create':
            if (answerActionsEnabled && method == 'session.resume') {
              final id = params['session_id'] as String;
              final runtime = 'runtime-$id';
              answerRuntimes[runtime] = id;
              return {
                'session_id': runtime,
                'stored_session_id': id,
                if (answerParents.containsKey(id))
                  'parent_session_id': answerParents[id],
                'messages': _answerRpcRows(
                  _answerHistory(scope.profileName, id),
                ),
                'info': {
                  'profile_name': scope.profileName,
                  'model': 'gpt-6-astra',
                  'provider': 'openai-codex',
                  'reasoning_effort': 'high',
                },
              };
            }
            final response = await base.call(method, params);
            return {
              ...response,
              'info': {
                'profile_name': scope.profileName,
                'model': 'gpt-6-astra',
                'provider': 'openai-codex',
                'reasoning_effort': 'high',
              },
            };
          default:
            return base.call(method, params);
        }
      },
    );
    gateways[scope.profileName] = fixtureGateway;
    return fixtureGateway;
  }

  void enableAnswerActions() {
    answerActionsEnabled = true;
    answerRuntimes['runtime-chat-0'] = 'chat-0';
  }

  List<Map<String, dynamic>> _answerHistory(String profile, String id) =>
      answerHistories.putIfAbsent(
        '$profile/$id',
        () => [
          {
            'id': 1,
            'role': 'user',
            'content': 'Original emulator prompt',
            'display_content': 'Original emulator prompt',
          },
          {
            'id': 2,
            'role': 'assistant',
            'content': 'Original emulator answer',
            'display_content': 'Original emulator answer',
          },
          {
            'id': 3,
            'role': 'user',
            'content': 'Latest emulator prompt',
            'display_content': 'Latest emulator prompt',
          },
          {
            'id': 4,
            'role': 'assistant',
            'content': 'Latest emulator answer',
            'display_content': 'Latest emulator answer',
          },
        ],
      );

  List<Map<String, dynamic>> _answerRpcRows(List<Map<String, dynamic>> rows) =>
      rows.map((row) {
        final rpc = Map<String, dynamic>.from(row);
        rpc['row_id'] = rpc.remove('id');
        return rpc;
      }).toList();

  void completeAnswerAction(String profile, String runtimeId) {
    gateways[profile]!.onEvent!(
      StreamEvent(
        type: 'message.complete',
        sessionId: runtimeId,
        data: const {},
      ),
    );
  }

  Map<String, dynamic> get _sessionControl => !supervisionEnabled
      ? {
          'goal': null,
          'loop': null,
          'heartbeat': null,
          'revision': 'roadmap-empty-control',
          'updated_at': 1,
        }
      : {
          'goal': {
            'title': 'Verify the emulator roadmap',
            'status': goalStatus,
            'turns_used': 2,
            'max_turns': 8,
            'contract': const {
              'outcome': 'Verify the client',
              'verification': 'Recorded checks pass',
              'constraints': 'Local fixtures',
              'boundaries': 'Android client',
              'stop_when': 'Checks complete',
            },
            'subgoals': const ['Run the isolated checks'],
            'gates': const [],
          },
          'loop': {
            'prompt': 'Check the release queue',
            'status': loopStatus,
            'mode': 'interval',
            'interval_seconds': 300,
            'current_delay': 300,
            'times': 4,
            'until': '',
            'max_ticks': 0,
            'ticks_fired': 2,
            'created_at': 1,
            'last_fired_at': 2,
            'next_due_at': 1893456000,
            'awaiting_response': false,
            'deferred_by_goal': true,
          },
          'heartbeat': const {
            'prompt': 'Report emulator health',
            'status': 'active',
            'interval_seconds': 900,
            'created_at': 1,
            'last_fired_at': 2,
            'fire_count': 3,
          },
          'revision': 'roadmap-supervision-revision',
          'updated_at': 3,
        };

  void requestApproval(String profile, String runtimeId) {
    gateways[profile]!.onEvent!(
      StreamEvent(
        type: 'approval.request',
        sessionId: runtimeId,
        data: const {
          'request_id': 'roadmap-approval',
          'command': 'echo isolated-roadmap-check',
          'choices': ['once', 'session', 'deny'],
        },
      ),
    );
  }

  void deliverReview(String profile, String runtimeId) {
    gateways[profile]!.onEvent!(
      StreamEvent(
        type: 'review.summary',
        sessionId: runtimeId,
        data: const {'text': 'Roadmap review needs a human check.'},
      ),
    );
  }

  void requestVaultUnlock(String profile, String runtimeId) {
    gateways[profile]!.onEvent!(
      StreamEvent(
        type: 'vault.unlock_prompt',
        sessionId: runtimeId,
        data: const {
          'request_id': 'roadmap-vault-unlock',
          'backend': 'roadmap-vault',
          'display_name': 'Roadmap Vault',
        },
      ),
    );
  }
}

class RoadmapMemoryCredentialStore implements CredentialStore {
  final _values = <String, String>{};
  final _cache = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = _values[key];
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
    _cache[key] = value;
  }
}
