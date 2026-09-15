/// Manual Android UI checks using the shipped screen/controller and an isolated
/// gateway fixture. Build as a debug entry point, install with adb install -r,
/// and restore lib/main.dart afterward. Never install this in Wing.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import '../test/support/profile_browser_fixture.dart';

class DeviceFixture extends ProfileBrowserFixture {
  ProfileGateway? active;
  int replies = 0;
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {'id': 1, 'role': 'user', 'content': 'Review the landing page only.'},
    {
      'id': 2,
      'role': 'tool',
      'tool_name': 'Read project',
      'content': 'Disposable device test',
    },
    {
      'id': 3,
      'role': 'tool',
      'tool_name': 'Inspect files',
      'content': 'No server request',
    },
    {
      'id': 4,
      'role': 'assistant',
      'content':
          '## Keep the review focused\n\nThe landing page is the current review. Other routes are **future work**.\n\n'
          '> Navigation currently opens the prototype. This matters before publishing, but it should not interrupt the landing-page review.\n\n'
          '### Next steps\n\n- Review the `/target/` landing page.\n- Keep the agreed scope.\n\n'
          '---\n\n| Area | Status |\n| --- | --- |\n| Landing page | In review |\n| Other routes | Planned |\n\n'
          '```dart\nfinal profile = "personal";\n```',
    },
  ];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return active = ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) async {
        if (method != 'clarify.lock') return base.call(method, params);
        if (params['profile'] != 'personal' ||
            params['session_id'] != 'runtime' ||
            params['request_id'] != 'device-question') {
          throw StateError('Device QA response identity mismatch');
        }
        replies++;
        debugPrint(
          'DEVICE_QA reply=$replies question=${params['question_id']} answer=${params['answer']}',
        );
        if (replies == 1) throw StateError('Authored retry test');
        return {
          'status': 'ok',
          'remaining': params['question_id'] == 'q1' ? ['q2'] : [],
        };
      },
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // No disk credentials or production configuration are read or written.
  SharedPreferences.setMockInitialValues({});
  runApp(const DeviceCheck());
}

class DeviceCheck extends StatefulWidget {
  const DeviceCheck({super.key});
  @override
  State<DeviceCheck> createState() => _DeviceCheckState();
}

class _DeviceCheckState extends State<DeviceCheck> {
  ProfileWorkspaceController? controller;
  Brightness brightness = Brightness.dark;
  double scale = 1;
  Future<void> open({
    bool question = false,
    bool light = false,
    bool large = false,
  }) async {
    final fixture = DeviceFixture();
    final next = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'device-check',
        label: 'Device QA',
        host: 'unused',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'isolated-device-check',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await next.initialize();
    await next.openSession(
      ProfileSessionKey(next.current!.scope, 'device-check'),
    );
    final chat = next.current!.chat!;
    chat.title = question ? 'Question device check' : 'Markdown device check';
    if (question) {
      fixture.active!.onEvent!(
        StreamEvent(
          type: 'clarify',
          sessionId: chat.runtimeId,
          data: {
            'request_id': 'device-question',
            'questions': [
              {
                'qid': 'q1',
                'question':
                    'The landing page is ready for a design and copy review. The other routes still belong to an earlier prototype and are outside the current scope. Which type of review should I run before we continue?',
                'choices': [
                  'Detailed review of layout and copy (Recommended)',
                  'Quick review of the main issues',
                  'Wait until the other routes are ready',
                ],
              },
              {
                'qid': 'q2',
                'question': 'Which areas should I focus on?',
                'choices': ['Layout', 'Copy', 'Accessibility'],
                'multi_select': true,
              },
            ],
          },
        ),
      );
    }
    setState(() {
      controller = next;
      brightness = light ? Brightness.light : Brightness.dark;
      scale = large ? 2 : 1;
    });
    debugPrint('DEVICE_QA ready question=$question light=$light large=$large');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: hermesTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: controller == null
        ? Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Isolated Android device check'),
                    FilledButton(
                      onPressed: () => open(),
                      child: const Text('Dark quotes'),
                    ),
                    FilledButton(
                      onPressed: () => open(light: true),
                      child: const Text('Light quotes'),
                    ),
                    FilledButton(
                      onPressed: () => open(question: true),
                      child: const Text('Questions and retry'),
                    ),
                    FilledButton(
                      onPressed: () => open(question: true, large: true),
                      child: const Text('Questions large text'),
                    ),
                  ],
                ),
              ),
            ),
          )
        : ProfileWorkspaceScreen(controller: controller!),
  );
}
