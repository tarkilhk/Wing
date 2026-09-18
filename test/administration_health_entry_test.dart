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
  final scopedRequests = <(String, String, Map<String, String>)>[];
  final explicitCalls = <String>[];
  final modelWrites = <(String, Map<String, dynamic>)>[];
  final models = <String, String>{};
  Map<String, dynamic> modelInfo(String profile) => {
    'model': models[profile] ?? 'gpt-5.6-sol',
    'provider': 'openai-codex',
  };
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
          get: (path, query) async {
            if (path == 'model/info') return modelInfo(scope.profileName);
            if (path == 'model/options') {
              return {
                'providers': [
                  {
                    'slug': 'openai-codex',
                    'name': 'OpenAI Codex',
                    'models': ['gpt-5.6-sol', 'gpt-6-astra'],
                  },
                ],
              };
            }
            return source.read(path, query);
          },
          post: (path, body) async {
            modelWrites.add((path, Map.of(body)));
            models[scope.profileName] = body['model'] as String;
            return {'ok': true};
          },
          rpc: (method, params) {
            explicitCalls.add('$method ${scope.profileName}');
            if (method == 'setup.runtime_check') {
              return Future.value({
                'ok': true,
                'profile': scope.profileName,
                ...modelInfo(scope.profileName),
              });
            }
            return source.call(method, params);
          },
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
      scopedRequests.add((method, path, Map.of(query)));
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
        'model/info' => modelInfo(query['profile']!),
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

  testWidgets(
    'model save refreshes selection and clears credentials for the captured profile',
    (tester) async {
      final fixture = _Fixture('green');
      await fixture.initialize();
      addTearDown(fixture.dispose);
      await fixture.workspace.switchProfile('client-work');
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: HermesHealthContent(
              controller: fixture.workspace,
              repository: fixture.repository,
              onOpenMenu: () {},
              onOpenSession: (_) async {},
              onConnections: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Model & provider'));
      await tester.tap(find.text('Model & provider'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Check access'));
      await tester.pumpAndSettle();
      expect(find.text('Credentials available'), findsOneWidget);
      await tester.tap(find.text('Change model'));
      await tester.pumpAndSettle();
      final option = find.byKey(
        const Key('profile-model-openai-codex-gpt-6-astra'),
      );
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-model-save')));
      await tester.pumpAndSettle();
      expect(fixture.modelWrites.single.$1, 'model/set?profile=client-work');
      expect(fixture.modelWrites.single.$2, {
        'scope': 'main',
        'provider': 'openai-codex',
        'model': 'gpt-6-astra',
      });
      expect(find.text('gpt-6-astra'), findsOneWidget);
      expect(find.text('Credentials not checked'), findsOneWidget);
      expect(
        fixture.explicitCalls.where((v) => v.startsWith('setup.runtime_check')),
        hasLength(1),
      );
      await tester.tap(find.byTooltip('Check access'));
      await tester.pumpAndSettle();
      expect(find.text('Credentials available'), findsOneWidget);
      expect(fixture.models['default'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Health owns scoped observations; profile check is explicit and read only',
    (tester) async {
      final fixture = _Fixture('green');
      await fixture.initialize();
      addTearDown(fixture.dispose);
      fixture.explicitCalls.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: Scaffold(
            body: HermesHealthContent(
              controller: fixture.workspace,
              repository: fixture.repository,
              onOpenMenu: () {},
              onOpenSession: (_) async {},
              onConnections: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        fixture.requests,
        containsAll([
          'GET model/info',
          'GET providers/oauth',
          'GET tools/toolsets',
          'GET mcp/servers',
          'GET cron/jobs',
        ]),
      );
      expect(
        fixture.explicitCalls.where((v) => v.startsWith('setup.runtime_check')),
        isEmpty,
      );
      expect(find.text('Not fully checked'), findsNothing);
      final before = fixture.scopedRequests.length;
      await fixture.workspace.switchProfile('client-work');
      await tester.pumpAndSettle();
      final switched = fixture.scopedRequests
          .skip(before)
          .where(
            (r) => const [
              'model/info',
              'providers/oauth',
              'tools/toolsets',
              'mcp/servers',
              'cron/jobs',
            ].contains(r.$2),
          );
      expect(switched, hasLength(5));
      expect(switched.every((r) => r.$3['profile'] == 'client-work'), isTrue);
      await tester.ensureVisible(find.byTooltip('Refresh profile status'));
      await tester.tap(find.byTooltip('Refresh profile status'));
      await tester.pumpAndSettle();
      expect(
        fixture.explicitCalls.where(
          (v) => v == 'setup.runtime_check client-work',
        ),
        hasLength(1),
      );
      expect(find.textContaining('Credentials available'), findsOneWidget);
      await tester.ensureVisible(find.text('Model & provider'));
      await tester.tap(find.text('Model & provider'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Credentials available'), findsOneWidget);
      expect(find.text('Provider configuration detected'), findsNothing);
      expect(
        find.text('Provider readiness is not fully observed'),
        findsNothing,
      );
      expect(find.text('Access checks'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('Manage provider access'), findsOneWidget);
      expect(find.text('gpt-5.6-sol'), findsOneWidget);
      expect(find.text('openai-codex'), findsOneWidget);
      await tester.tap(find.text('Change model'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Credentials available'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Credentials available'), findsOneWidget);
      expect(
        fixture.explicitCalls.where((v) => v.startsWith('setup.runtime_check')),
        hasLength(1),
      );
      expect(
        fixture.requests.where(
          (v) => v.startsWith('POST') || v.contains('ops/'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
                    appBar: AppBar(title: const Text('Hermes health')),
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
            expect(find.text('Server'), findsOneWidget);
            expect(
              fixture.requests,
              containsAll([
                'GET model/info',
                'GET providers/oauth',
                'GET tools/toolsets',
                'GET mcp/servers',
              ]),
            );
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
            expect(find.text('Not fully checked'), findsNothing);
            if (status == 'green' || large) {
              for (final title in [
                'Model & provider',
                'Tools',
                'Connectors',
                'Scheduled tasks',
              ]) {
                await tester.drag(vertical, const Offset(0, 3000));
                await tester.pumpAndSettle();
                await tester.scrollUntilVisible(
                  find.text(title),
                  200,
                  scrollable: vertical,
                );
                await tester.pumpAndSettle();
                await tester.tap(find.text(title));
                await tester.pumpAndSettle();
                await snapshot(tester, '$name-detail-$title');
                await tester.drag(
                  find.byType(Scrollable).first,
                  const Offset(0, -450),
                );
                await tester.pumpAndSettle();
                await snapshot(tester, '$name-detail-$title-lower');
                expect(tester.takeException(), isNull);
                await tester.pageBack();
                await tester.pumpAndSettle();
              }
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
