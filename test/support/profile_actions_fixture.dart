import 'package:wing/core/services/connection_manager.dart';
import 'dart:async';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'profile_browser_fixture.dart';

class ProfileActionsFixture extends ProfileBrowserFixture {
  final updates = <(String, String, Map<String, dynamic>)>[];
  final deletes = <(String, Map<String, String>)>[];
  final deleteAttempts = <(String, Map<String, String>)>[];
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
  Completer<void>? mutationStarted;
  Completer<void>? titleDelay;
  String? suggestedTitle = 'Conversation list improvements';
  bool failTitle = false;
  final titleRequests = <Map<String, dynamic>>[];
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
              id == 'p2' &&
              row['id'] == 'project-only'))
        row,
  ];
  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: (endpoint, query) async {
        final path = Uri.parse(endpoint).path;
        if (path != 'sessions/search' &&
            path.startsWith('sessions/') &&
            path.split('/').length == 2) {
          final id = Uri.decodeComponent(path.substring('sessions/'.length));
          final row = sessions(
            scope.profileName,
          ).where((row) => row['id'] == id).firstOrNull;
          if (row == null) throw DashboardSessionNotFound(path);
          return {...row, 'profile': scope.profileName};
        }
        return base.read(endpoint, query);
      },
      rpc: (method, params) async {
        if (method == 'llm.oneshot') {
          titleRequests.add(Map.of(params));
          await titleDelay?.future;
          if (failTitle) {
            throw StateError('Title generation failed. Try again.');
          }
          return {'text': suggestedTitle};
        }
        if (method == 'session.title') {
          final id = active ? activeSessionKey : 'new-chat';
          final title = params['title'];
          changes.putIfAbsent(scope.profileName, () => {})[id] = {
            'title': title,
          };
          return {'session_key': id, 'title': title, 'pending': !active};
        }
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
      ownedPatch: (endpoint, body, canDispatch, onDispatched) async {
        if (!canDispatch()) {
          throw DashboardRequestNotSentException(StateError('Menu retired'));
        }
        onDispatched();
        updates.add((scope.profileName, endpoint, body));
        mutationStarted?.complete();
        await mutationDelay?.future;
        if (failMutation) throw StateError('Write rejected');
        final id = Uri.decodeComponent(endpoint.split('/').last);
        final update = {
          for (final key in ['title', 'pinned', 'archived', 'unread'])
            if (body.containsKey(key)) key: body[key],
        };
        final profile = changes.putIfAbsent(scope.profileName, () => {});
        profile[id] = {...?profile[id], ...update};
        return {'ok': true, 'title': update['title'] ?? 'Chat', ...update};
      },
      ownedDelete: (endpoint, parameters, canDispatch, onDispatched) async {
        if (!canDispatch()) {
          throw DashboardRequestNotSentException(StateError('Menu retired'));
        }
        final query = parameters.map(
          (key, value) => MapEntry(key, value.toString()),
        );
        onDispatched();

        deleteAttempts.add((endpoint, Map.unmodifiable(query)));
        if (failMutation) throw StateError('Delete rejected');
        if (active) throw StateError('Runtime must be closed before deletion');
        deletes.add((endpoint, query));
        removed
            .putIfAbsent(scope.profileName, () => {})
            .add(Uri.decodeComponent(endpoint.split('/').last));

        return {'ok': true};
      },
    );
  }
}
