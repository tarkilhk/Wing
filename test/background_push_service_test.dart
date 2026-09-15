import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/background_push_service.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/turn_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryCredentialStore implements CredentialStore {
  final values = <String, String>{
    'profile_connection_identity_key_v1': base64Encode(List.filled(32, 7)),
  };

  @override
  String? readCached(String key) => values[key];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _RegistrationCall {
  final SavedConnection connection;
  final WorkspaceScope workspace;
  final String installationId;
  final String token;
  final String applicationId;
  final PushPreferences preferences;

  const _RegistrationCall({
    required this.connection,
    required this.workspace,
    required this.installationId,
    required this.token,
    required this.applicationId,
    required this.preferences,
  });
}

class _FakeTransport implements PushRegistrationTransport {
  final profilesByConnection = <String, List<HermesProfile>>{};
  final registerCalls = <_RegistrationCall>[];
  final unregisterCalls = <PushRegistrationRecord>[];
  final failProfiles = <String>{};
  final failRegistrationProfiles = <String>{};
  Completer<void>? profilesDelay;

  @override
  Future<List<HermesProfile>> profiles(
    SavedConnection connection,
    String connectionIdentity,
  ) async {
    await profilesDelay?.future;
    if (failProfiles.contains(connection.id)) throw StateError('offline');
    return profilesByConnection[connection.id] ?? const [];
  }

  @override
  Future<PushRegistrationRecord> register({
    required SavedConnection connection,
    required WorkspaceScope workspace,
    required String installationId,
    required String fcmToken,
    required String applicationId,
    required PushPreferences preferences,
  }) async {
    registerCalls.add(
      _RegistrationCall(
        connection: connection,
        workspace: workspace,
        installationId: installationId,
        token: fcmToken,
        applicationId: applicationId,
        preferences: preferences,
      ),
    );
    if (failRegistrationProfiles.contains(workspace.profileName)) {
      throw StateError('rejected');
    }
    return PushRegistrationRecord(
      registrationId: 'registration-${workspace.profileName}',
      workspace: workspace,
    );
  }

  @override
  Future<void> unregister({
    required SavedConnection connection,
    required PushRegistrationRecord registration,
  }) async {
    unregisterCalls.add(registration);
  }
}

SavedConnection _connection(String id) => SavedConnection(
  id: id,
  label: id,
  host: 'hermes.example',
  port: 443,
  apiKey: 'test-key',
  useHttps: true,
);

void main() {
  late SharedPreferences preferences;
  late _FakeTransport transport;
  late PushRegistrationCoordinator coordinator;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    transport = _FakeTransport();
    coordinator = PushRegistrationCoordinator(
      preferences: preferences,
      identities: ProfileConnectionIdentity(
        credentialStore: _MemoryCredentialStore(),
      ),
      transport: transport,
      installationIdFactory: () => 'installation-1',
    );
  });

  test(
    'registers every discovered profile with one stable installation',
    () async {
      final connection = _connection('primary');
      transport.profilesByConnection[connection.id] = const [
        HermesProfile(name: 'personal'),
        HermesProfile(name: 'work'),
      ];
      const pushPreferences = PushPreferences(
        completion: true,
        attention: false,
        includeChatTitle: true,
      );

      final first = await coordinator.sync(
        connections: [connection],
        fcmToken: 'token-1',
        applicationId: 'com.tarkilhk.wing',
        pushPreferences: pushPreferences,
      );
      final second = await coordinator.sync(
        connections: [connection],
        fcmToken: 'token-2',
        applicationId: 'com.tarkilhk.wing',
        pushPreferences: pushPreferences,
      );

      expect(first.registered, 2);
      expect(second.registered, 2);
      expect(transport.registerCalls, hasLength(4));
      expect(
        transport.registerCalls.map((call) => call.installationId).toSet(),
        {'installation-1'},
      );
      expect(transport.registerCalls.last.token, 'token-2');
      expect(transport.registerCalls.last.applicationId, 'com.tarkilhk.wing');
      expect(transport.registerCalls.last.preferences.toJson(), {
        'completion': true,
        'attention': false,
        'include_chat_title': true,
      });
      expect(
        jsonDecode(preferences.getString('background_push_registrations_v1')!),
        hasLength(2),
      );
    },
  );

  test('queues a newer token while registration is in flight', () async {
    final connection = _connection('primary');
    transport.profilesByConnection[connection.id] = const [
      HermesProfile(name: 'personal'),
    ];
    transport.profilesDelay = Completer<void>();
    const pushPreferences = PushPreferences(
      completion: true,
      attention: true,
      includeChatTitle: false,
    );

    final first = coordinator.sync(
      connections: [connection],
      fcmToken: 'old-token',
      applicationId: 'com.tarkilhk.wing',
      pushPreferences: pushPreferences,
    );
    final second = coordinator.sync(
      connections: [connection],
      fcmToken: 'new-token',
      applicationId: 'com.tarkilhk.wing',
      pushPreferences: pushPreferences,
    );
    await Future<void>.delayed(Duration.zero);
    transport.profilesDelay!.complete();
    await Future.wait([first, second]);

    expect(transport.registerCalls.map((call) => call.token), [
      'old-token',
      'new-token',
    ]);
  });

  test('unregisters with the previous connection credentials', () async {
    final connection = _connection('primary');
    transport.profilesByConnection[connection.id] = const [
      HermesProfile(name: 'personal'),
    ];
    const pushPreferences = PushPreferences(
      completion: true,
      attention: true,
      includeChatTitle: false,
    );
    await coordinator.sync(
      connections: [connection],
      fcmToken: 'token',
      applicationId: 'com.tarkilhk.wing',
      pushPreferences: pushPreferences,
    );

    final result = await coordinator.unregisterConnection(connection);

    expect(result.removed, 1);
    expect(transport.unregisterCalls.single.workspace.profileName, 'personal');
    expect(
      jsonDecode(preferences.getString('background_push_registrations_v1')!),
      isEmpty,
    );
  });

  test('gateway removal sends authenticated profile query', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final connection = SavedConnection(
      id: 'primary',
      label: 'Primary',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      apiKey: '',
      useHttps: false,
      dashboardPortOverride: server.port,
      dashboardUsername: 'mobile',
      dashboardPassword: 'secret',
    );
    final requests = StreamIterator<HttpRequest>(server);
    final removal = GatewayPushRegistrationTransport().unregister(
      connection: connection,
      registration: PushRegistrationRecord(
        registrationId: 'registration/one',
        workspace: WorkspaceScope(
          connectionId: 'primary',
          connectionIdentity: 'owner',
          profileName: 'personal',
        ),
      ),
    );
    expect(await requests.moveNext(), isTrue);
    final login = requests.current;
    expect(login.method, 'POST');
    expect(login.uri.path, '/auth/password-login');
    expect(
      await utf8.decoder.bind(login).join(),
      contains('"username":"mobile"'),
    );
    login.response.headers.add(
      HttpHeaders.setCookieHeader,
      'hermes_session_at=test-session; Path=/; HttpOnly',
    );
    login.response.statusCode = HttpStatus.ok;
    await login.response.close();

    expect(await requests.moveNext(), isTrue);
    final request = requests.current;
    await request.drain<void>();
    expect(request.method, 'DELETE');
    expect(
      request.uri.toString(),
      contains('/api/mobile/push/installations/registration%2Fone'),
    );
    expect(request.uri.queryParameters, {'profile': 'personal'});
    expect(
      request.headers.value(HttpHeaders.cookieHeader),
      'hermes_session_at=test-session',
    );
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    await removal;
    await requests.cancel();
  });

  test(
    'delivery ledger preserves distinct events and rejects repeats',
    () async {
      final ledger = PushDeliveryLedger(preferences);

      expect(await ledger.claim('first'), isTrue);
      expect(await ledger.claim('first'), isFalse);
      expect(await ledger.claim('second'), isTrue);
      await ledger.release('first');
      expect(await ledger.claim('first'), isTrue);
    },
  );

  test(
    'queued push honors current owner, category, and title preference',
    () async {
      final credentialStore = _MemoryCredentialStore();
      final manager = ConnectionManager(
        preferences,
        credentialStore: credentialStore,
      );
      await manager.saveConnection(
        'Primary',
        'hermes.example',
        443,
        'test-key',
      );
      final connection = (await manager.loadConnectionsWithSecrets()).single;
      final identity = await ProfileConnectionIdentity(
        credentialStore: credentialStore,
      ).resolve(connection);
      final authorizer = PushMessageAuthorizer(
        preferences: preferences,
        connectionManager: manager,
        identities: ProfileConnectionIdentity(credentialStore: credentialStore),
      );
      final message = BackgroundPushMessage.fromData({
        'schema_version': '1',
        'event_id': 'event-1',
        'event_type': 'completion',
        'target': jsonEncode({
          'connection': connection.id,
          'connection_identity': identity,
          'profile': 'personal',
          'session': 'chat-1',
        }),
        'title': 'Remote title',
        'body': 'Private chat title',
      });

      final generic = await authorizer.notificationFor(message);
      expect(generic?.title, 'Hermes finished');
      expect(generic?.body, 'Open to view the result');

      await preferences.setBool(notificationTitlesKey, true);
      final preview = await authorizer.notificationFor(message);
      expect(preview?.title, 'Remote title');
      expect(preview?.body, 'Private chat title');

      await preferences.setBool(completionNotificationsKey, false);
      expect(await authorizer.notificationFor(message), isNull);

      await preferences.setBool(completionNotificationsKey, true);
      await manager.updateApiKey(connection.id, 'rotated-key');
      expect(await authorizer.notificationFor(message), isNull);
    },
  );

  test('disabled preferences remove registrations using their owner', () async {
    final connection = _connection('primary');
    transport.profilesByConnection[connection.id] = const [
      HermesProfile(name: 'personal'),
    ];
    await coordinator.sync(
      connections: [connection],
      fcmToken: 'token',
      applicationId: 'com.tarkilhk.wing',
      pushPreferences: const PushPreferences(
        completion: true,
        attention: true,
        includeChatTitle: false,
      ),
    );

    final result = await coordinator.sync(
      connections: [connection],
      fcmToken: 'token',
      applicationId: 'com.tarkilhk.wing',
      pushPreferences: const PushPreferences(
        completion: false,
        attention: false,
        includeChatTitle: false,
      ),
    );

    expect(result.removed, 1);
    expect(transport.unregisterCalls.single.workspace.profileName, 'personal');
    expect(
      jsonDecode(preferences.getString('background_push_registrations_v1')!),
      isEmpty,
    );
  });

  test('failed discovery retains prior registration for later retry', () async {
    final connection = _connection('primary');
    transport.profilesByConnection[connection.id] = const [
      HermesProfile(name: 'personal'),
    ];
    const pushPreferences = PushPreferences(
      completion: true,
      attention: true,
      includeChatTitle: false,
    );
    await coordinator.sync(
      connections: [connection],
      fcmToken: 'token',
      applicationId: 'com.tarkilhk.wing',
      pushPreferences: pushPreferences,
    );
    transport.failProfiles.add(connection.id);

    final result = await coordinator.sync(
      connections: [connection],
      fcmToken: 'rotated-token',
      applicationId: 'com.tarkilhk.wing',
      pushPreferences: pushPreferences,
    );

    expect(result.failed, 1);
    expect(
      jsonDecode(preferences.getString('background_push_registrations_v1')!),
      hasLength(1),
    );
  });

  test(
    'removed connections drop local routes that can no longer authenticate',
    () async {
      final connection = _connection('primary');
      transport.profilesByConnection[connection.id] = const [
        HermesProfile(name: 'personal'),
      ];
      const pushPreferences = PushPreferences(
        completion: true,
        attention: true,
        includeChatTitle: false,
      );
      await coordinator.sync(
        connections: [connection],
        fcmToken: 'token',
        applicationId: 'com.tarkilhk.wing',
        pushPreferences: pushPreferences,
      );

      await coordinator.sync(
        connections: const [],
        fcmToken: 'token',
        applicationId: 'com.tarkilhk.wing',
        pushPreferences: pushPreferences,
      );

      expect(
        jsonDecode(preferences.getString('background_push_registrations_v1')!),
        isEmpty,
      );
    },
  );

  test('push data reuses the authenticated notification target', () {
    final target = jsonEncode({
      'connection': 'primary',
      'connection_identity': 'owner-hash',
      'profile': 'personal',
      'session': 'chat-1',
    });

    final message = BackgroundPushMessage.fromData({
      'schema_version': '1',
      'event_id': 'event-1',
      'event_type': 'input_required',
      'target': target,
      'title': 'Hermes needs your input',
      'body': 'Open to respond',
      'request_id': 'request-1',
    });

    expect(message.target, target);
    expect(message.notification(includeServerText: true).payload, target);
    expect(
      message.notification(includeServerText: true).title,
      'Hermes needs your input',
    );
    expect(
      message.notification(includeServerText: true).body,
      'Open to respond',
    );
  });

  test('accepts a generic error event without error details', () {
    final target = jsonEncode({
      'connection': 'primary',
      'connection_identity': 'owner-hash',
      'profile': 'personal',
      'session': 'chat-1',
    });
    final message = BackgroundPushMessage.fromData({
      'schema_version': '1',
      'event_id': 'failed-event',
      'event_type': 'error',
      'target': target,
    });
    expect(message.eventType, 'error');
  });

  test('rejects malformed, unsupported, and incomplete push data', () {
    expect(
      () => BackgroundPushMessage.fromData(const {}),
      throwsFormatException,
    );
    expect(
      () => BackgroundPushMessage.fromData({
        'schema_version': '2',
        'event_id': 'event',
        'event_type': 'completion',
        'target': '{}',
      }),
      throwsFormatException,
    );
    expect(
      () => BackgroundPushMessage.fromData({
        'schema_version': '1',
        'event_id': 'event',
        'event_type': 'unknown',
        'target': '{}',
      }),
      throwsFormatException,
    );
  });
}
