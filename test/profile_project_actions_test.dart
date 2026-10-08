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

  testWidgets(
    'rename stays reviewable on failure and blocks duplicate submit',
    (tester) async {
      await showHarness(tester);
      await openAction(tester, 'rename');
      await tester.enterText(
        find.byKey(const ValueKey('project-name-field')),
        'Renamed project',
      );

      host.delay = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('project-rename-save')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('project-rename-save')),
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
      expect(find.text('Rename project'), findsOneWidget);
      host.failMutation = true;
      host.delay!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Renamed project'), findsOneWidget);
      expect(find.textContaining('not acknowledged'), findsOneWidget);
      host.failMutation = false;
      await tester.tap(find.byKey(const ValueKey('project-rename-save')));
      await tester.pumpAndSettle();
      expect(find.text('Rename project'), findsNothing);
      expect(host.personalProject['label'], 'Renamed project');
    },
  );

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

  testWidgets('appearance sends Desktop color and icon values', (tester) async {
    await showHarness(tester);
    await openAction(tester, 'appearance');
    await tester.tap(find.byKey(const ValueKey('project-color-7')));
    await tester.ensureVisible(find.byKey(const ValueKey('project-icon-repo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-icon-repo')));
    await tester.tap(find.byKey(const ValueKey('project-appearance-save')));
    await tester.pumpAndSettle();

    final call = host.calls.lastWhere((call) => call.$2 == 'projects.update');
    expect(call.$1, 'personal');
    expect(call.$3, {
      'id': 'personal-project',
      'color': 'hsl(210 68% 58%)',
      'icon': 'repo',
      'profile': 'personal',
    });
    expect(find.text('Project appearance'), findsNothing);
  });

  testWidgets('captured owner prevents a profile-switched rename', (
    tester,
  ) async {
    await showHarness(tester);
    await openAction(tester, 'rename');
    await tester.enterText(
      find.byKey(const ValueKey('project-name-field')),
      'Wrong owner',
    );
    await controller.navigateProfile('work');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('project-rename-save')));
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
  };
  final workProject = <String, dynamic>{
    'id': 'work-project',
    'label': 'Work app',
    'path': '/work',
    'lastActive': 10,
  };
  bool deleted = false;
  bool failMutation = false;
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
      get: base.read,
      rpc: (method, params) async {
        if (method == 'projects.update' || method == 'projects.delete') {
          calls.add((
            scope.profileName,
            method,
            Map<String, dynamic>.from(params),
          ));
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
