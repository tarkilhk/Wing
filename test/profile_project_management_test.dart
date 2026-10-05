import 'support/composer_fixture.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProjectHost {
  final calls = <(String, String, Map<String, dynamic>)>[];
  final projects = <String, List<Map<String, dynamic>>>{
    'a': [
      {
        'id': 'project-a',
        'label': 'A project',
        'path': '/a',
        'lastActive': 2,
        'color': '#112233',
        'icon': 'folder',
      },
    ],
    'b': [
      {'id': 'project-b', 'label': 'B project', 'path': '/b', 'lastActive': 1},
    ],
  };
  final history = <String, List<Map<String, dynamic>>>{};
  bool rejectUpdateAck = false;
  bool rejectDeleteAck = false;
  bool failDeleteRefresh = false;
  final failNextTree = <String>{};
  Completer<void>? deleteStarted;
  Completer<void>? deleteGate;

  Future<ProfileDiscovery> discover() async => ProfileDiscovery(
    profiles: const [
      HermesProfile(name: 'a'),
      HermesProfile(name: 'b'),
    ],
    currentName: 'a',
    activeName: 'a',
  );

  ProfileGateway gateway(WorkspaceScope scope) => ProfileGateway(
    scope: scope,
    discover: discover,
    get: (path, query) async {
      if (path == 'sessions') {
        return {
          'offset': int.parse(query['offset']!),
          'limit': int.parse(query['limit']!),
          'total': 1,
          'sessions': [
            {
              'id': '${scope.profileName}-chat',
              'title': '${scope.profileName} chat',
              'profile': scope.profileName,
            },
          ],
        };
      }
      if (path.endsWith('/messages')) {
        final id = Uri.decodeComponent(path.split('/')[1]);
        final offset = int.parse(query['offset']!);
        final limit = int.parse(query['limit']!);
        final rows = (history[id] ?? <Map<String, dynamic>>[])
            .skip(offset)
            .take(limit)
            .toList();
        return {
          'session_id': id,
          'messages': rows,
          'pagination': {
            'offset': offset,
            'limit': limit,
            'returned': rows.length,
            'order': 'latest',
          },
        };
      }
      throw StateError('Unexpected read $path');
    },
    rpc: (method, params) async {
      calls.add((scope.profileName, method, params));
      switch (method) {
        case 'session.resume':
          return {
            'session_id': '${scope.profileName}-runtime',
            'session_key': params['session_id'],
            'resumed': params['session_id'],
            'status': 'idle',
            'messages':
                history[params['session_id']] ?? <Map<String, dynamic>>[],
            'running': false,
            'info': {'profile_name': scope.profileName},
          };
        case 'projects.tree':
          if (failNextTree.remove(scope.profileName)) {
            throw StateError('Tree refresh failed');
          }
          return {'projects': projects[scope.profileName]};
        case 'projects.project_sessions':
          return {
            'project': {'id': params['project_id'], 'repos': const []},
          };
        case 'projects.update':
          if (rejectUpdateAck) return {};
          final id = params['id'];
          projects[scope.profileName] = [
            for (final project in projects[scope.profileName]!)
              if (project['id'] == id)
                {
                  ...project,
                  if (params['name'] case final String name) 'label': name,
                  if (params.containsKey('color'))
                    'color': params['color'] == '' ? null : params['color'],
                  if (params.containsKey('icon'))
                    'icon': params['icon'] == '' ? null : params['icon'],
                }
              else
                project,
          ];
          return {
            'project': {
              ...projects[scope.profileName]!.firstWhere((p) => p['id'] == id),
              'name': projects[scope.profileName]!.firstWhere(
                (p) => p['id'] == id,
              )['label'],
              'primary_path': projects[scope.profileName]!.firstWhere(
                (p) => p['id'] == id,
              )['path'],
            },
          };
        case 'projects.delete':
          deleteStarted?.complete();
          await deleteGate?.future;
          if (rejectDeleteAck) return {};
          final id = params['id'];
          projects[scope.profileName] = [
            for (final project in projects[scope.profileName]!)
              if (project['id'] != id) project,
          ];
          if (failDeleteRefresh) failNextTree.add(scope.profileName);
          return {'projects': projects[scope.profileName], 'active_id': null};
        default:
          throw StateError('Unexpected RPC $method');
      }
    },
  );
}

void main() {
  late _ProjectHost host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _ProjectHost();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      connectionIdentity: 'project-host',
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  test('updates server appearance and refreshes selected metadata', () async {
    final resource = controller.current!;
    await controller.selectProject(resource.projects.single);
    await controller.openSession(ProfileSessionKey(resource.scope, 'a-chat'));

    await controller.updateProject(
      resource.scope,
      'project-a',
      name: 'Renamed',
      color: '',
      icon: 'rocket',
      canDispatch: () => true,
    );

    final call = host.calls.lastWhere((entry) => entry.$2 == 'projects.update');
    expect(call.$1, 'a');
    expect(call.$3, {
      'id': 'project-a',
      'name': 'Renamed',
      'color': '',
      'icon': 'rocket',
      'profile': 'a',
    });
    expect(resource.projects.single['name'], 'Renamed');
    expect(resource.projects.single['color'], isNull);
    expect(resource.projects.single['icon'], 'rocket');
    expect(resource.selectedProject, same(resource.projects.single));
    expect(resource.selectedSession, 'a-chat');
  });

  test(
    'late delete changes only its owner and preserves chat records',
    () async {
      final resourceA = controller.current!;
      host.history['a-chat'] = [
        {'id': 1, 'role': 'assistant', 'content': 'Keep this answer'},
      ];
      await controller.selectProject(resourceA.projects.single);
      final cachedChat = await openFixtureChat(
        controller: controller,
        key: ProfileSessionKey(resourceA.scope, 'a-chat'),
        title: 'A chat',
        select: false,
      );
      await cachedChat.composer.editText('Keep this draft');

      host.deleteStarted = Completer<void>();
      host.deleteGate = Completer<void>();

      final deleting = controller.deleteProject(
        resourceA.scope,
        'project-a',
        canDispatch: () => true,
      );
      await host.deleteStarted!.future;
      await controller.openSession(
        ProfileSessionKey(resourceA.scope, 'a-chat'),
      );
      await controller.navigateProfile('b');
      final resourceB = controller.current!;
      await controller.selectProject(resourceB.projects.single);

      host.deleteGate!.complete();
      await deleting;

      expect(controller.current, same(resourceB));
      expect(resourceB.selectedProject?['id'], 'project-b');
      expect(resourceB.projects.single['id'], 'project-b');
      expect(resourceA.projects, isEmpty);
      expect(resourceA.selectedProject, isNull);
      expect(resourceA.selectedSession, 'a-chat');
      expect(resourceA.sessions.single['id'], 'a-chat');
      expect(resourceA.visibleSessions.single['id'], 'a-chat');
      expect(cachedChat.projectId, isNull);
      expect(cachedChat.composer.observation.text, 'Keep this draft');
      expect(cachedChat.reading.messages.single['content'], 'Keep this answer');
    },
  );

  test(
    'failed acknowledgements leave server-backed selection unchanged',
    () async {
      final resource = controller.current!;
      await controller.selectProject(resource.projects.single);
      final selected = resource.selectedProject;

      host.rejectUpdateAck = true;
      await expectLater(
        controller.updateProject(
          resource.scope,
          'project-a',
          name: 'Ignored',
          canDispatch: () => true,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(resource.projects.single['name'], 'A project');
      expect(resource.selectedProject, same(selected));

      host.rejectDeleteAck = true;
      await expectLater(
        controller.deleteProject(
          resource.scope,
          'project-a',
          canDispatch: () => true,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(resource.projects.single['id'], 'project-a');
      expect(resource.selectedProject, same(selected));
    },
  );

  test(
    'acknowledged delete finishes without a follow-up project read',
    () async {
      final resource = controller.current!;
      await controller.selectProject(resource.projects.single);
      host.failDeleteRefresh = true;
      host.calls.clear();

      await controller.deleteProject(
        resource.scope,
        'project-a',
        canDispatch: () => true,
      );

      expect(resource.projects, isEmpty);
      expect(resource.selectedProject, isNull);
      expect(resource.projectsError, isNull);
      expect(host.calls.where((call) => call.$2 == 'projects.tree'), isEmpty);
    },
  );
}
