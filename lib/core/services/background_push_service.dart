import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/hermes_profile.dart';
import 'connection_manager.dart';
import 'profile_connection_identity.dart';
import 'profile_gateway.dart';
import 'profile_workspace_controller.dart';
import 'turn_notification_service.dart';

const _installationIdKey = 'background_push_installation_id_v1';
const _registrationsKey = 'background_push_registrations_v1';
const _deliveryIdsKey = 'background_push_delivery_ids_v1';
const _maxDeliveryIds = 64;
const backgroundPushPermissionRequestedKey =
    'background_push_permission_requested_v1';

/// Firebase identifiers supplied by the release build. These values identify a
/// Firebase app but do not contain the trusted sender credential.
FirebaseOptions? wingFirebaseOptions() {
  const apiKey = String.fromEnvironment('WING_FIREBASE_API_KEY');
  const appId = String.fromEnvironment('WING_FIREBASE_APP_ID');
  const senderId = String.fromEnvironment('WING_FIREBASE_MESSAGING_SENDER_ID');
  const projectId = String.fromEnvironment('WING_FIREBASE_PROJECT_ID');
  const storageBucket = String.fromEnvironment('WING_FIREBASE_STORAGE_BUCKET');
  if ([apiKey, appId, senderId, projectId].any((value) => value.isEmpty)) {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
  );
}

class PushPreferences {
  final bool completion;
  final bool attention;
  final bool includeChatTitle;

  const PushPreferences({
    required this.completion,
    required this.attention,
    required this.includeChatTitle,
  });

  factory PushPreferences.read(SharedPreferences preferences) =>
      PushPreferences(
        completion: preferences.getBool(completionNotificationsKey) ?? true,
        attention: preferences.getBool(attentionNotificationsKey) ?? true,
        includeChatTitle: preferences.getBool(notificationTitlesKey) ?? false,
      );

  bool get enabled => completion || attention;

  Map<String, bool> toJson() => {
    'completion': completion,
    'attention': attention,
    'include_chat_title': includeChatTitle,
  };
}

class PushRegistrationRecord {
  final String registrationId;
  final WorkspaceScope workspace;

  const PushRegistrationRecord({
    required this.registrationId,
    required this.workspace,
  });

  String get key =>
      '${workspace.connectionId}\u0000${workspace.connectionIdentity}\u0000'
      '${workspace.profileName}';

  Map<String, String> toJson() => {
    'registration_id': registrationId,
    'connection': workspace.connectionId,
    'connection_identity': workspace.connectionIdentity,
    'profile': workspace.profileName,
  };

  factory PushRegistrationRecord.fromJson(Map<String, dynamic> value) {
    final registrationId = value['registration_id'];
    final connection = value['connection'];
    final identity = value['connection_identity'];
    final profile = value['profile'];
    if (registrationId is! String ||
        registrationId.isEmpty ||
        connection is! String ||
        connection.isEmpty ||
        identity is! String ||
        identity.isEmpty ||
        profile is! String) {
      throw const FormatException('Invalid push registration');
    }
    return PushRegistrationRecord(
      registrationId: registrationId,
      workspace: WorkspaceScope(
        connectionId: connection,
        connectionIdentity: identity,
        profileName: profile,
      ),
    );
  }
}

abstract class PushRegistrationTransport {
  Future<List<HermesProfile>> profiles(
    SavedConnection connection,
    String connectionIdentity,
  );

  Future<PushRegistrationRecord> register({
    required SavedConnection connection,
    required WorkspaceScope workspace,
    required String installationId,
    required String fcmToken,
    required String applicationId,
    required PushPreferences preferences,
  });

  Future<void> unregister({
    required SavedConnection connection,
    required PushRegistrationRecord registration,
  });
}

class GatewayPushRegistrationTransport implements PushRegistrationTransport {
  @override
  Future<List<HermesProfile>> profiles(
    SavedConnection connection,
    String connectionIdentity,
  ) async {
    final gateway = ProfileGateway.forConnection(
      connection,
      WorkspaceScope(
        connectionId: connection.id,
        connectionIdentity: connectionIdentity,
        profileName: 'default',
      ),
    );
    try {
      return (await gateway.discover()).profiles;
    } finally {
      gateway.close();
    }
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
    final gateway = ProfileGateway.forConnection(connection, workspace);
    try {
      final result = await gateway.post('mobile/push/installations', {
        'schema_version': 1,
        'installation_id': installationId,
        'fcm_token': fcmToken,
        'platform': 'android',
        'application_id': applicationId,
        'workspace': {
          'connection': workspace.connectionId,
          'connection_identity': workspace.connectionIdentity,
          'profile': workspace.profileName,
        },
        'preferences': preferences.toJson(),
      });
      final registrationId = result['registration_id'];
      if (registrationId is! String || registrationId.isEmpty) {
        throw const FormatException(
          'Hermes did not confirm the push registration.',
        );
      }
      final returnedWorkspace = result['workspace'];
      if (returnedWorkspace is! Map ||
          returnedWorkspace['connection'] != workspace.connectionId ||
          returnedWorkspace['connection_identity'] !=
              workspace.connectionIdentity ||
          returnedWorkspace['profile'] != workspace.profileName) {
        throw const FormatException(
          'Hermes returned a different push registration owner.',
        );
      }
      return PushRegistrationRecord(
        registrationId: registrationId,
        workspace: workspace,
      );
    } finally {
      gateway.close();
    }
  }

  @override
  Future<void> unregister({
    required SavedConnection connection,
    required PushRegistrationRecord registration,
  }) async {
    final gateway = ProfileGateway.forConnection(
      connection,
      registration.workspace,
    );
    try {
      await gateway.deleteResource(
        'mobile/push/installations/${Uri.encodeComponent(registration.registrationId)}',
      );
    } finally {
      gateway.close();
    }
  }
}

class PushSyncResult {
  final int registered;
  final int removed;
  final int failed;

  const PushSyncResult({
    required this.registered,
    required this.removed,
    required this.failed,
  });
}

enum BackgroundPushState {
  unavailableBuild,
  disabled,
  noConnections,
  permissionRequired,
  syncing,
  configured,
  unavailableServer,
}

/// A small delivery ledger shared by live gateway and Firebase notifications.
/// It is delivery metadata, not conversation state. Reloading before every
/// claim makes separate Flutter isolates observe recent writes. Shared
/// preferences does not offer a cross-isolate transaction, so simultaneous
/// claims can still race; the backend also sends each event idempotently.
class PushDeliveryLedger {
  final SharedPreferences preferences;
  Future<void> _writes = Future.value();

  PushDeliveryLedger(this.preferences);

  Future<bool> claim(String eventId) {
    final result = Completer<bool>();
    _writes = _writes
        .then((_) async {
          await preferences.reload();
          final ids = preferences.getStringList(_deliveryIdsKey) ?? <String>[];
          if (ids.contains(eventId)) {
            result.complete(false);
            return;
          }
          final next = [...ids, eventId];
          if (next.length > _maxDeliveryIds) {
            next.removeRange(0, next.length - _maxDeliveryIds);
          }
          if (!await preferences.setStringList(_deliveryIdsKey, next)) {
            throw StateError('Could not save notification delivery state.');
          }
          result.complete(true);
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        });
    return result.future;
  }

  Future<void> release(String eventId) {
    final result = Completer<void>();
    _writes = _writes
        .then((_) async {
          await preferences.reload();
          final ids = preferences.getStringList(_deliveryIdsKey) ?? <String>[];
          ids.removeWhere((value) => value == eventId);
          if (!await preferences.setStringList(_deliveryIdsKey, ids)) {
            throw StateError('Could not save notification delivery state.');
          }
          result.complete();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        });
    return result.future;
  }
}

/// Reconciles this app installation with every saved, authenticated Hermes
/// connection. A failed host does not block registrations on other hosts.
class PushRegistrationCoordinator {
  final SharedPreferences preferences;
  final ProfileConnectionIdentity identities;
  final PushRegistrationTransport transport;
  final String Function() installationIdFactory;

  Future<void> _syncTail = Future<void>.value();

  PushRegistrationCoordinator({
    required this.preferences,
    ProfileConnectionIdentity? identities,
    PushRegistrationTransport? transport,
    String Function()? installationIdFactory,
  }) : identities = identities ?? ProfileConnectionIdentity(),
       transport = transport ?? GatewayPushRegistrationTransport(),
       installationIdFactory = installationIdFactory ?? const Uuid().v4;

  Future<PushSyncResult> sync({
    required List<SavedConnection> connections,
    required String? fcmToken,
    required String applicationId,
    required PushPreferences pushPreferences,
  }) {
    final scheduled = _syncTail.then(
      (_) => _sync(
        connections: connections,
        fcmToken: fcmToken,
        applicationId: applicationId,
        pushPreferences: pushPreferences,
      ),
    );
    _syncTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<PushSyncResult> unregisterConnection(SavedConnection connection) {
    final scheduled = _syncTail.then((_) async {
      final retained = <String, PushRegistrationRecord>{
        for (final registration in _readRegistrations())
          registration.key: registration,
      };
      var removed = 0;
      var failed = 0;
      for (final registration
          in retained.values
              .where((item) => item.workspace.connectionId == connection.id)
              .toList()) {
        try {
          await transport.unregister(
            connection: connection,
            registration: registration,
          );
          retained.remove(registration.key);
          removed++;
        } catch (_) {
          failed++;
        }
      }
      await _writeRegistrations(retained.values);
      return PushSyncResult(registered: 0, removed: removed, failed: failed);
    });
    _syncTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<PushSyncResult> _sync({
    required List<SavedConnection> connections,
    required String? fcmToken,
    required String applicationId,
    required PushPreferences pushPreferences,
  }) async {
    final existing = _readRegistrations();
    final retained = <String, PushRegistrationRecord>{
      for (final registration in existing) registration.key: registration,
    };
    var registered = 0;
    var removed = 0;
    var failed = 0;
    final canRegister =
        pushPreferences.enabled &&
        fcmToken != null &&
        fcmToken.trim().isNotEmpty &&
        applicationId.trim().isNotEmpty;
    final installationId = canRegister ? await _installationId() : null;

    for (final connection in connections) {
      final String identity;
      try {
        identity = await identities.resolve(connection);
      } catch (_) {
        failed++;
        continue;
      }
      final ownedExisting = existing
          .where(
            (item) =>
                item.workspace.connectionId == connection.id &&
                item.workspace.connectionIdentity == identity,
          )
          .toList();
      if (!canRegister) {
        for (final registration in ownedExisting) {
          try {
            await transport.unregister(
              connection: connection,
              registration: registration,
            );
            retained.remove(registration.key);
            removed++;
          } catch (_) {
            failed++;
          }
        }
        continue;
      }

      final List<HermesProfile> profiles;
      try {
        profiles = await transport.profiles(connection, identity);
      } catch (_) {
        failed++;
        continue;
      }
      final desiredKeys = <String>{};
      for (final profile in profiles) {
        final workspace = WorkspaceScope(
          connectionId: connection.id,
          connectionIdentity: identity,
          profileName: profile.name,
        );
        desiredKeys.add(
          PushRegistrationRecord(registrationId: '', workspace: workspace).key,
        );
        try {
          final registration = await transport.register(
            connection: connection,
            workspace: workspace,
            installationId: installationId!,
            fcmToken: fcmToken.trim(),
            applicationId: applicationId,
            preferences: pushPreferences,
          );
          retained[registration.key] = registration;
          registered++;
        } catch (_) {
          failed++;
        }
      }
      for (final registration in ownedExisting.where(
        (item) => !desiredKeys.contains(item.key),
      )) {
        try {
          await transport.unregister(
            connection: connection,
            registration: registration,
          );
          retained.remove(registration.key);
          removed++;
        } catch (_) {
          failed++;
        }
      }
    }

    final connectionIds = connections.map((item) => item.id).toSet();
    retained.removeWhere(
      (_, registration) =>
          !connectionIds.contains(registration.workspace.connectionId),
    );
    await _writeRegistrations(retained.values);
    return PushSyncResult(
      registered: registered,
      removed: removed,
      failed: failed,
    );
  }

  Future<String> _installationId() async {
    final existing = preferences.getString(_installationIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final created = installationIdFactory();
    if (!await preferences.setString(_installationIdKey, created)) {
      throw StateError('Could not save the push installation identity.');
    }
    return created;
  }

  List<PushRegistrationRecord> _readRegistrations() {
    try {
      final decoded = jsonDecode(
        preferences.getString(_registrationsKey) ?? '[]',
      );
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (value) => PushRegistrationRecord.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeRegistrations(
    Iterable<PushRegistrationRecord> registrations,
  ) async {
    final value = jsonEncode(
      registrations.map((registration) => registration.toJson()).toList(),
    );
    if (!await preferences.setString(_registrationsKey, value)) {
      throw StateError('Could not save push registrations.');
    }
  }
}

class BackgroundPushMessage {
  final String eventId;
  final String eventType;
  final String target;
  final String? title;
  final String? body;

  const BackgroundPushMessage({
    required this.eventId,
    required this.eventType,
    required this.target,
    this.title,
    this.body,
  });

  ProfileSessionKey get targetKey => ProfileSessionKey.fromJson(
    Map<String, dynamic>.from(jsonDecode(target) as Map),
  );

  factory BackgroundPushMessage.fromRemoteMessage(RemoteMessage message) =>
      BackgroundPushMessage.fromData(
        message.data,
        title: message.notification?.title ?? message.data['title'],
        body: message.notification?.body ?? message.data['body'],
      );

  factory BackgroundPushMessage.fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    if (data['schema_version'] != '1') {
      throw const FormatException('Unsupported push schema');
    }
    final eventId = data['event_id'];
    final eventType = data['event_type'];
    final target = data['target'];
    if (eventId is! String ||
        eventId.isEmpty ||
        !{'completion', 'input_required', 'error'}.contains(eventType) ||
        target is! String ||
        target.isEmpty) {
      throw const FormatException('Invalid Hermes push');
    }
    final parsed = BackgroundPushMessage(
      eventId: eventId,
      eventType: eventType as String,
      target: target,
      title:
          title ?? (data['title'] is String ? data['title'] as String : null),
      body: body ?? (data['body'] is String ? data['body'] as String : null),
    );
    parsed.targetKey;
    return parsed;
  }

  TurnNotification notification({required bool includeServerText}) =>
      TurnNotification(
        id: TurnNotificationService.notificationIdFor('push-event:$eventId'),
        title:
            (includeServerText ? title : null) ??
            (eventType == 'input_required'
                ? 'Hermes needs your input'
                : eventType == 'error'
                ? 'Hermes needs attention'
                : 'Hermes finished'),
        body:
            (includeServerText ? body : null) ??
            (eventType == 'input_required'
                ? 'Open to respond'
                : 'Open to view the result'),
        payload: target,
        channel: TurnNotificationService.turnChannel,
      );
}

class PushMessageAuthorizer {
  final SharedPreferences preferences;
  final ConnectionManager connectionManager;
  final ProfileConnectionIdentity identities;

  PushMessageAuthorizer({
    required this.preferences,
    required this.connectionManager,
    ProfileConnectionIdentity? identities,
  }) : identities = identities ?? ProfileConnectionIdentity();

  Future<TurnNotification?> notificationFor(
    BackgroundPushMessage message,
  ) async {
    await preferences.reload();
    final configured = PushPreferences.read(preferences);
    final enabled = message.eventType == 'completion'
        ? configured.completion
        : configured.attention;
    if (!enabled) return null;
    final target = message.targetKey;
    final connections = await connectionManager.loadConnectionsWithSecrets();
    final connection = connections
        .where((item) => item.id == target.workspace.connectionId)
        .firstOrNull;
    if (connection == null) return null;
    final currentIdentity = await identities.resolve(connection);
    if (currentIdentity != target.workspace.connectionIdentity) return null;
    return message.notification(includeServerText: configured.includeChatTitle);
  }
}

/// Owns Firebase delivery. Hermes sends high-priority data messages so foreground
/// and background isolates use the same delivery claim and notification sink.
class BackgroundPushService {
  final SharedPreferences preferences;
  final ConnectionManager connectionManager;
  final PushRegistrationCoordinator registrations;
  final TurnNotificationSink notifications;
  final PushDeliveryLedger deliveries;
  final PushMessageAuthorizer authorizer;
  final FirebaseMessaging messaging;
  final String applicationId;
  final Future<void> Function(String target) onOpen;
  final ValueNotifier<BackgroundPushState> state;

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  Future<void> _syncTail = Future<void>.value();

  BackgroundPushService({
    required this.preferences,
    required this.connectionManager,
    required this.registrations,
    required this.notifications,
    required this.deliveries,
    required this.authorizer,
    required this.messaging,
    required this.applicationId,
    required this.onOpen,
    required this.state,
  });

  static Future<BackgroundPushService?> create({
    required SharedPreferences preferences,
    required ConnectionManager connectionManager,
    required TurnNotificationSink notifications,
    required PushDeliveryLedger deliveries,
    required Future<void> Function(String target) onOpen,
    required ValueNotifier<BackgroundPushState> state,
  }) async {
    final options = wingFirebaseOptions();
    if (options == null) return null;
    await Firebase.initializeApp(options: options);
    FirebaseMessaging.onBackgroundMessage(wingFirebaseBackgroundHandler);
    final packageInfo = await PackageInfo.fromPlatform();
    final service = BackgroundPushService(
      preferences: preferences,
      connectionManager: connectionManager,
      registrations: PushRegistrationCoordinator(preferences: preferences),
      notifications: notifications,
      deliveries: deliveries,
      authorizer: PushMessageAuthorizer(
        preferences: preferences,
        connectionManager: connectionManager,
      ),
      messaging: FirebaseMessaging.instance,
      applicationId: packageInfo.packageName,
      onOpen: onOpen,
      state: state,
    );
    await service.initialize();
    return service;
  }

  Future<void> initialize() async {
    await notifications.initialize();
    _tokenSubscription = messaging.onTokenRefresh.listen((_) {
      unawaited(
        sync().catchError((Object _) {
          state.value = BackgroundPushState.unavailableServer;
          return const PushSyncResult(registered: 0, removed: 0, failed: 1);
        }),
      );
    });
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForeground,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_open);
    final initial = await messaging.getInitialMessage();
    if (initial != null) await _open(initial);
    try {
      await sync();
    } catch (_) {
      state.value = BackgroundPushState.unavailableServer;
    }
  }

  Future<PushSyncResult> sync() {
    final scheduled = _syncTail.then((_) => _sync());
    _syncTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<PushSyncResult> _sync() async {
    state.value = BackgroundPushState.syncing;
    final connections = await connectionManager.loadConnectionsWithSecrets();
    final pushPreferences = PushPreferences.read(preferences);
    final settings = await messaging.getNotificationSettings();
    final allowed =
        preferences.getBool(backgroundPushPermissionRequestedKey) == true &&
        {
          AuthorizationStatus.authorized,
          AuthorizationStatus.provisional,
        }.contains(settings.authorizationStatus);
    final shouldRegister =
        allowed && pushPreferences.enabled && connections.isNotEmpty;
    await messaging.setAutoInitEnabled(shouldRegister);
    final token = shouldRegister ? await messaging.getToken() : null;
    final result = await registrations.sync(
      connections: connections,
      fcmToken: token,
      applicationId: applicationId,
      pushPreferences: pushPreferences,
    );
    state.value = !pushPreferences.enabled
        ? BackgroundPushState.disabled
        : connections.isEmpty
        ? BackgroundPushState.noConnections
        : !allowed
        ? BackgroundPushState.permissionRequired
        : result.failed > 0 || result.registered == 0
        ? BackgroundPushState.unavailableServer
        : BackgroundPushState.configured;
    return result;
  }

  Future<void> _showForeground(RemoteMessage message) async {
    try {
      final parsed = BackgroundPushMessage.fromRemoteMessage(message);
      await show(parsed);
    } catch (_) {
      // A malformed remote payload must not affect the running app.
    }
  }

  Future<bool> show(BackgroundPushMessage message) async {
    final notification = await authorizer.notificationFor(message);
    if (notification == null) return false;
    if (await notifications.notificationsEnabled() == false) return false;
    if (!await deliveries.claim(message.eventId)) return false;
    try {
      await notifications.show(notification);
      return true;
    } catch (_) {
      await deliveries.release(message.eventId);
      rethrow;
    }
  }

  Future<void> _open(RemoteMessage message) async {
    try {
      await onOpen(BackgroundPushMessage.fromRemoteMessage(message).target);
    } catch (_) {
      // The normal notification route reports unavailable or stale targets.
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _syncTail;
  }

  Future<PushSyncResult> unregisterConnection(SavedConnection connection) =>
      registrations.unregisterConnection(connection);
}

@pragma('vm:entry-point')
Future<void> wingFirebaseBackgroundHandler(RemoteMessage message) async {
  BackgroundPushMessage? parsed;
  PushDeliveryLedger? deliveries;
  try {
    final options = wingFirebaseOptions();
    if (options == null) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    parsed = BackgroundPushMessage.fromRemoteMessage(message);
    final preferences = await SharedPreferences.getInstance();
    final manager = ConnectionManager(preferences);
    final notification = await PushMessageAuthorizer(
      preferences: preferences,
      connectionManager: manager,
    ).notificationFor(parsed);
    if (notification == null) return;
    final sink = PluginTurnNotificationSink();
    if (await sink.notificationsEnabled() == false) return;
    deliveries = PushDeliveryLedger(preferences);
    if (!await deliveries.claim(parsed.eventId)) return;
    await sink.show(notification);
  } catch (_) {
    if (parsed != null && deliveries != null) {
      try {
        await deliveries.release(parsed.eventId);
      } catch (_) {}
    }
  }
}
