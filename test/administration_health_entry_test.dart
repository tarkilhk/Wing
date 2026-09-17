import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/administration/administration_content.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/administration_fixture.dart';
import 'support/profile_browser_fixture.dart';

const _profiles = [
  HermesProfile(name: 'default', isDefault: true),
  HermesProfile(name: 'client-work'),
  HermesProfile(name: 'reminder-inbox'),
  HermesProfile(name: 'shared'),
  HermesProfile(name: 'research-and-writing'),
];

class _Fixture {
  _Fixture(this.status);
  final String status;
  final requests = <String>[];
  final base = AdministrationFixture('Claw');
  late ProfileWorkspaceController workspace;
  late AdministrationRepository repository;
  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    final discovery = ProfileDiscovery(
      profiles: _profiles,
      currentName: 'reminder-inbox',
      activeName: 'default',
    );
    final browser = ProfileBrowserFixture();
    workspace = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'Claw',
        label: 'Claw',
        host: 'localhost',
        port: 1,
        apiKey: '',
        icon: ConnectionIcon.home,
      ),
      connectionIdentity: 'Claw-endpoint',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: (scope) {
        final source = browser.gateway(scope);
        return ProfileGateway(
          scope: scope,
          get: source.read,
          rpc: source.call,
          discover: () async => discovery,
        );
      },
    );
    await workspace.initialize();
    await workspace.switchProfile('default');
    workspace.connectionStatus.accessAvailable();
    workspace.connectionStatus.liveChanged('default', true);
    Future<Map<String, dynamic>> read(
      String method,
      String path,
      Map<String, String> query,
      Map<String, dynamic>? body,
    ) async {
      requests.add('$method $path');
      if (method != 'GET') throw StateError('Unexpected write: $path');
      if (status == 'unknown' && path == 'tools/toolsets') {
        throw StateError('Unavailable');
      }
      return switch (path) {
        'profiles' => {
          'profiles': [
            for (final p in _profiles)
              {'name': p.name, 'is_default': p.isDefault},
          ],
        },
        'profiles/active' => {'current': 'reminder-inbox', 'active': 'default'},
        'config' => {
          'memory': {'memory_enabled': true, 'memory_char_limit': 2200},
          'agent': {'reasoning_effort': 'high'},
          'approvals': {'mode': 'smart'},
          'compression': {'enabled': true},
        },
        'model/info' => {'model': 'gpt-5.6-sol', 'provider': 'openai-codex'},
        'skills' => {
          'data': List.generate(
            126,
            (i) => {'name': 'skill-$i', 'enabled': true},
          ),
        },
        'tools/toolsets' => {
          'data': List.generate(
            21,
            (i) => {
              'name': 'tool-$i',
              'enabled': true,
              'configured': status != 'amber' || i != 0,
            },
          ),
        },
        'providers/oauth' => {
          'providers': [
            {
              'id': 'openai-codex',
              'name': 'OpenAI Codex',
              'flow': 'device_code',
              'status': {
                'logged_in': true,
                'source_label': 'OpenAI Codex',
                if (status == 'red') 'expires_at': '2020-01-01T00:00:00Z',
              },
            },
          ],
        },
        'mcp/servers' => {
          'servers': [
            {'name': 'example', 'enabled': true},
          ],
        },
        'cron/jobs' => {'data': []},
        _ => await base.send(method, path, query, body),
      };
    }

    repository = AdministrationRepository(
      connectionId: 'Claw',
      connectionIdentity: 'Claw-endpoint',
      connectionLabel: 'Claw',
      request: read,
      gateway: (name) => ProfileGateway(
        scope: WorkspaceScope(
          connectionId: 'Claw',
          connectionIdentity: 'Claw-endpoint',
          profileName: name,
        ),
        get: (p, q) => read('GET', p, {...q, 'profile': name}, null),
        discover: () async => discovery,
        rpc: (method, params) async {
          requests.add('RPC $method $name');
          if (method != 'setup.status') {
            throw StateError('Unexpected RPC: $method');
          }
          return {'profile': name, 'provider_configured': true};
        },
      ),
    );
  }

  void dispose() {
    workspace.dispose();
    repository.close();
  }
}

void main({
  Future<void> Function(WidgetTester tester, String name)? nativeCapture,
  bool useNativeViewport = false,
}) {
  const capture = bool.fromEnvironment('CAPTURE_ADMIN_HEALTH');
  if (capture) {
    setUpAll(() async {
      for (final e in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
      }.entries) {
        await (FontLoader(e.key)..addFont(
              File(
                '/tmp/wing-header-fonts/${e.value}',
              ).readAsBytes().then((b) => b.buffer.asByteData()),
            ))
            .load();
      }
    });
  }
  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!capture) {
      await nativeCapture?.call(tester, name);
      return;
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('health-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/administration-health/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final status in ['green', 'amber', 'red', 'unknown']) {
      for (final large in [false, if (status == 'amber') true]) {
        testWidgets(
          'health entry $status ${brightness.name} ${large ? 'large' : 'phone'}',
          (tester) async {
            final fixture = _Fixture(status);
            await fixture.initialize();
            addTearDown(fixture.dispose);
            if (!useNativeViewport) {
              tester.view.physicalSize = large
                  ? const Size(320, 640)
                  : const Size(412, 832);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
            }
            final scaffold = GlobalKey<ScaffoldState>();
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('health-capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: wingTheme(brightness),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: child!,
                  ),
                  home: Scaffold(
                    key: scaffold,
                    drawer: const Drawer(child: Text('Navigation')),
                    body: HermesHealthContent(
                      controller: fixture.workspace,
                      repository: fixture.repository,
                      onOpenMenu: () => scaffold.currentState!.openDrawer(),
                      onOpenSession: (_) async {},
                      onConnections: () {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(HermesHealthContent), findsOneWidget);
            expect(find.text('Selected profile'), findsAtLeastNWidgets(1));
            expect(find.byType(TabBar), findsNothing);
            final name =
                '$status-${brightness.name}-${large ? 'large' : 'phone'}';
            await snapshot(tester, '$name-overview');
            await snapshot(tester, '$name-health');
            final vertical = find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first;
            await tester.drag(vertical, const Offset(0, -700));
            await tester.pumpAndSettle();
            await snapshot(tester, '$name-health-lower');
            if (!large) {
              expect(
                find.byKey(const ValueKey('profile-default')),
                findsOneWidget,
              );
            }
            expect(
              fixture.requests.where(
                (r) => r.startsWith('POST') || r.contains('ops/'),
              ),
              isEmpty,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
