import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FaultInjectingCredentialStore implements CredentialStore {
  final Map<String, String> values = <String, String>{};
  final Map<String, String> _cache = <String, String>{};

  int reads = 0;
  int writes = 0;
  int deletes = 0;
  bool failNextRead = false;
  bool _failCredentialReadBack = false;

  @override
  Future<void> delete(String key) async {
    deletes += 1;
    values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    reads += 1;
    if (_failCredentialReadBack &&
        key.startsWith('connection_credentials_v1.')) {
      _failCredentialReadBack = false;
      _cache.remove(key);
      return null;
    }

    final value = values[key];
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<void> write(String key, String value) async {
    writes += 1;
    values[key] = value;
    if (failNextRead && key.startsWith('connection_credentials_v1.')) {
      failNextRead = false;
      _failCredentialReadBack = true;
    }
  }
}

String _legacyConnection({
  required String id,
  required String label,
  required String host,
  String apiKey = '',
  String? dashboardPassword,
  int port = 8642,
  String? gatewayPrefix,
}) {
  return jsonEncode(<String, Object?>{
    'id': id,
    'label': label,
    'host': host,
    'port': port,
    'api_key': apiKey,
    'use_https': false,
    'gateway_prefix': gatewayPrefix,
    'dashboard_username': dashboardPassword == null ? null : 'operator',
    'dashboard_password': dashboardPassword,
  });
}

List<Map<String, dynamic>> _storedMetadata(SharedPreferences prefs) {
  return (prefs.getStringList('saved_connections') ?? const <String>[])
      .map((value) => jsonDecode(value) as Map<String, dynamic>)
      .toList();
}

void _expectNoPlaintextCredentials(SharedPreferences prefs) {
  final metadata = _storedMetadata(prefs);
  for (final connection in metadata) {
    expect(connection, isNot(contains('api_key')));
    expect(connection, isNot(contains('dashboard_password')));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'modern metadata hydrates from secure storage without rewriting secrets',
    () async {
      final connections = [
        SavedConnection(
          id: 'profile-a',
          label: 'A',
          host: 'a.example',
          port: 8642,
          apiKey: '',
        ),
        SavedConnection(
          id: 'profile-b',
          label: 'B',
          host: 'b.example',
          port: 8642,
          apiKey: '',
        ),
      ];
      SharedPreferences.setMockInitialValues({
        'saved_connections': connections
            .map((c) => jsonEncode(c.toMap()))
            .toList(),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = _FaultInjectingCredentialStore();
      for (final connection in connections) {
        final id = base64Url
            .encode(utf8.encode(connection.id))
            .replaceAll('=', '');
        store.values['connection_credentials_v1.$id'] = jsonEncode({
          'api_key': 'synthetic-${connection.id}',
        });
      }
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );
      expect(manager.getConnections().map((c) => c.apiKey), [
        'synthetic-profile-a',
        'synthetic-profile-b',
      ]);
      expect(store.writes, 0);
      _expectNoPlaintextCredentials(prefs);
      final other = ConnectionManager(prefs, credentialStore: store);
      expect(other.getConnections().first.apiKey, 'synthetic-profile-a');
      await manager.initialize();
      expect(store.writes, 0);
    },
  );

  test(
    'plaintext legacy metadata is rejected without migrating or deleting it',
    () async {
      final legacy = [
        _legacyConnection(
          id: 'legacy',
          label: 'Old',
          host: 'old.example',
          apiKey: 'synthetic-old-secret',
        ),
      ];
      SharedPreferences.setMockInitialValues({'saved_connections': legacy});
      final prefs = await SharedPreferences.getInstance();
      final store = _FaultInjectingCredentialStore();
      final manager = ConnectionManager(prefs, credentialStore: store);
      await expectLater(
        manager.initialize(),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(
        manager.getConnections,
        throwsA(isA<CredentialStorageException>()),
      );
      expect(prefs.getStringList('saved_connections'), legacy);
      expect(store.values, isEmpty);
      expect(store.writes, 0);
    },
  );

  test('update, clear, and delete keep secure storage synchronized', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FaultInjectingCredentialStore();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );

    await manager.saveConnection(
      'Home',
      '192.0.2.10',
      8642,
      'synthetic-api-old',
      dashboardUsername: 'operator',
      dashboardPassword: 'synthetic-password-old',
    );
    final original = manager.getConnections().single;
    expect(store.values, hasLength(1));
    _expectNoPlaintextCredentials(prefs);

    await manager.updateConnection(
      original.id,
      'Moved',
      'https://hermes.example.com',
      8642,
      'synthetic-api-new',
      dashboardUsername: 'operator',
      dashboardPassword: 'synthetic-password-new',
    );
    var updated = manager.getConnections().single;
    expect(updated.id, original.id);
    expect(updated.label, 'Moved');
    expect(updated.host, 'hermes.example.com');
    expect(updated.port, 443);
    expect(updated.apiKey, 'synthetic-api-new');
    expect(updated.dashboardPassword, 'synthetic-password-new');
    _expectNoPlaintextCredentials(prefs);

    await manager.updateApiKey(original.id, '');
    await manager.updateDashboardAuth(original.id, username: '', password: '');
    updated = manager.getConnections().single;
    expect(updated.apiKey, isEmpty);
    expect(updated.dashboardPassword, isNull);
    expect(store.values, isEmpty);
    _expectNoPlaintextCredentials(prefs);

    await manager.updateApiKey(original.id, 'synthetic-api-restored');
    expect(store.values, hasLength(1));
    await manager.deleteConnection(original.id);
    expect(manager.getConnections(), isEmpty);
    expect(_storedMetadata(prefs), isEmpty);
    expect(store.values, isEmpty);
  });

  test('gateway headers stay secure and update as one verified set', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FaultInjectingCredentialStore();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );

    await manager.saveConnection(
      'Proxy',
      'proxy.example.test',
      443,
      '',
      gatewayHeaders: <String, String>{
        'X-Access-Client': 'mobile',
        'X-Access-Secret': 'private-old',
      },
    );
    final original = manager.getConnections().single;
    expect(original.gatewayHeaders['X-Access-Secret'], 'private-old');
    expect(jsonEncode(_storedMetadata(prefs)), isNot(contains('private-old')));
    expect(store.values.values.single, contains('private-old'));

    await manager.updateConnection(
      original.id,
      original.label,
      original.host,
      original.port,
      original.apiKey,
      gatewayHeaders: <String, String?>{
        'x-access-secret': null,
        'X-Access-Zone': 'edge',
      },
    );
    final updated = manager.getConnections().single;
    expect(updated.gatewayHeaders, <String, String>{
      'X-Access-Secret': 'private-old',
      'X-Access-Zone': 'edge',
    });
    expect(jsonEncode(_storedMetadata(prefs)), isNot(contains('private-old')));
    expect(jsonEncode(_storedMetadata(prefs)), isNot(contains('edge')));

    final recreated = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );
    expect(
      recreated.getConnections().single.gatewayHeaders,
      updated.gatewayHeaders,
    );

    store.failNextRead = true;
    await expectLater(
      recreated.updateConnection(
        original.id,
        original.label,
        original.host,
        original.port,
        original.apiKey,
        gatewayHeaders: <String, String?>{
          'X-Access-Secret': 'private-rejected',
        },
      ),
      throwsA(isA<CredentialStorageException>()),
    );
    expect(
      recreated.getConnections().single.gatewayHeaders,
      updated.gatewayHeaders,
    );
    expect(jsonEncode(_storedMetadata(prefs)), isNot(contains('private')));
  });

  test('failed update read-back restores the prior credentials', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FaultInjectingCredentialStore();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );
    await manager.saveConnection(
      'Home',
      '192.0.2.10',
      8642,
      'synthetic-api-stable',
      dashboardPassword: 'synthetic-password-stable',
    );
    final id = manager.getConnections().single.id;

    store.failNextRead = true;
    await expectLater(
      manager.updateApiKey(id, 'synthetic-api-rejected'),
      throwsA(isA<CredentialStorageException>()),
    );

    final retained = manager.getConnections().single;
    expect(retained.apiKey, 'synthetic-api-stable');
    expect(retained.dashboardPassword, 'synthetic-password-stable');
    _expectNoPlaintextCredentials(prefs);
  });
}
