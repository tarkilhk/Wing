import 'dart:async';
import 'dart:convert';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/profile_gateway.dart';

class AdministrationFixture {
  final String id;
  final rpcRequests = <(String, String)>[];
  final requests =
      <(String, String, Map<String, String>, Map<String, dynamic>?)>[];
  final configs = <String, Map<String, dynamic>>{
    'default': {
      'memory': {'memory_enabled': true, 'memory_char_limit': 1500},
    },
    'personal': {
      'memory': {'memory_enabled': true, 'memory_char_limit': 2000},
      'agent': {'max_turns': 20},
      'unrelated': {'keep': true},
    },
    'work': {
      'memory': {'memory_enabled': false, 'memory_char_limit': 3000},
    },
  };
  Map<String, dynamic> updateCheck = {
    'current_version': '1.2.3',
    'install_method': 'git',
    'behind': 3,
    'update_available': true,
    'can_apply': true,
    'commits': [
      {
        'summary': 'Keep scheduled tasks running after reconnecting',
        'sha': 'abc1234',
        'author': 'Example contributor',
        'at': 1789646400,
      },
      {
        'summary':
            'Improve tool discovery for profiles with their own connectors',
        'sha': 'def5678',
        'author': 'Another contributor',
        'at': 1789560000,
      },
    ],
  };
  bool reject = false;
  bool ignoreSave = false;
  bool rootIsDefault = true;
  bool failReads = false;
  Completer<void>? writeGate;
  AdministrationRequest? override;
  late final AdministrationRepository server = AdministrationRepository(
    connectionId: id,
    connectionIdentity: '$id-endpoint',
    connectionLabel: id,
    request: send,
    gateway: (name) => ProfileGateway(
      scope: WorkspaceScope(connectionId: id, profileName: name),
      get: (path, query) => send('GET', path, query, null),
      put: (path, body) => send(
        'PUT',
        Uri.parse(path).path,
        Uri.parse(path).queryParameters,
        body,
      ),
      rpc: (method, params) async {
        rpcRequests.add((name, method));
        return {
          'plugins': [],
          'servers': [],
          if (method == 'reload.mcp') 'status': 'reloaded',
        };
      },
      discover: () => server.discover(),
    ),
  );
  AdministrationFixture([this.id = 'Server A']);
  Future<Map<String, dynamic>> send(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic>? body,
  ) async {
    requests.add((method, path, {...query}, body == null ? null : {...body}));
    if (override != null) return override!(method, path, query, body);
    if (method == 'GET' && failReads) throw StateError('Offline');
    if (path == 'health') {
      return {'ok': true, 'version': updateCheck['current_version']};
    }
    if (path == 'hermes/update/check') return updateCheck;
    if (path == 'profiles') {
      return {
        'profiles': [
          for (final name in configs.keys)
            {
              'name': name,
              'is_default': name == 'default' && rootIsDefault,
              'display_name': name == 'default' ? 'Shared root' : name,
            },
        ],
      };
    }
    if (path == 'profiles/active') {
      return {'current': 'default', 'active': 'work'};
    }
    final name = query['profile'];
    if (path == 'config') {
      if (method == 'PUT') {
        if (writeGate != null) await writeGate!.future;
        if (reject) return {'ok': false};
        if (!ignoreSave) _merge(configs[name]!, body!['config'] as Map);
        return {'ok': true};
      }
      return jsonDecode(jsonEncode(configs[name])) as Map<String, dynamic>;
    }
    if (path == 'config/schema') {
      return {
        'fields': {
          'memory.memory_enabled': {'type': 'boolean'},
          'memory.memory_char_limit': {'type': 'number'},
        },
      };
    }
    if (path == 'learning/graph') return {'memory': [], 'nodes': []};
    if (path == 'model/info') {
      return {'provider': 'Example provider', 'model': 'Research model'};
    }
    if (path == 'tools/toolsets') return {'data': []};
    if (path == 'cron/jobs') return {'data': []};
    if (path == 'mcp/servers') return {'servers': []};
    if (path == 'skills') return {'data': []};
    if (path == 'providers/oauth') return {'providers': []};
    if (path == 'env') return {};
    throw StateError('Unexpected $method $path');
  }

  void _merge(Map target, Map patch) {
    for (final key in patch.keys) {
      if (target[key] is Map && patch[key] is Map) {
        _merge(target[key] as Map, patch[key] as Map);
      } else {
        target[key] = patch[key];
      }
    }
  }
}
