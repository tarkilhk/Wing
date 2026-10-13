import 'package:wing/core/models/chat_list_view.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_project_actions.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_browser_fixture.dart';

void main() {
  late _ProjectFixture host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late ChatBrowserData browser;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _ProjectFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'project-actions',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    browser = ChatBrowserData(controller);
    host.calls.clear();
  });

  tearDown(() {
    browser.dispose();
    controller.dispose();
    appPreferences.dispose();
  });

  Future<void> showHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final session = await browser.projectActionsFor(
                    controller.current!.scope,
                    BrowserProject.fromWire(
                      controller.current!.projects.single,
                    ),
                  );
                  if (session == null) return;
                  try {
                    if (context.mounted) {
                      await showProjectActions(context, session);
                    }
                  } finally {
                    session.dispose();
                  }
                },
                child: const Text('Project actions'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openAction(WidgetTester tester, String key) async {
    await tester.tap(find.text('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('project-action-$key')));
    await tester.pumpAndSettle();
  }

  testWidgets('edit keeps its draft on failure and blocks duplicate save', (
    tester,
  ) async {
    await showHarness(tester);
    await openAction(tester, 'editProject');
    await tester.enterText(
      find.byKey(const ValueKey('project-name-field')),
      'Renamed project',
    );

    host.delay = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('project-edit-confirm')));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('project-edit-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(
      host.calls.where((call) => call.$2 == 'projects.update'),
      hasLength(1),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('project-name-field')))
          .enabled,
      isFalse,
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Edit project'), findsOneWidget);
    host.failMutation = true;
    host.delay!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Renamed project'), findsOneWidget);
    expect(find.textContaining('not acknowledged'), findsOneWidget);
    host.failMutation = false;
    await tester.tap(find.byKey(const ValueKey('project-edit-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Edit project'), findsNothing);
    expect(host.personalProject['label'], 'Renamed project');
  });

  testWidgets('pending delete stays open until acknowledgement', (
    tester,
  ) async {
    await showHarness(tester);
    await openAction(tester, 'delete');
    host.delay = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
    await tester.pump();
    await tester.tapAt(const Offset(8, 8));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Delete project?'), findsOneWidget);
    host.delay!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Delete project?'), findsNothing);
  });

  testWidgets('edit menu prefills one shared project form and folder picker', (
    tester,
  ) async {
    await showHarness(tester);
    await tester.tap(find.text('Project actions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-action-rename')), findsNothing);
    expect(
      find.byKey(const ValueKey('project-action-appearance')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('project-action-editProject')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('project-action-editProject')));
    await tester.pumpAndSettle();
    expect(find.text('Edit project'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('project-name-field')))
          .controller!
          .text,
      'Mobile app',
    );
    expect(find.text('/mobile'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('project-icon-book')),
              matching: find.byType(IconButton),
            ),
          )
          .isSelected,
      isTrue,
    );
    await tester.ensureVisible(find.byTooltip('Change primary folder'));
    await tester.tap(find.byTooltip('Change primary folder'));
    await tester.pumpAndSettle();
    expect(find.text('/mobile'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('project-folder-continue')));
    await tester.pumpAndSettle();
    expect(
      host.calls.where((call) => call.$2.startsWith('projects.')),
      isEmpty,
    );
  });

  test(
    'primary switch retains folders and publishes before metadata failure',
    () async {
      final resource = controller.current!;
      host.failMutation = true;
      await expectLater(
        controller.updateProject(
          resource.scope,
          'personal-project',
          path: '/new',
          name: 'Edited project',
          color: '#334455',
          icon: 'rocket',
          canDispatch: () => true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Folder saved.'),
          ),
        ),
      );
      expect(resource.projects.single['path'], '/new');
      expect(resource.projects.single['name'], 'Mobile app');
      expect(
        (resource.projects.single['folders'] as List).map((f) => f['path']),
        containsAll(['/mobile', '/archive', '/new']),
      );
      expect(
        host.calls
            .where(
              (call) => {
                'projects.add_folder',
                'projects.update',
                'projects.remove_folder',
              }.contains(call.$2),
            )
            .map((call) => call.$2),
        ['projects.add_folder', 'projects.update'],
      );
      expect(host.calls.first.$3, {
        'id': 'personal-project',
        'path': '/new',
        'is_primary': true,
        'profile': 'personal',
      });
      host.failMutation = false;
      await controller.updateProject(
        resource.scope,
        'personal-project',
        path: '/new',
        name: 'Edited project',
        color: '#334455',
        icon: 'rocket',
        canDispatch: () => true,
      );
      expect(
        host.calls.where((call) => call.$2 == 'projects.add_folder'),
        hasLength(1),
      );
      expect(resource.projects.single['name'], 'Edited project');
      expect(resource.projects.single['path'], '/new');
      expect(
        (resource.projects.single['folders'] as List).map((f) => f['path']),
        containsAll(['/mobile', '/archive', '/new']),
      );
    },
  );

  test(
    'invalid primary acknowledgement prevents later metadata write',
    () async {
      host.rejectPrimaryAck = true;
      await expectLater(
        controller.updateProject(
          controller.current!.scope,
          'personal-project',
          path: '/new',
          name: 'Edited',
          canDispatch: () => true,
        ),
        throwsFormatException,
      );
      expect(controller.current!.projects.single['path'], '/mobile');
      expect(
        host.calls
            .where(
              (call) => {
                'projects.add_folder',
                'projects.update',
                'projects.remove_folder',
              }.contains(call.$2),
            )
            .map((call) => call.$2),
        ['projects.add_folder'],
      );
    },
  );

  test('primary-only edit updates selected project placement', () async {
    final resource = controller.current!;
    await controller.selectProject(resource.projects.single);
    await controller.updateProject(
      resource.scope,
      'personal-project',
      path: '/new',
      canDispatch: () => true,
    );
    expect(ProfileGateway.projectDirectory(resource.selectedProject!), '/new');
    expect(resource.selectedProject, same(resource.projects.single));
    expect(
      host.calls.where((call) => call.$2 == 'projects.add_folder'),
      hasLength(1),
    );
    expect(host.calls.where((call) => call.$2 == 'projects.update'), isEmpty);
  });

  test('invalid edit values cannot switch the folder first', () async {
    await expectLater(
      controller.updateProject(
        controller.current!.scope,
        'personal-project',
        path: '/new',
        name: ' ',
        canDispatch: () => true,
      ),
      throwsArgumentError,
    );
    expect(host.calls, isEmpty);
    expect(controller.current!.projects.single['path'], '/mobile');
  });

  test('profile switch between edit steps fences the second write', () async {
    final captured = controller.current!;
    host.primaryDelay = Completer<void>();
    final pending = controller.updateProject(
      captured.scope,
      'personal-project',
      path: '/new',
      name: 'Edited',
      canDispatch: () => true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      host.calls
          .where(
            (call) => {
              'projects.add_folder',
              'projects.update',
              'projects.remove_folder',
            }.contains(call.$2),
          )
          .map((call) => call.$2),
      ['projects.add_folder'],
    );
    await controller.navigateProfile('work');
    host.primaryDelay!.complete();
    await expectLater(pending, throwsStateError);
    expect(
      host.calls
          .where(
            (call) => {
              'projects.add_folder',
              'projects.update',
              'projects.remove_folder',
            }.contains(call.$2),
          )
          .map((call) => call.$2),
      ['projects.add_folder'],
    );
    expect(controller.current!.projects.single['path'], '/work');
    expect(captured.projects.single['path'], '/new');
  });

  testWidgets('appearance sends Desktop color and icon values', (tester) async {
    await showHarness(tester);
    await openAction(tester, 'editProject');
    await tester.tap(find.byKey(const ValueKey('project-color-7')));
    await tester.ensureVisible(find.byKey(const ValueKey('project-icon-repo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-icon-repo')));
    await tester.tap(find.byKey(const ValueKey('project-edit-confirm')));
    await tester.pumpAndSettle();

    final call = host.calls.lastWhere((call) => call.$2 == 'projects.update');
    expect(call.$1, 'personal');
    expect(call.$3, {
      'id': 'personal-project',
      'name': 'Mobile app',
      'color': 'hsl(210 68% 58%)',
      'icon': 'repo',
      'profile': 'personal',
    });
    expect(find.text('Edit project'), findsNothing);
  });

  testWidgets('captured owner prevents a profile-switched edit', (
    tester,
  ) async {
    await showHarness(tester);
    await openAction(tester, 'editProject');
    await tester.enterText(
      find.byKey(const ValueKey('project-name-field')),
      'Wrong owner',
    );
    await controller.navigateProfile('work');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('project-edit-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Wrong owner'), findsOneWidget);
    expect(find.textContaining('Profile changed'), findsOneWidget);
    expect(host.calls.where((call) => call.$2 == 'projects.update'), isEmpty);
  });

  testWidgets(
    'delete states its scope and keeps a rejected confirmation open',
    (tester) async {
      await showHarness(tester);
      await openAction(tester, 'delete');
      expect(find.textContaining('chats will remain'), findsOneWidget);
      expect(
        find.textContaining('Files on the host will not be deleted'),
        findsOneWidget,
      );

      host.failMutation = true;
      await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('not acknowledged'), findsOneWidget);
      expect(find.text('Delete project?'), findsOneWidget);

      host.failMutation = false;
      await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Delete project?'), findsNothing);
      expect(controller.current!.projects, isEmpty);
    },
  );

  testWidgets('project avatar accepts server appearance and invalid fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Builder(
              builder: (context) => projectAvatar(
                context,
                const BrowserProject(
                  id: 'first',
                  name: '',
                  color: '#123456',
                  icon: 'repo',
                ),
              ),
            ),
            Builder(
              builder: (context) => projectAvatar(
                context,
                const BrowserProject(
                  id: 'second',
                  name: '',
                  color: 'not-a-color',
                  icon: 'not-an-icon',
                ),
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  });
}

class _ProjectFixture extends ProfileBrowserFixture {
  final personalProject = <String, dynamic>{
    'id': 'personal-project',
    'label': 'Mobile app',
    'path': '/mobile',
    'lastActive': 10,
    'color': '#123456',
    'icon': 'book',
    'folders': [
      {'path': '/mobile', 'is_primary': true},
      {'path': '/archive', 'is_primary': false},
    ],
  };
  final workProject = <String, dynamic>{
    'id': 'work-project',
    'label': 'Work app',
    'path': '/work',
    'lastActive': 10,
  };
  bool deleted = false;
  bool failMutation = false;
  bool rejectPrimaryAck = false;
  Completer<void>? primaryDelay;
  Completer<void>? delay;

  @override
  List<Map<String, dynamic>> projects(String profile) {
    if (profile == 'work') return [Map<String, dynamic>.from(workProject)];
    return deleted ? [] : [Map<String, dynamic>.from(personalProject)];
  }

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: (path, query) async {
        if (path != 'files') return base.read(path, query);
        final folder = query['path'] ?? '/';
        return {
          'path': folder,
          'parent': folder == '/' ? null : '/',
          'entries': [
            if (folder == '/')
              for (final name in ['mobile', 'archive', 'new'])
                {'name': name, 'path': '/$name', 'is_directory': true},
          ],
        };
      },
      rpc: (method, params) async {
        if (method == 'projects.update' ||
            method == 'projects.delete' ||
            method == 'projects.add_folder') {
          calls.add((
            scope.profileName,
            method,
            Map<String, dynamic>.from(params),
          ));
          if (method == 'projects.add_folder') {
            await primaryDelay?.future;
            primaryDelay = null;
            if (rejectPrimaryAck) {
              return {
                'project': {'id': params['id']},
              };
            }
            final path = params['path'];
            personalProject['path'] = path;
            personalProject['folders'] = [
              for (final folder in personalProject['folders'] as List)
                if (folder['path'] != path)
                  {...folder as Map<String, dynamic>, 'is_primary': false},
              {'path': path, 'is_primary': true},
            ];
            return {
              'project': {
                ...personalProject,
                'name': personalProject['label'],
                'primary_path': path,
              },
            };
          }
          await delay?.future;
          delay = null;
          if (failMutation) throw StateError('Rejected');
          if (method == 'projects.update') {
            for (final key in ['name', 'color', 'icon']) {
              if (params.containsKey(key)) {
                personalProject[key == 'name' ? 'label' : key] = params[key];
              }
            }
            return {
              'project': {
                ...personalProject,
                'name': personalProject['label'],
                'primary_path': personalProject['path'],
              },
            };
          }
          deleted = true;
          return {'projects': <Map<String, dynamic>>[], 'active_id': null};
        }
        return base.call(method, params);
      },
    );
  }
}
