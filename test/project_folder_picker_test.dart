import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/widgets/project_folder_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProjectScreenHost {
  final calls = <(String, Map<String, dynamic>)>[];
  final projects = <Map<String, dynamic>>[];

  ProfileGateway gateway(WorkspaceScope scope) => ProfileGateway(
    scope: scope,
    discover: () async => const ProfileDiscovery(
      profiles: [HermesProfile(name: 'work')],
      currentName: 'work',
      activeName: 'work',
    ),
    get: (path, query) async {
      if (path != 'sessions') throw StateError('Unexpected read $path');
      return {
        'sessions': const [],
        'offset': int.parse(query['offset']!),
        'limit': int.parse(query['limit']!),
        'total': 0,
      };
    },
    rpc: (method, params) async {
      calls.add((method, params));
      switch (method) {
        case 'session.active_list':
          return {'sessions': const []};
        case 'projects.tree':
          return {'projects': projects};
        case 'projects.discover_repos':
          return {
            'repos': const [
              {
                'root': '/srv/Client Work',
                'label': 'Client Work',
                'sessions': 2,
                'last_active': 10,
              },
            ],
            'discovery_policy': const {'enabled': true},
          };
        case 'projects.create':
          projects.add({
            'id': 'created',
            'label': params['name'],
            'path': params['primary_path'],
            'lastActive': 11,
          });
          return {
            'project': {'id': 'created'},
          };
        default:
          throw StateError('Unexpected RPC $method');
      }
    },
  );
}

void main() {
  Future<void> showPicker(
    WidgetTester tester, {
    required Future<List<ProjectFolderSuggestion>> Function() discover,
    required ValueChanged<String?> onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => onResult(
                await showDialog<String>(
                  context: context,
                  builder: (_) => ProjectFolderPickerDialog(discover: discover),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('manual path is available without scanning the host', (
    tester,
  ) async {
    var discoveries = 0;
    String? result;
    await showPicker(
      tester,
      discover: () async {
        discoveries++;
        return const [];
      },
      onResult: (value) => result = value,
    );

    expect(discoveries, 0);
    await tester.enterText(
      find.byKey(const ValueKey('project-folder-path')),
      '  /srv/manual  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('project-folder-continue')));
    await tester.pumpAndSettle();

    expect(result, '/srv/manual');
    expect(discoveries, 0);
  });

  testWidgets('find folders fills the manual path with a discovered root', (
    tester,
  ) async {
    var discoveries = 0;
    String? result;
    await showPicker(
      tester,
      discover: () async {
        discoveries++;
        return const [
          ProjectFolderSuggestion(path: '/srv/wing', label: 'Wing'),
          ProjectFolderSuggestion(path: '/srv/docs', label: 'Docs'),
        ];
      },
      onResult: (value) => result = value,
    );

    await tester.tap(find.byKey(const ValueKey('project-folder-find')));
    await tester.pumpAndSettle();
    expect(discoveries, 1);
    expect(find.text('Wing'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('project-folder-/srv/wing')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('project-folder-path')))
          .controller!
          .text,
      '/srv/wing',
    );
    await tester.tap(find.byKey(const ValueKey('project-folder-continue')));
    await tester.pumpAndSettle();

    expect(result, '/srv/wing');
  });

  testWidgets('folders remain usable with large text and the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    String? result;
    await showPicker(
      tester,
      discover: () async => const [
        ProjectFolderSuggestion(path: '/srv/docs', label: 'Documents'),
      ],
      onResult: (value) => result = value,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('project-folder-find')),
    );
    await tester.tap(find.byKey(const ValueKey('project-folder-find')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final folder = find.byKey(const ValueKey('project-folder-/srv/docs'));
    await tester.ensureVisible(folder);
    await tester.tap(folder);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('project-folder-continue')),
    );
    await tester.tap(find.byKey(const ValueKey('project-folder-continue')));
    await tester.pumpAndSettle();
    expect(result, '/srv/docs');
  });

  testWidgets('scan failure leaves manual path entry usable', (tester) async {
    String? result;
    await showPicker(
      tester,
      discover: () async => throw StateError('offline'),
      onResult: (value) => result = value,
    );

    await tester.tap(find.byKey(const ValueKey('project-folder-find')));
    await tester.pumpAndSettle();
    expect(
      find.text('Folders could not be loaded. Enter an absolute path instead.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('project-folder-path')),
      '/srv/fallback',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('project-folder-continue')));
    await tester.pumpAndSettle();
    expect(result, '/srv/fallback');
  });

  testWidgets('workspace create passes a discovered host path unchanged', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final host = _ProjectScreenHost();
    final controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'project-picker',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.binding.setSurfaceSize(const Size(460, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Workspace options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'New workspace',
    );
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('project-folder-find')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('project-folder-/srv/Client Work')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('project-folder-continue')));
    await tester.pumpAndSettle();

    final create = host.calls.singleWhere(
      (call) => call.$1 == 'projects.create',
    );
    expect(create.$2, {
      'name': 'New workspace',
      'folders': ['/srv/Client Work'],
      'primary_path': '/srv/Client Work',
      'profile': 'work',
    });
  });
}
