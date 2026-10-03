import 'dart:async';

import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';

import 'profile_actions_fixture.dart';

class BrowserMutationsFixture extends ProfileActionsFixture {
  final projectChanges = <String, Map<String, dynamic>>{};
  final deletedProjects = <String>{};
  Completer<void>? projectReadDelay;
  int extraRows = 0;

  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (final row in super.sessions(profile))
      {...row, 'input_tokens': 1000, 'output_tokens': 500},
    for (var i = 0; i < extraRows; i++)
      {
        'id': 'extra-$i',
        'title': 'Extra chat $i',
        'profile': profile,
        'last_active': now - (i + 20) * 3600,
        'input_tokens': 1000,
        'output_tokens': 500,
        ...?changes[profile]?['extra-$i'],
      },
  ];

  @override
  List<Map<String, dynamic>> projects(String profile) => [
    for (final project in super.projects(profile))
      if (!deletedProjects.contains('$profile/${project['id']}'))
        {...project, ...?projectChanges['$profile/${project['id']}']},
    ?projectChanges['$profile/created'],
  ];

  Map<String, dynamic> _confirmedProject(Map<String, dynamic> project) => {
    'id': project['id'],
    'name': project['label'],
    'primary_path': project['path'],
    'color': project['color'],
    'icon': project['icon'],
  };

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      patch: (path, body) => base.updateSession(
        Uri.decodeComponent(path.split('/').last),
        {...body}..remove('profile'),
      ),
      delete: (path, query) =>
          base.deleteSession(Uri.decodeComponent(path.split('/').last)),
      rpc: (method, params) async {
        if (method == 'projects.update') {
          final id = params['id'] as String;
          final project = projects(
            scope.profileName,
          ).firstWhere((p) => p['id'] == id);
          final updated = {
            ...project,
            if (params.containsKey('name')) 'label': params['name'],
            if (params.containsKey('color')) 'color': params['color'],
            if (params.containsKey('icon')) 'icon': params['icon'],
          };
          projectChanges['${scope.profileName}/$id'] = updated;
          return {'project': _confirmedProject(updated)};
        }
        if (method == 'projects.create') {
          final project = {
            'id': 'created',
            'label': params['name'],
            'path': params['primary_path'],
            'lastActive': now,
          };
          projectChanges['${scope.profileName}/created'] = project;
          return {'project': _confirmedProject(project)};
        }
        if (method == 'projects.delete') {
          deletedProjects.add('${scope.profileName}/${params['id']}');
          return {
            'projects': projects(
              scope.profileName,
            ).map(_confirmedProject).toList(),
            'active_id': null,
          };
        }
        final result = await base.call(method, params);
        if (method == 'projects.tree') await projectReadDelay?.future;
        return result;
      },
    );
  }
}
