import 'dart:async';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'profile_browser_fixture.dart';

class ProfileActionsFixture extends ProfileBrowserFixture {
  final updates = <(String, String, Map<String, dynamic>)>[];
  final deletes = <(String, Map<String, String>)>[];
  final moves = <(String, Map<String, dynamic>)>[];
  final closes = <(String, Map<String, dynamic>)>[];
  final changes = <String, Map<String, Map<String, dynamic>>>{};
  final removed = <String, Set<String>>{};
  bool failMutation = false;
  bool active = false;
  String activeSessionKey = 'newest';
  String? activeStatus = 'idle';
  String? statusAfterResume;
  String? resumeProfile;
  String resumeSessionId = 'newest';
  bool reuseLiveResume = false;
  Map<String, dynamic> resumeOverrides = {};
  bool failClose = false;
  bool acknowledgeClose = true;
  bool foreignActive = false;
  Completer<void>? mutationDelay;
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (final row in super.sessions(profile))
      if (!(removed[profile]?.contains(row['id']) ?? false))
        {...row, ...?changes[profile]?[row['id']]},
  ];
  @override
  List<Map<String, dynamic>> projectSessions(String profile, String id) => [
    for (final row in sessions(profile))
      if (row['cwd'] ==
              projects(profile).firstWhere((p) => p['id'] == id)['path'] ||
          (row['cwd'] == '/not-the-project-path' &&
              row['id'] == 'project-only'))
        row,
  ];
  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'session.workspace.move') {
          moves.add((scope.profileName, params));
          await mutationDelay?.future;
          if (failMutation) throw StateError('Move rejected');
          final id = params['session_key'] as String;
          final profile = changes.putIfAbsent(scope.profileName, () => {});
          profile[id] = {
            ...?profile[id],
            'cwd': params['cwd'],
            'git_branch': null,
            'git_repo_root': null,
          };
          return {'cwd': params['cwd'], 'branch': null, 'git_repo_root': null};
        }
        if (method == 'session.active_list') {
          return {
            'sessions': [
              if (active)
                {
                  'id': 'runtime',
                  'session_key': activeSessionKey,
                  'status': activeStatus,
                },
              if (foreignActive)
                {
                  'id': 'foreign-runtime',
                  'session_key': 'newest',
                  'status': 'working',
                },
            ],
          };
        }
        if (method == 'session.resume' &&
            params['session_id'] == activeSessionKey) {
          active = true;
          activeStatus = statusAfterResume ?? activeStatus;
          return {
            'session_id': 'runtime',
            if (reuseLiveResume) ...{
              'session_key': resumeSessionId,
              'resumed': resumeSessionId,
              'status': activeStatus,
            } else
              'stored_session_id': resumeSessionId,
            'messages': [],
            'info': {'profile_name': resumeProfile ?? scope.profileName},
            ...resumeOverrides,
          };
        }
        if (method == 'session.close') {
          closes.add((scope.profileName, params));
          if (failClose) throw StateError('Close rejected');
          if (acknowledgeClose) active = false;
          return {'closed': acknowledgeClose};
        }
        return base.call(method, params);
      },
      patch: (endpoint, body) async {
        updates.add((scope.profileName, endpoint, body));
        await mutationDelay?.future;
        if (failMutation) throw StateError('Write rejected');
        final id = Uri.decodeComponent(endpoint.split('/').last);
        final update = {...body}..remove('profile');
        final profile = changes.putIfAbsent(scope.profileName, () => {});
        profile[id] = {...?profile[id], ...update};
        return {'ok': true, 'title': update['title'] ?? 'Chat', ...update};
      },
      delete: (endpoint, query) async {
        if (failMutation) throw StateError('Delete rejected');
        if (active) throw StateError('Runtime must be closed before deletion');
        deletes.add((endpoint, query));
        removed
            .putIfAbsent(scope.profileName, () => {})
            .add(Uri.decodeComponent(endpoint.split('/').last));
      },
    );
  }
}
