// Export real Wing widgets with authored, public-safe demo content.
// Run manually; this is asset tooling, not a production application change.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/gateway_activity.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/transcript_message.dart';
import 'package:wing/core/presentation/tool_call_presentation.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/screens/administration/administration_content.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/composer_action_button.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/widgets/profile_tool_call.dart';

import '../../test/helpers/pump_markdown_widget.dart';
import '../../test/support/profile_browser_fixture.dart';
import '../../test/support/administration_design_fixture.dart';
import '../../test/support/host_resources_fixture.dart';

class _CaptureBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

class _WebsiteFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (final row in super.sessions(profile))
      {
        ...row,
        if (row['id'] == 'newest') 'title': 'The research, ready to use',
        if (row['id'] == 'pinned') 'title': 'Ideas for the next release',
        if (row['id'] == 'project-only')
          'title': 'Compare the deployment options',
        if (row['id'] == 'old') 'title': 'Turn meeting notes into a plan',
        if (row['id'] == 'test') 'title': 'Review the report sources',
        if (row['id'] == 'docs') 'title': 'Prepare the launch checklist',
        if (profile == 'work') 'title': 'Review the launch copy',
        if (profile == 'work') 'id': 'launch-copy',
      },
  ];

  @override
  List<Map<String, dynamic>> projects(String profile) => [
    for (final project in super.projects(profile))
      {
        ...project,
        if (project['id'] == 'p2') 'label': 'Research',
        if (profile == 'work') 'label': 'Launch',
        'sessionIds': profile == 'work'
            ? ['launch-copy']
            : project['id'] == 'p2'
            ? ['newest', 'project-only']
            : project['isNoProject'] == true
            ? ['old', 'pinned', 'pin-two', 'test', 'docs']
            : <String>[],
      },
  ];

  @override
  List<Map<String, dynamic>> searchRows(String profile, String query) => [
    for (final row in sessions(profile))
      if (row['id'] == query ||
          row['title'].toString().toLowerCase().contains(query))
        {...row, 'session_id': row['id']},
  ];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) =>
      id != 'newest'
      ? [
          {
            'id': 1,
            'role': 'assistant',
            'content': 'The next step is ready to review.',
            'timestamp': now - 600,
          },
        ]
      : [
          {
            'id': 1,
            'role': 'user',
            'timestamp': now - 7200,
            'content':
                'Check the options and turn the research into a short recommendation.',
          },
          {
            'id': 2,
            'role': 'tool',
            'tool_name': 'execute_code',
            'content': 'Checked 7 records. Source dates preserved.',
          },
          {
            'id': 3,
            'role': 'assistant',
            'timestamp': now - 600,
            'content':
                '## The comparison is ready\n\n'
                'I checked all 7 records and kept the source dates with each finding.\n\n'
                '| Option | Best for |\n| --- | --- |\n'
                '| Smaller setup | A focused pilot |\n| Full setup | A larger rollout |\n'
                '| Hybrid setup | Gradual expansion |\n\n'
                '**Start with the smaller setup.** It covers the pilot without adding work you do not need yet.\n\n'
                'The full comparison is saved in `comparison.md`.',
          },
        ];

  @override
  ProfileGateway gateway(scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: (path, query) async => path == 'model/info'
          ? {'provider': 'research', 'model': 'Research model'}
          : base.read(path, query),
      ownedPatch: (path, body, canDispatch, onDispatched) async {
        if (!canDispatch()) throw StateError('Capture retired');
        onDispatched();
        return {'ok': true};
      },
      rpc: (method, params) async {
        if (method == 'setup.runtime_check') {
          return {
            'ok': true,
            'profile': scope.profileName,
            'provider': 'research',
            'model': 'Research model',
          };
        }
        final result = await base.call(method, params);
        if (method == 'session.resume') {
          return {
            ...result,
            'info': {
              ...result['info'] as Map,
              'model': 'provider/research-model',
            },
          };
        }
        return result;
      },
    );
  }
}

class _WebsiteAdministration extends AdministrationDesignFixture {
  @override
  Future<Map<String, dynamic>> send(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic>? body,
  ) async {
    if (path == 'system/stats') {
      return {...hostStatsPayload(), 'hostname': 'My Hermes'};
    }
    if (path == 'status') return hostPressurePayload();
    if (path == 'ops/doctor' || path == 'ops/security-audit') {
      return {'ok': true, 'name': path.substring(4), 'pid': 7};
    }
    if (path.startsWith('actions/')) {
      return {
        'name': path.split('/')[1],
        'pid': 7,
        'running': false,
        'exit_code': 0,
        'lines': ['All checks passed.'],
      };
    }
    if (path == 'tools/toolsets') {
      return {
        'data': [
          {'name': 'web', 'enabled': true, 'configured': true},
          {'name': 'terminal', 'enabled': true, 'configured': true},
        ],
      };
    }
    if (path == 'mcp/servers') {
      return {
        'servers': [
          {'name': 'Research library', 'enabled': true},
        ],
      };
    }
    if (path.endsWith('/test')) return {'ok': true};
    if (path == 'providers/oauth') {
      return {
        'providers': [
          {
            'id': 'research',
            'name': 'Research provider',
            'flow': 'device_code',
            'status': {'logged_in': true, 'source_label': 'Profile sign-in'},
          },
        ],
      };
    }
    return super.send(method, path, query, body);
  }
}

void main() {
  _CaptureBinding();
  const frame = ValueKey('website-capture');

  setUpAll(() async {
    const root = String.fromEnvironment('WING_CAPTURE_FONTS');
    for (final entry in {
      'Roboto': '$root/studio-roboto.ttf',
      'Ahem': '$root/studio-roboto.ttf',
      'MaterialIcons': '$root/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
      'monospace': '$root/studio-mono.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.settleMarkdown();
    await tester.runAsync(() async {
      final context = tester.element(find.byKey(frame));
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        await precacheImage(image.image, context);
      }
    });
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(frame),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('website/assets/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('export ${brightness.name} website demo screens', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      // This opt-in fixture tool runs under flutter test, outside test/ discovery.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final fixture = _WebsiteFixture();
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: SavedConnection(
            id: 'Home server',
            label: 'My Hermes',
            host: 'unused',
            port: 1,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'Home server-endpoint',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: fixture.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            home: ProfileWorkspaceScreen(controller: controller),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await capture(tester, 'chats-${brightness.name}');
      fixture.liveSessions['personal'] = [
        {
          'id': 'research-runtime',
          'session_key': 'project-only',
          'status': 'working',
          'last_active': fixture.now,
        },
      ];
      fixture.liveSessions['work'] = [
        {
          'id': 'launch-runtime',
          'session_key': 'launch-copy',
          'status': 'waiting',
          'last_active': fixture.now,
        },
      ];
      await controller.refreshRecents();
      expect(controller.recentsProfileErrors, isEmpty);
      expect(
        controller.recentChats().where((chat) => chat.state != null),
        hasLength(2),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            home: ProfileWorkspaceScreen(
              key: const ValueKey('recents'),
              controller: controller,
              initialDestination: AppDestination.activity,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await capture(tester, 'recents-${brightness.name}');
      fixture.liveSessions.clear();
      await controller.refreshActivity();
      await tester.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            home: ProfileWorkspaceScreen(
              key: const ValueKey('conversation'),
              controller: controller,
            ),
          ),
        ),
      );
      final chat = (await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'newest'),
      ))!;
      await tester.pump(const Duration(milliseconds: 250));
      await tester.settleMarkdown();
      controller.current!.gateway.onEvent!(
        StreamEvent(
          type: 'session.usage',
          sessionId: chat.runtime.runtimeId,
          data: const {
            'usage': {
              'context_used': 42000,
              'context_max': 128000,
              'context_percent': 32.8,
              'context_estimated': true,
            },
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await capture(tester, 'conversation-${brightness.name}');

      controller.current!.gateway.onEvent!(
        StreamEvent(
          type: 'message.start',
          sessionId: chat.runtime.runtimeId,
          data: const {},
        ),
      );
      await tester.enterText(
        find.byKey(const Key('profile-message-composer')),
        'Keep the source links in the final report.',
      );
      await tester.pump(const Duration(milliseconds: 250));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ComposerActionButton)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('composer-choice-steer'))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, 'steer-${brightness.name}');
      await gesture.cancel();

      final administration = _WebsiteAdministration();
      administration.jobs.add({
        'id': 'morning-brief',
        'name': 'Morning research brief',
        'enabled': true,
        'state': 'scheduled',
        'schedule': {'kind': 'cron', 'expr': '0 8 * * 1-5'},
        'next_run_at': DateTime.now()
            .add(const Duration(hours: 12))
            .toIso8601String(),
      });
      controller.connectionStatus.accessAvailable();
      controller.connectionStatus.liveChanged('personal', true);
      for (final healthOnly in [false, true]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              home: Scaffold(
                appBar: healthOnly
                    ? AppBar(title: const Text('Hermes health'))
                    : null,
                body: HermesAdministrationContent(
                  key: ValueKey(healthOnly),
                  controller: controller,
                  repository: administration.server,
                  onOpenMenu: () {},
                  onOpenSession: (_) async {},
                  healthOnly: healthOnly,
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await capture(
          tester,
          '${healthOnly ? 'health' : 'administration'}-${brightness.name}',
        );
        if (healthOnly) {
          tester.view.physicalSize = const Size(390, 560);
          await tester.pump(const Duration(milliseconds: 250));
          await tester.drag(find.byType(ListView).last, const Offset(0, -420));
          await tester.pump(const Duration(milliseconds: 250));
          await capture(tester, 'health-profile-${brightness.name}');
          tester.view.physicalSize = const Size(390, 844);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());

      tester.view.physicalSize = const Size(390, 800);
      await tester.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ProfileMessage(
                  message: TranscriptMessage.fromRow({
                    'role': 'assistant',
                    'content':
                        '## Your launch plan\n\nThe research is ready. **Start with a focused pilot**, then expand from what you learn.\n\n| Step | Result |\n| --- | --- |\n| Review | A clear recommendation |\n| Pilot | Feedback from real use |\n| Expand | A tested plan |\n\n> Keep the source dates with the findings.\n\n```python\nfrom pathlib import Path\nreport = Path("comparison.md")\nprint(report.read_text())\n```\n\nThe complete report: [comparison.md](/workspace/comparison.md)',
                  }),
                  onOpenRemoteFile: (_) async {},
                  onDownloadRemoteFile: (_) async => true,
                  onReadAloud: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await capture(tester, 'results-${brightness.name}');

      tester.view.physicalSize = const Size(390, 400);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wingTheme(brightness),
          home: RepaintBoundary(
            key: frame,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: ProfileToolCall(
                  initiallyExpanded: true,
                  call: ToolCallPresentation.live(
                    GatewayToolActivity(
                      toolId: 'website-code',
                      name: 'execute_code',
                      phase: GatewayToolActivityPhase.completed,
                      arguments: jsonEncode({
                        'code':
                            'from pathlib import Path\n\nrecords = Path("research.csv")\nrows = records.read_text().splitlines()\nprint(f"Checked {len(rows) - 1} records")',
                      }),
                      result: jsonEncode({
                        'output': 'Checked 7 records\nSource dates preserved',
                        'success': true,
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await capture(tester, 'tool-${brightness.name}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
