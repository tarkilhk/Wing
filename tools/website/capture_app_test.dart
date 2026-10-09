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
import 'package:wing/core/presentation/tool_call_presentation.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/composer_action_button.dart';
import 'package:wing/core/widgets/profile_tool_call.dart';

import '../../test/helpers/pump_markdown_widget.dart';
import '../../test/support/profile_browser_fixture.dart';

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
      },
  ];

  @override
  List<Map<String, dynamic>> projects(String profile) => [
    for (final project in super.projects(profile))
      {
        ...project,
        if (project['id'] == 'p2') 'label': 'Research',
        'sessionIds': project['id'] == 'p2'
            ? ['newest', 'project-only']
            : project['isNoProject'] == true
            ? ['old', 'pinned', 'pin-two', 'test', 'docs']
            : <String>[],
      },
  ];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) =>
      id != 'newest'
      ? []
      : [
          {
            'id': 1,
            'role': 'user',
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
      get: base.read,
      ownedPatch: (path, body, canDispatch, onDispatched) async {
        if (!canDispatch()) throw StateError('Capture retired');
        onDispatched();
        return {'ok': true};
      },
      rpc: (method, params) async {
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
            id: 'website-demo',
            label: 'My Hermes',
            host: 'unused',
            port: 1,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'website-demo',
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
