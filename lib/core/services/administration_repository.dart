import 'dart:async';

import '../models/hermes_profile.dart';
import 'connection_manager.dart';
import 'profile_gateway.dart';
import 'profiles_repository.dart';
import 'server_connection_status.dart';

typedef AdministrationRequest =
    Future<Map<String, dynamic>> Function(
      String method,
      String endpoint,
      Map<String, String> query,
      Map<String, dynamic>? body,
    );

/// One connection, independent of the currently selected workspace.
/// Profile views capture an explicit scope, including shared-root account views.
class AdministrationRepository {
  final String connectionId;
  final String connectionIdentity;
  final String connectionLabel;
  final AdministrationRequest request;
  final ProfileGateway Function(String name) gateway;
  final void Function() _close;
  int _leases = 0;
  bool _closing = false;
  bool _closed = false;

  AdministrationRepository({
    required this.connectionId,
    required this.connectionIdentity,
    required this.connectionLabel,
    required this.request,
    required this.gateway,
    void Function()? close,
  }) : _close = close ?? _noop;
  static void _noop() {}

  factory AdministrationRepository.forConnection(
    SavedConnection connection,
    String identity, {
    required ServerConnectionStatus connectionStatus,
  }) {
    final dashboard = DashboardClient(
      host: connection.host,
      port: connection.dashboardPort,
      useHttps: connection.useHttps,
      pathPrefix: connection.dashboardPrefix ?? '',
      proxied: connection.dashboardProxied,
      username: connection.dashboardUsername,
      password: connection.dashboardPassword,
      dashboardOAuth: connection.dashboardOAuth,
      requiresOAuth: connection.isCloud,
      gatewayHeaders: connection.gatewayHeaders,
    );
    final gateways = <String, ProfileGateway>{};
    return AdministrationRepository(
      connectionId: connection.id,
      connectionIdentity: identity,
      connectionLabel: connection.label,
      request: (method, endpoint, query, body) async {
        if (endpoint.startsWith('cron/')) {
          return connectionStatus.observeAccess(
            () => dashboard.cronRequest(method, endpoint, query, body),
          );
        }
        final path = Uri.parse(
          endpoint,
        ).replace(queryParameters: query.isEmpty ? null : query).toString();
        final Future<Map<String, dynamic>> response = switch (method) {
          'GET' => dashboard.apiGet(endpoint, queryParameters: query),
          'POST' => dashboard.apiPost(path, body: body),
          'PUT' => dashboard.apiPut(path, body: body),
          'PATCH' => dashboard.apiPatch(path, body: body ?? {}),
          'DELETE' => dashboard.apiDeleteResult(path, body: body),
          _ => throw ArgumentError('Unsupported administration request'),
        };
        return connectionStatus.observeAccess(
          () => response.timeout(const Duration(seconds: 45)),
        );
      },
      gateway: (name) => gateways.putIfAbsent(
        name,
        () =>
            ProfileGateway.forConnection(
                connection,
                WorkspaceScope(
                  connectionId: connection.id,
                  connectionIdentity: identity,
                  profileName: name,
                ),
              )
              ..connectionStatus = connectionStatus
              ..reportsLiveChat = false,
      ),
      close: () {
        for (final gateway in gateways.values) {
          gateway.close();
        }
        dashboard.close();
      },
    );
  }

  void retain() {
    if (_closed) throw StateError('Administration connection is closed');
    _leases++;
  }

  void release() {
    _leases--;
    if (_closing && _leases == 0) close();
  }

  void close() {
    _closing = true;
    if (_leases == 0 && !_closed) {
      _closed = true;
      _close();
    }
  }

  Future<Map<String, dynamic>> read(
    String endpoint, [
    Map<String, String> query = const {},
  ]) => request('GET', endpoint, query, null);

  Future<Map<String, dynamic>> write(
    String method,
    String endpoint, [
    Map<String, dynamic> body = const {},
  ]) async {
    final result = await request(method, endpoint, const {}, body);
    if (result['ok'] == false) {
      throw AdministrationFailure.rejected(result);
    }
    return result;
  }

  Future<ProfileDiscovery> discover() =>
      ProfilesRepository((endpoint) => read(endpoint)).discover();

  Future<Map<String, dynamic>> runtimeIdentity() async {
    try {
      final profiles = await discover();
      final current = profiles.named(profiles.currentName);
      if (current != null) {
        return {
          'name': current.name,
          'label': 'Runtime profile: ${current.label}',
          'unavailable': false,
        };
      }
    } catch (_) {
      // Runtime operations remain reachable when identity metadata is unavailable.
    }
    return {'label': 'Profile scope unavailable', 'unavailable': true};
  }

  ProfileAdministration profile(String name) {
    if (!HermesProfile.isCanonicalName(name) || name == 'current') {
      throw ArgumentError('An explicit canonical profile is required');
    }
    return ProfileAdministration._(this, name);
  }

  /// The stock profile resolver maps canonical default to the shared root.
  /// Verify this identity through discovery before offering shared writes.
  Future<ProfileAdministration> sharedProviders() async {
    final profiles = await discover();
    final root = profiles.named('default');
    if (root == null || !root.isDefault) {
      throw const AdministrationFailure(
        'The shared account owner is unavailable.',
      );
    }
    return profile(root.name);
  }
}

class ProfileAdministration {
  final AdministrationRepository server;
  final String name;
  ProfileAdministration._(this.server, this.name);
  String get label => '${server.connectionLabel} / $name';
  WorkspaceScope get scope => WorkspaceScope(
    connectionId: server.connectionId,
    connectionIdentity: server.connectionIdentity,
    profileName: name,
  );
  ProfileGateway get gateway => server.gateway(name);

  Future<Map<String, dynamic>> read(
    String endpoint, [
    Map<String, String> query = const {},
  ]) => server.request('GET', endpoint, {...query, 'profile': name}, null);

  Future<void> requireProfile() async {
    if ((await server.discover()).named(name) == null) {
      throw const AdministrationFailure(
        'This profile is no longer available. Your edits are kept.',
      );
    }
  }

  Future<Map<String, dynamic>> write(
    String method,
    String endpoint, [
    Map<String, dynamic> body = const {},
  ]) async {
    await requireProfile();
    final result = await server.request(
      method,
      endpoint,
      {'profile': name},
      {...body, 'profile': name},
    );
    if (result['ok'] == false && result['confirm_required'] != true) {
      throw AdministrationFailure.rejected(result);
    }
    return result;
  }

  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic> params = const {},
    bool mutation = false,
  ]) async {
    if (mutation) await requireProfile();
    await gateway.connect();
    final result = await gateway.call(method, params);
    if (result['ok'] == false) {
      throw AdministrationFailure.rejected(result);
    }
    return result;
  }

  Future<Map<String, dynamic>> config() => read('config');
  Future<void> saveSettings(Map<String, dynamic> values) async {
    final patch = <String, dynamic>{};
    for (final entry in values.entries) {
      setSetting(patch, entry.key, entry.value);
    }
    await write('PUT', 'config', {'config': patch});
    final saved = await config();
    for (final entry in values.entries) {
      if (!sameSetting(setting(saved, entry.key), entry.value)) {
        throw const AdministrationFailure(
          'Save not confirmed. Your edits are kept. Refresh before retrying.',
        );
      }
    }
  }
}

class AdministrationFailure implements Exception {
  final String message;
  // Only operation-specific presenters should display this, after redaction.
  final String? serverError;
  const AdministrationFailure(this.message, {this.serverError});
  factory AdministrationFailure.rejected(Map<String, dynamic> result) =>
      AdministrationFailure(
        'The server rejected this change.',
        serverError: result['error'] is String
            ? result['error'] as String
            : null,
      );
  @override
  String toString() => message;
}

String administrationError(Object error, {bool writing = false}) {
  if (error is AdministrationFailure) return error.message;
  if (error is DashboardHttpException &&
      {404, 405, 501}.contains(error.statusCode)) {
    return 'This information is unavailable on this server. Refresh or check the connection.';
  }
  return writing
      ? 'The result could not be confirmed. Your edits are kept. Refresh before retrying.'
      : 'Could not load this information. Check the connection and retry.';
}

List<Map<String, dynamic>> administrationRows(Object? value) {
  if (value is! List || value.any((row) => row is! Map)) {
    throw const FormatException('Invalid administration list');
  }
  return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}

Object? setting(Map<String, dynamic> config, String key) {
  Object? value = config;
  for (final part in key.split('.')) {
    if (value is! Map) return null;
    value = value[part];
  }
  return value;
}

void setSetting(Map<String, dynamic> config, String key, Object? value) {
  final parts = key.split('.');
  var node = config;
  for (final part in parts.take(parts.length - 1)) {
    node =
        node.putIfAbsent(part, () => <String, dynamic>{})
            as Map<String, dynamic>;
  }
  node[parts.last] = value;
}

bool sameSetting(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => sameSetting(a[i], b[i])).every((v) => v);
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && sameSetting(a[k], b[k]));
  }
  return a == b;
}

/// Never mistake another client's same-name action for this operation.
class AdministrationAction {
  final String name;
  final int pid;
  const AdministrationAction(this.name, this.pid);
  factory AdministrationAction.fromJson(Map<String, dynamic> result) {
    final name = result['name'];
    final pid = result['pid'];
    if (name is! String || name.isEmpty || pid is! int) {
      throw const AdministrationFailure(
        'Operation started, but tracking is unavailable. Refresh its result.',
      );
    }
    return AdministrationAction(name, pid);
  }
  Future<Map<String, dynamic>> status(AdministrationRepository server) async {
    final result = await server.read(
      'actions/${Uri.encodeComponent(name)}/status',
      {'lines': '100'},
    );
    if (result['pid'] != pid) {
      throw const AdministrationFailure(
        'This operation’s result is no longer available. Refresh the affected resource.',
      );
    }
    return result;
  }
}
