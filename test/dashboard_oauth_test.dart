import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_connection_identity.dart';

class _Store implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

DashboardOAuthSession _session({
  bool expired = true,
  http.Client Function()? client,
  Future<void> Function()? persist,
}) => DashboardOAuthSession(
  id: 'grant',
  baseUrl: 'https://agent.example/hermes',
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
  expiresAt: expired
      ? DateTime.utc(2020)
      : DateTime.now().add(const Duration(hours: 1)),
  createClient: client,
  persist: persist,
);

http.Response _tokens() => http.Response(
  jsonEncode({
    'provider': 'nous',
    'access_token': 'new-access',
    'refresh_token': 'new-refresh',
    'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'parallel renewal exchanges one rotating grant and persists before use',
    () async {
      var exchanges = 0, saves = 0;
      final release = Completer<void>();
      final session = _session(
        client: () => MockClient((request) async {
          exchanges++;
          expect(
            request.url.toString(),
            'https://agent.example/hermes/auth/native/refresh',
          );
          expect(request.followRedirects, false);
          expect(jsonDecode(request.body), {
            'provider': 'nous',
            'refresh_token': 'old-refresh',
          });
          await release.future;
          return _tokens();
        }),
        persist: () async {
          saves++;
        },
      );
      final requests = List.generate(
        8,
        (_) => session.bearerFor('https://agent.example:443/hermes/'),
      );
      release.complete();
      expect(await Future.wait(requests), everyElement('new-access'));
      expect(exchanges, 1);
      expect(saves, 1);
    },
  );

  test(
    'failed secure save retries rotated tokens without replaying refresh',
    () async {
      var exchanges = 0, saves = 0;
      final session = _session(
        client: () => MockClient((_) async {
          exchanges++;
          return _tokens();
        }),
        persist: () async {
          if (++saves == 1) throw StateError('storage unavailable');
        },
      );
      await expectLater(
        session.bearerFor(session.baseUrl),
        throwsA(isA<CloudAccessException>()),
      );
      expect(session.refreshToken, 'new-refresh');
      expect(await session.bearerFor(session.baseUrl), 'new-access');
      expect(exchanges, 1);
      expect(saves, 2);
    },
  );

  test('grant cannot be forwarded to another origin or path', () async {
    final session = _session(expired: false);
    for (final url in [
      'https://elsewhere.example/hermes',
      'https://agent.example/other',
      'http://agent.example/hermes',
    ]) {
      await expectLater(session.bearerFor(url), throwsA(anything));
    }
  });

  test(
    'OAuth dashboard uses bearer, then a single-use WebSocket ticket',
    () async {
      final client = DashboardClient(
        host: 'agent.example',
        port: 443,
        useHttps: true,
        pathPrefix: '/hermes',
        dashboardOAuth: _session(expired: false),
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer old-access');
          expect(request.headers, isNot(contains('Cookie')));
          expect(request.headers, isNot(contains('X-Hermes-Session-Token')));
          expect(request.url.path, '/hermes/api/auth/ws-ticket');
          return http.Response('{"ticket":"single-use"}', 200);
        }),
      );
      expect(await client.gatewayCredentials(), (
        token: null,
        ticket: 'single-use',
      ));
      client.close();
    },
  );

  test(
    'late 401 from an old bearer does not invalidate an already renewed grant',
    () async {
      var exchanges = 0;
      final session = _session(
        expired: false,
        client: () => MockClient((_) async {
          exchanges++;
          return _tokens();
        }),
      );
      final lateResponse = Completer<void>();
      final client = DashboardClient(
        host: 'agent.example',
        port: 443,
        useHttps: true,
        pathPrefix: '/hermes',
        dashboardOAuth: session,
        httpClient: MockClient((request) async {
          if (request.headers['Authorization'] == 'Bearer old-access') {
            if (request.url.path.endsWith('/second')) await lateResponse.future;
            return http.Response('{}', 401, request: request);
          }
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response('{}', 200, request: request);
        }),
      );
      final first = client.apiGet('first');
      final second = client.apiGet('second');
      await first;
      lateResponse.complete();
      await second;
      expect(exchanges, 1);
      client.close();
    },
  );

  test(
    'restored Cloud without grant fails closed before any HTTP request',
    () async {
      final client = DashboardClient(
        host: 'agent.example',
        useHttps: true,
        requiresOAuth: true,
        httpClient: MockClient(
          (_) async =>
              throw StateError('Must never fetch SPA or password login'),
        ),
      );
      await expectLater(
        client.apiGet('profiles'),
        throwsA(isA<CloudAccessException>()),
      );
      client.close();
    },
  );

  test(
    'secure grant is shared, survives reload and keeps ownership stable on rotation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = _Store();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );
      final session = _session(
        client: () => MockClient((_) async => _tokens()),
      );
      final saved = await manager.saveConnection(
        'Research',
        'https://agent.example',
        443,
        '',
        dashboardPrefix: '/hermes',
        cloudInstanceId: 'instance',
        cloudOrganization: 'team',
        dashboardOAuth: session,
      );
      expect(
        prefs.getStringList('saved_connections')!.join(),
        isNot(contains('old-access')),
      );
      expect(
        prefs.getStringList('saved_connections')!.join(),
        isNot(contains('old-refresh')),
      );
      final hydrated = manager.getConnections().single;
      expect(identical(hydrated.dashboardOAuth, session), true);
      final identity = ProfileConnectionIdentity(credentialStore: store);
      final before = await identity.resolve(saved);
      expect(
        await hydrated.dashboardOAuth!.bearerFor(session.baseUrl),
        'new-access',
      );
      expect(await identity.resolve(saved), before);
      final stored = store.values.values.firstWhere(
        (v) => v.contains('dashboard_oauth'),
      );
      expect(
        jsonDecode(stored)['dashboard_oauth']['refresh_token'],
        'new-refresh',
      );
      final loaded = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );
      expect(
        identical(loaded.getConnections().single.dashboardOAuth, session),
        true,
      );
      await manager.deleteConnection(saved.id);
      await expectLater(
        session.persist!(),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(
        store.values.values.any((v) => v.contains('refresh_token')),
        false,
      );
    },
  );
}
