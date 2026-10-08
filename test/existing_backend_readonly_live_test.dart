import 'package:wing/core/services/connection_access.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/backend_update.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/services/ws_client.dart';

import 'support/existing_backend_login.dart';

/// Opt in with WING_HERMES_URL and WING_HERMES_LOGIN_FILE (a private JSON file
/// containing username/password). Credentials stay out of compiled defines and
/// output. Uses normal password sign-in and single-use WebSocket tickets.
/// Only health, discovery, schema/catalog reads and liveness RPCs are allowed;
/// no chats, transcripts, model calls, settings changes or server operations.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Platform.environment['WING_HERMES_URL'];
  final loginFile = Platform.environment['WING_HERMES_LOGIN_FILE'];
  final enabled = url != null && loginFile != null;
  late SavedConnection connection;
  late DashboardClient dashboard;
  late ProfileDiscovery discovery;
  HttpOverrides? overrides;

  setUpAll(() async {
    if (!enabled) return;
    overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    connection = await readExistingBackendConnection(
      url: url,
      loginFile: loginFile,
      id: 'existing-readonly',
    );
    dashboard = DashboardClient(
      host: connection.host,
      port: connection.dashboardPort,
      useHttps: connection.useHttps,
      pathPrefix: connection.dashboardPrefix ?? '',
      username: connection.dashboardUsername,
      password: connection.dashboardPassword,
    );
    addTearDown(dashboard.close);
    discovery = await ProfilesRepository(dashboard.apiGet).discover();
  });

  tearDownAll(() {
    if (enabled) HttpOverrides.global = overrides;
  });

  test(
    'existing server authenticates and exposes profile/version contracts',
    () async {
      expect(discovery.profiles.isNotEmpty, isTrue);
      expect(discovery.named('default') != null, isTrue);
      expect(discovery.named(discovery.currentName) != null, isTrue);
      final health = await dashboard.apiGet('status');
      expect(health['version'] is String, isTrue);
      expect(health['gateway_running'] is bool, isTrue);
      final identity = await dashboard.apiGet('auth/me');
      expect(identity['provider'] == 'basic', isTrue);
      final version = BackendUpdateCheck.fromJson(
        await dashboard.apiGet('hermes/update/check'),
      );
      expect(version.currentVersion?.isNotEmpty == true, isTrue);
      // Retain public version and counts only, never profile names or auth data.
      // ignore: avoid_print
      print(
        'EXISTING_HERMES_READONLY ${jsonEncode({'version': health['version'], 'profile_count': discovery.profiles.length, 'runtime_identity_available': discovery.currentName != null, 'authenticated': true})}',
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'existing default profile exposes scoped administration read contracts',
    () async {
      final gateway = ProfileGateway.forConnection(
        ConnectionAccess(connection: connection, dashboardOAuth: null),
        WorkspaceScope(connectionId: connection.id, profileName: 'default'),
      );
      addTearDown(gateway.close);
      final model = await gateway.read('model/info');
      expect(model.containsKey('model'), isTrue);
      final schema = await gateway.read('config/schema');
      expect(schema['fields'] is Map, isTrue);
      for (final endpoint in ['skills', 'tools/toolsets']) {
        final catalog = await gateway.read(endpoint);
        expect(catalog['data'] is List, isTrue, reason: endpoint);
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'existing gateway authenticates a ticket and answers read-only RPCs',
    () async {
      final credentials = await dashboard.gatewayCredentials();
      expect(credentials.token == null && credentials.ticket != null, isTrue);
      final socket = WsClient(dashboard.baseUrl, ticket: credentials.ticket);
      addTearDown(socket.close);
      await socket.connect();
      final ready = await socket.waitForGatewayReady();
      expect(ready.isNotEmpty, isTrue);
      final ping = await socket.send('ping', {});
      expect(ping['error'] == null, isTrue);
      expect(ping['result'] is Map && ping['result']['pong'] == true, isTrue);
      final capabilities = await socket.send('gateway.capabilities', {});
      expect(capabilities['error'] == null, isTrue);
      expect(capabilities['result'] is Map, isTrue);
      expect(
        capabilities['result']['per_session_exclusive_submit'] is bool,
        isTrue,
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
