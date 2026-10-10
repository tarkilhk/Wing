import 'profile_model_catalog.dart';
import 'gateway_endpoint.dart';
import 'remote_files_client.dart';
import 'models_dev_pricing.dart';
import 'skill_reader_session.dart';
import '../models/skill_reader.dart';
import 'connection_access.dart';
// Named transport seams keep request functions injectable.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import '../models/session_visibility.dart';
import '../models/deleted_draft_cleanup.dart';
import '../models/hermes_profile.dart';
import '../models/answer_versions.dart';
import '../models/gateway_activity.dart';
import 'connection_manager.dart';
import 'profiles_repository.dart';
import 'ws_client.dart';
import 'server_connection_status.dart';
import 'workspace_connection_failure.dart';

typedef ScopedGet =
    Future<Map<String, dynamic>> Function(
      String endpoint,
      Map<String, String> query,
    );
typedef ScopedRpc =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

typedef ScopedPost =
    Future<Map<String, dynamic>> Function(
      String endpoint,
      Map<String, dynamic> body,
    );

typedef ScopedOwnedPost =
    Future<Map<String, dynamic>> Function(
      String endpoint,
      Map<String, dynamic> body,
      bool Function() canDispatch,
      void Function() onDispatched,
    );

/// The REST page may include extra pinned rows outside its offset window.
class ProfileSessionPage {
  final List<Map<String, dynamic>> rows;
  final int offset;
  final int limit;
  final int total;
  const ProfileSessionPage({
    required this.rows,
    required this.offset,
    required this.limit,
    required this.total,
  });
  int? get nextOffset => offset + limit < total ? offset + limit : null;
}

typedef ProfileCanonicalBotChat = ({String tipId, Map<String, dynamic> row});

class ProfileHistoryPage {
  final String sessionId;
  final List<Map<String, dynamic>> rows;
  final int offset;
  final int limit;
  final bool isComplete;
  const ProfileHistoryPage(
    this.sessionId,
    this.rows,
    this.offset,
    this.limit, {
    this.isComplete = false,
  });
  int? get nextOffset =>
      !isComplete && rows.length == limit ? offset + rows.length : null;
}

class ProjectFolderSuggestion {
  final String path;
  final String label;

  const ProjectFolderSuggestion({required this.path, required this.label});
}

DashboardClient _dashboardFor(ConnectionAccess access) {
  final connection = access.connection;
  return DashboardClient(
    host: connection.host,
    port: connection.dashboardPort,
    useHttps: connection.useHttps,
    pathPrefix: connection.dashboardPrefix ?? '',
    proxied: connection.dashboardProxied,
    username: connection.dashboardUsername,
    password: connection.dashboardPassword,
    dashboardOAuth: access.dashboardOAuth,
    requiresOAuth: connection.isCloud,
    gatewayHeaders: connection.gatewayHeaders,
  );
}

/// Authentication and HTTP pooling belong to one saved connection, not to each
/// profile or short-lived project reader. Gateways still own separate sockets.
class ProfileGatewayConnection {
  ProfileGatewayConnection(this.access);
  final ConnectionAccess access;
  SavedConnection get connection => access.connection;
  late final DashboardClient _dashboard = _dashboardFor(access);
  // An explicitly distinct file origin owns its own sign-in. Never share a
  // cookie between that origin and the workspace's Dashboard origin.
  DashboardClient? _fileDashboard;
  bool _closed = false;

  DashboardClient createFileReadClient() {
    if (_closed) throw StateError('Connection is closed');
    final dashboard = _fileDashboard ??=
        normalizedGatewayBaseUrl(connection) == _dashboard.baseUrl
        ? _dashboard
        : RemoteFilesClient.fromConnection(access).dashboard;
    return dashboard.forkReads();
  }

  ProfileGateway create(WorkspaceScope scope) {
    if (_closed) throw StateError('Connection is closed');
    return ProfileGateway._forDashboard(
      connection,
      scope,
      _dashboard,
      ownsDashboard: false,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final fileDashboard = _fileDashboard;
    if (fileDashboard != null && !identical(fileDashboard, _dashboard)) {
      fileDashboard.close();
    }
    _dashboard.close();
  }
}

/// The stock modern Hermes contract. All profile-owned traffic passes through
/// this immutable scope. There is no unscoped or experimental-recovery fallback.
class ProfileGateway {
  late final _skillReader = SkillReaderRepository(_get);
  SkillReaderSession skillReader(SkillReaderTarget document) =>
      SkillReaderSession(
        repository: _skillReader,
        document: document,
        profile: scope.profileName,
      );
  final WorkspaceScope scope;
  final ApiPricingRead? _apiPricing;
  late final modelCatalog = ProfileModelCatalog(
    scope: scope,
    apiPricing: _apiPricing,
    read: ({required refresh, required explicitOnly}) => read('model/options', {
      if (refresh) 'refresh': '1',
      if (explicitOnly) 'explicit_only': '1',
    }),
  );
  final ScopedGet _getRequest;
  final ScopedRpc _rpcRequest;
  Future<Map<String, dynamic>> _rpc(
    String method,
    Map<String, dynamic> params,
  ) async {
    try {
      return await _rpcRequest(method, params);
    } catch (failure) {
      if (isTemporaryWorkspaceFailure(failure)) {
        disconnect();
        _liveChanged(false);
        onConnectionChanged?.call(false);
      }
      rethrow;
    }
  }

  final ScopedOwnedPost? _ownedPatch;
  final ScopedOwnedPost? _ownedDelete;
  final ScopedPost? _post;
  final ScopedOwnedPost? _ownedPost;
  final ScopedOwnedPost? _ownedPut;
  final Future<void> Function() _connect;
  final void Function() _close;
  final void Function() disconnect;
  final Future<ProfileDiscovery> Function() _discover;
  ServerConnectionStatus? connectionStatus;
  // Administration RPC sockets do not carry chat updates and are not recovered
  // by the workspace. Their lifetime must not determine live chat availability.
  bool reportsLiveChat = true;
  void _liveChanged(bool connected) {
    if (reportsLiveChat) {
      connectionStatus?.liveChanged(scope.profileName, connected);
    }
  }

  Future<Map<String, dynamic>> _get(
    String endpoint,
    Map<String, String> query,
  ) => connectionStatus == null
      ? _getRequest(endpoint, query)
      : connectionStatus!.observeAccess(() => _getRequest(endpoint, query));
  Future<ProfileDiscovery> discover() => connectionStatus == null
      ? _discover()
      : connectionStatus!.observeAccess(_discover);
  StreamCallback? onEvent;
  ConnectionCallback? onConnectionChanged;

  ProfileGateway({
    ApiPricingRead? apiPricing,
    required this.scope,
    required ScopedGet get,
    required ScopedRpc rpc,
    ScopedOwnedPost? ownedPatch,
    ScopedOwnedPost? ownedDelete,
    ScopedPost? post,
    ScopedOwnedPost? ownedPost,
    ScopedOwnedPost? ownedPut,
    required Future<ProfileDiscovery> Function() discover,
    Future<void> Function()? connect,
    void Function()? close,
    void Function()? disconnect,
  }) : _apiPricing = apiPricing,
       _getRequest = get,
       _discover = discover,
       _rpcRequest = rpc,
       _ownedPatch = ownedPatch,
       _ownedDelete = ownedDelete,
       _post = post,
       _ownedPost = ownedPost,
       _ownedPut = ownedPut,
       _connect = connect ?? _nothing,
       _close = close ?? _noop,
       disconnect = disconnect ?? _noop;

  static Future<void> _nothing() async {}
  static void _noop() {}

  factory ProfileGateway.forConnection(
    ConnectionAccess access,
    WorkspaceScope scope,
  ) {
    final connection = access.connection;
    if (scope.connectionId != connection.id) {
      throw ArgumentError('Connection does not own this workspace');
    }
    return ProfileGateway._forDashboard(
      connection,
      scope,
      _dashboardFor(access),
      ownsDashboard: true,
    );
  }

  factory ProfileGateway._forDashboard(
    SavedConnection connection,
    WorkspaceScope scope,
    DashboardClient dashboard, {
    required bool ownsDashboard,
  }) {
    if (scope.connectionId != connection.id) {
      throw ArgumentError('Connection does not own this workspace');
    }
    WsClient? socket;
    WsClient? openingSocket;
    var closed = false;
    var connected = false;
    Future<void>? connecting;
    late final ProfileGateway gateway;
    Future<void> open() async {
      final credentials =
          await (gateway.connectionStatus?.observeAccess(
                () => dashboard.gatewayCredentials().timeout(
                  const Duration(seconds: 20),
                ),
              ) ??
              dashboard.gatewayCredentials().timeout(
                const Duration(seconds: 20),
              ));
      if (closed) throw StateError('Gateway is closed');
      final candidate = WsClient(
        connection.desktopGatewayUrl ?? dashboard.baseUrl,
        token: credentials.token,
        ticket: credentials.ticket,
        gatewayHeaders: connection.gatewayHeaders,
      );
      openingSocket = candidate;
      candidate.onStreamEvent = (event) => gateway.onEvent?.call(event);
      candidate.onConnectionChanged = (value) {
        if (!identical(socket, candidate) &&
            !identical(openingSocket, candidate)) {
          return;
        }
        connected = value;
        if (!value && !closed && identical(socket, candidate)) {
          gateway._liveChanged(false);
        }
        gateway.onConnectionChanged?.call(value);
      };
      try {
        await candidate.connect();
        await candidate.waitForGatewayReady();
        if (closed) throw StateError('Gateway is closed');
        socket = candidate;
      } catch (_) {
        candidate.close();
        rethrow;
      } finally {
        if (identical(openingSocket, candidate)) openingSocket = null;
      }
    }

    gateway = ProfileGateway(
      apiPricing: ModelsDevPricing.shared.load,
      scope: scope,
      get: (endpoint, query) => dashboard
          .apiGet(endpoint, queryParameters: query)
          .timeout(const Duration(seconds: 20)),
      ownedPatch: (endpoint, body, canDispatch, onDispatched) async {
        var dispatchAllowed = true;
        try {
          return await dashboard
              .apiWriteOwned(
                'PATCH',
                endpoint,
                body: body,
                canDispatch: () => !closed && dispatchAllowed && canDispatch(),
                onDispatched: onDispatched,
              )
              .timeout(const Duration(seconds: 20));
        } finally {
          dispatchAllowed = false;
        }
      },
      ownedDelete: (endpoint, body, canDispatch, onDispatched) async {
        var dispatchAllowed = true;
        try {
          return await dashboard
              .apiWriteOwned(
                'DELETE',
                Uri.parse(endpoint)
                    .replace(
                      queryParameters: body.map(
                        (key, value) => MapEntry(key, value.toString()),
                      ),
                    )
                    .toString(),
                body: const {},
                canDispatch: () => !closed && dispatchAllowed && canDispatch(),
                onDispatched: onDispatched,
              )
              .timeout(const Duration(seconds: 20));
        } finally {
          dispatchAllowed = false;
        }
      },
      post: (endpoint, body) => dashboard
          .apiPost(endpoint, body: body)
          .timeout(const Duration(seconds: 30)),
      ownedPost: (endpoint, body, canDispatch, onDispatched) async {
        var dispatchAllowed = true;
        bool active() => !closed && dispatchAllowed && canDispatch();
        try {
          return await dashboard
              .apiWriteOwned(
                'POST',
                endpoint,
                body: body,
                canDispatch: active,
                onDispatched: onDispatched,
              )
              .timeout(const Duration(seconds: 30));
        } finally {
          dispatchAllowed = false;
        }
      },
      ownedPut: (endpoint, body, canDispatch, onDispatched) async {
        var dispatchAllowed = true;
        bool active() => !closed && dispatchAllowed && canDispatch();
        try {
          return await dashboard
              .apiWriteOwned(
                'PUT',
                endpoint,
                body: body,
                canDispatch: active,
                onDispatched: onDispatched,
              )
              .timeout(const Duration(seconds: 30));
        } finally {
          dispatchAllowed = false;
        }
      },
      rpc: (method, params) async {
        final current = socket;
        if (current == null) {
          throw JsonRpcError(
            method,
            'Connection unavailable',
            reason: 'connection_closed',
          );
        }
        final envelope = await current.send(
          method,
          params,
          timeout: method == 'mcp.servers.oauth.start'
              ? const Duration(seconds: 45)
              : const {
                  'command.dispatch',
                  'slash.exec',
                  'session.compress',
                }.contains(method)
              ? const Duration(minutes: 11)
              : const Duration(seconds: 30),
        );
        final error = envelope['error'];
        if (error is Map) {
          throw JsonRpcError.fromGateway(
            method,
            error,
            fallbackMessage: 'Gateway request failed',
          );
        }
        final result = envelope['result'];
        if (result is! Map) throw const FormatException('Missing RPC result');
        return Map<String, dynamic>.from(result);
      },
      discover: () => ProfilesRepository(
        dashboard.apiGet,
      ).discover().timeout(const Duration(seconds: 20)),
      connect: () =>
          connecting ??
          (connected && socket != null
              ? Future<void>.value()
              : connecting = (() async {
                  socket?.close();
                  socket = null;
                  try {
                    await open();
                  } finally {
                    connecting = null;
                  }
                })()),
      disconnect: () {
        final previous = socket;
        socket = null;
        connected = false;
        previous?.close();
      },
      close: () {
        closed = true;
        openingSocket?.close();
        socket?.close();
        if (ownsDashboard) dashboard.close();
      },
    );
    return gateway;
  }

  Future<void> connect() async {
    try {
      await _connect();
      _liveChanged(true);
    } catch (_) {
      _liveChanged(false);
      rethrow;
    }
  }

  void close() {
    modelCatalog.close();
    _close();
    if (reportsLiveChat) connectionStatus?.forgetLive(scope.profileName);
  }

  /// Revalidate immediately before writes. Stock servers can still have a
  /// deletion-after-validation race; client validation cannot fix that race.
  Future<void> requireProfile() async {
    if ((await discover()).named(scope.profileName) == null) {
      throw StateError('Profile ${scope.profileName} is no longer available');
    }
  }

  Future<Map<String, dynamic>> read(
    String endpoint, [
    Map<String, String> query = const {},
  ]) => _get(endpoint, {...query, 'profile': scope.profileName});

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) => _rpc(method, {...params, 'profile': scope.profileName});

  /// Reload is process-wide. Its stock schema forbids a profile parameter;
  /// this gateway provides the connection, not the operation's scope.
  Future<Map<String, dynamic>> reloadMcp({
    required bool confirm,
    required bool Function() canDispatch,
    required void Function() onDispatched,
  }) async {
    await connect();
    if (!canDispatch()) {
      throw JsonRpcError(
        'reload.mcp',
        'Operation retired',
        reason: 'operation_retired',
      );
    }
    onDispatched();
    return _rpc('reload.mcp', {'confirm': confirm});
  }

  /// MCP uses stock RPC for raw OAuth/header/TLS creation and loopback sign-in.
  /// Production RPC sends synchronously: no await follows the authority check.
  Future<Map<String, dynamic>> mcpCommand(
    String action,
    Map<String, dynamic> params, {
    required bool Function() canDispatch,
    required void Function() onDispatched,
  }) async {
    if (!{
      'add',
      'oauth.start',
      'oauth.callback',
      'oauth.cancel',
      'oauth.poll',
    }.contains(action)) {
      throw ArgumentError('Unknown MCP command');
    }
    await connect();
    if (!canDispatch()) {
      throw JsonRpcError(
        'mcp.servers.$action',
        'Operation retired',
        reason: 'operation_retired',
      );
    }
    onDispatched();
    return call('mcp.servers.$action', params);
  }

  /// Exact stock plugin toggle; no await separates route authority from RPC send.
  Future<Map<String, dynamic>> togglePlugin(
    String key,
    bool enabled, {
    required bool Function() canDispatch,
    required void Function() onDispatched,
  }) async {
    if (key.isEmpty) {
      throw ArgumentError('Plugin key is empty');
    }
    await connect();
    if (!canDispatch()) {
      throw JsonRpcError(
        'plugins.manage',
        'Operation retired',
        reason: 'operation_retired',
      );
    }
    onDispatched();
    return call('plugins.manage', {
      'action': 'toggle',
      'key': key,
      'enable': enabled,
    });
  }

  /// Stock completion derives profile and workspace from the owning session.
  /// An additional profile is unnecessary for an existing owned runtime.
  Future<Map<String, dynamic>> completeSlash({
    required String sessionId,
    required String text,
  }) => _rpc('complete.slash', {'session_id': sessionId, 'text': text});

  Future<Map<String, dynamic>> post(
    String endpoint, [
    Map<String, dynamic> body = const {},
  ]) {
    final send = _post;
    if (send == null) throw StateError('Dashboard writes are unavailable');
    final uri = Uri.parse(endpoint);
    return send(
      uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'profile': scope.profileName,
            },
          )
          .toString(),
      body,
    );
  }

  /// A distinct capability for route-owned commands. Unsupported adapters fail
  /// closed; generic writes never substitute for physical dispatch fencing.
  Future<Map<String, dynamic>> postOwned(
    String endpoint,
    Map<String, dynamic> body, {
    required bool Function() canDispatch,
    required void Function() onDispatched,
  }) {
    final send = _ownedPost;
    if (send == null) {
      throw StateError('Owned dashboard writes are unavailable');
    }
    final uri = Uri.parse(endpoint);
    return send(
      uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'profile': scope.profileName,
            },
          )
          .toString(),
      body,
      canDispatch,
      onDispatched,
    );
  }

  Future<Map<String, dynamic>> putOwned(
    String endpoint,
    Map<String, dynamic> body, {
    required bool Function() canDispatch,
    required void Function() onDispatched,
  }) {
    final send = _ownedPut;
    if (send == null) {
      throw StateError('Owned dashboard writes are unavailable');
    }
    final uri = Uri.parse(endpoint);
    return send(
      uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'profile': scope.profileName,
            },
          )
          .toString(),
      body,
      canDispatch,
      onDispatched,
    );
  }

  static const sessionPageSize = 50;
  static const projectSessionScanLimit = 5000;

  /// The stock exact-title registry lookup includes hidden canonical chats.
  /// Metadata supplies visibility and accounting absent from its summary.
  Future<ProfileCanonicalBotChat?> canonicalBotChat() async {
    final result = await call('session.list', {
      'title': 'Bot Chat',
      'include_hidden': true,
    });
    final summaries = records(result['sessions']);
    if (summaries.isEmpty) return null;
    if (summaries.length != 1) {
      throw const FormatException('Ambiguous canonical Bot Chat');
    }
    final summary = summaries.single;
    final id = summary['id'];
    final tipId = summary['resolved_id'];
    if (id is! String ||
        id.isEmpty ||
        tipId is! String ||
        tipId.isEmpty ||
        summary['title'] != 'Bot Chat') {
      throw const FormatException('Invalid canonical Bot Chat');
    }
    final root = await sessionMetadata(id);
    if (root == null) return null;
    final tip = id == tipId ? root : await sessionMetadata(tipId);
    if (tip == null) {
      throw const FormatException('Canonical Bot Chat tip is unavailable');
    }
    bool flag(String name) => root[name] == true || root[name] == 1;
    return (
      tipId: tipId,
      row: Map<String, dynamic>.unmodifiable({
        ...root,
        ...tip,
        'id': id,
        'profile': scope.profileName,
        'title': 'Bot Chat',
        'preview': summary['preview'],
        'hidden': flag('hidden'),
        'archived': flag('archived'),
        'pinned': flag('pinned'),
        'last_active':
            tip['last_activity_at'] ?? tip['last_active'] ?? tip['started_at'],
      }),
    );
  }

  Future<ProfileSessionPage> sessions({
    SessionVisibility visibility = SessionVisibility.chats,
    int offset = 0,
    int limit = sessionPageSize,
    bool archivedOnly = false,
    bool includeArchived = false,
  }) async {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid session page');
    }
    final result = await read('sessions', {
      'limit': '$limit',
      'offset': '$offset',
      'order': 'recent',
      ...visibility.queryParameters,
      if (archivedOnly)
        'archived': 'only'
      else if (includeArchived)
        'archived': 'include',
    });
    if (result['offset'] != offset ||
        result['limit'] != limit ||
        result['total'] is! int ||
        (result['total'] as int) < 0) {
      throw const FormatException('Invalid session pagination metadata');
    }
    final rows = records(result['sessions']);
    for (final row in rows) {
      if (row['profile'] != scope.profileName ||
          row['id'] is! String ||
          (row['id'] as String).isEmpty) {
        throw const FormatException(
          'Session response has a different profile owner',
        );
      }
    }
    return ProfileSessionPage(
      rows: rows,
      offset: offset,
      limit: limit,
      total: result['total'] as int,
    );
  }

  Future<List<Map<String, dynamic>>> projects() async {
    final rows = records(
      (await call('projects.tree', {'preview_limit': 0}))['projects'],
    );
    final projects = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row['isNoProject'] == true) continue;
      if (row['id'] is! String ||
          row['label'] is! String ||
          row['lastActive'] is! num) {
        throw const FormatException('Invalid project overview');
      }
      projects.add({...row, 'name': row['label'], 'primary_path': row['path']});
    }
    projects.sort(
      (a, b) => (b['lastActive'] as num).compareTo(a['lastActive'] as num),
    );
    return projects;
  }

  Future<List<Map<String, dynamic>>> projectSessions(String projectId) async {
    await requireProfile();
    final result = await call('projects.project_sessions', {
      'project_id': projectId,
      'session_limit': projectSessionScanLimit,
    });
    final project = result['project'];
    if (project is! Map || project['id'] != projectId) {
      throw StateError('Project is no longer available');
    }
    final rows = <String, Map<String, dynamic>>{};
    for (final repo in records(project['repos'])) {
      for (final group in records(repo['groups'])) {
        for (final session in records(group['sessions'])) {
          if (session['profile'] != scope.profileName ||
              session['id'] is! String) {
            throw const FormatException('Invalid project session owner');
          }
          rows[session['id'] as String] = session;
        }
      }
    }
    return rows.values.toList();
  }

  Future<Map<String, dynamic>> createSession({
    required bool cwdExplicit,
    required bool Function() canDispatch,
    String? cwd,
    String? title,
  }) async {
    if (cwdExplicit && (cwd == null || cwd.trim().isEmpty)) {
      throw ArgumentError('An explicit working directory is required');
    }
    await requireProfile();
    final session = _ownedSession(
      await _browserCommand('session.create', {
        'source': 'desktop',
        'close_on_disconnect': false,
        'cwd': ?cwd,
        'cwd_explicit': cwdExplicit,
        'title': ?title,
      }, canDispatch),
    );
    // Stock Hermes resolves the destination and acknowledges it in info.cwd.
    // An unavailable directory can resolve elsewhere even with cwd_explicit.
    final info = session['info'];
    if (cwdExplicit &&
        (info is! Map ||
            info['cwd'] is! String ||
            _workingDirectoryKey(info['cwd'] as String) !=
                _workingDirectoryKey(cwd!))) {
      throw StateError(
        'Hermes could not open the selected project directory. The draft was not moved.',
      );
    }
    return session;
  }

  String _workingDirectoryKey(String path) {
    // Normalize server paths lexically; never resolve them on the Android host.
    // Hermes uses abspath, not realpath, so symbolic links retain their spelling.
    final windows =
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
    final normalized = Uri(
      path: windows ? path.replaceAll(r'\', '/') : path,
    ).normalizePath().path;
    return normalized.length > 1 && normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  Future<Map<String, dynamic>> resume(String durableId) async {
    await requireProfile();
    return _ownedSession(
      await call('session.resume', {
        'session_id': durableId,
        'omit_messages': true,
      }),
    );
  }

  Future<Map<String, dynamic>> branch(String runtimeId, int count) async {
    if (count <= 0) throw ArgumentError.value(count, 'count');
    await requireProfile();
    return _ownedSession(
      await call('session.branch', {'session_id': runtimeId, 'count': count}),
    );
  }

  /// The persisted transcript that session.branch copies, including archived
  /// turns and hidden notices. RPC history is a different, active projection.
  /// Resolve [throughRowId] before writing, then verify the child through the
  /// same REST representation instead of its projected RPC response.
  Future<List<Map<String, dynamic>>> branchHistory(
    String durableId, {
    int? throughRowId,
  }) async {
    var offset = 0;
    final messages = <Map<String, dynamic>>[];
    while (true) {
      final result =
          await read('sessions/${Uri.encodeComponent(durableId)}/messages', {
            'limit': '500',
            'offset': '$offset',
            'order': 'oldest',
            'include_compacted': 'true',
          });
      if (result['session_id'] != durableId) {
        throw StateError(
          'History changed. Reload the conversation before branching.',
        );
      }
      final rows = records(result['messages']);
      for (final row in rows) {
        if (isBranchMessage(row)) messages.add(row);
        if (throughRowId != null && row['id'] == throughRowId) {
          if (row['role'] != 'assistant' || !isBranchMessage(row)) break;
          return messages;
        }
      }
      if (rows.length < 500) break;
      offset += rows.length;
    }
    if (throughRowId == null) return messages;
    throw StateError(
      'The selected answer is no longer saved. Reload before branching.',
    );
  }

  Future<List<Map<String, dynamic>>> fullHistory(String runtimeId) async =>
      records(
        (await call('session.history', {'session_id': runtimeId}))['messages'],
      );

  /// Current stock resume uses session_key for persisted sessions and
  /// stored_session_id for a still-live session without a database row.
  /// Preserve the raw response; runtime identity never substitutes for storage.
  String resumeDurableId(Map<String, dynamic> result) {
    _ownedSession(result);
    String? identity(String field) {
      if (!result.containsKey(field)) return null;
      final value = result[field];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException(
          'Resume response has an invalid durable identity',
        );
      }
      return value;
    }

    final sessionKey = identity('session_key');
    final storedId = identity('stored_session_id');
    if (sessionKey == null && storedId == null) {
      throw const FormatException('Resume response has no durable identity');
    }
    if (sessionKey != null && storedId != null && sessionKey != storedId) {
      throw const FormatException(
        'Resume response has conflicting durable identities',
      );
    }
    return sessionKey ?? storedId!;
  }

  Map<String, dynamic> _ownedSession(Map<String, dynamic> result) {
    final info = result['info'];
    // Stock Hermes omits profile_name from a live session's lazy info while
    // its agent is uninitialized. The request is already profile-scoped.
    // Reject any explicit conflicting owner, including in a lazy response.
    if (info is! Map ||
        (info.containsKey('profile_name')
            ? info['profile_name'] != scope.profileName
            : info['lazy'] != true)) {
      throw const FormatException(
        'Session response has a different profile owner',
      );
    }
    if (result['session_id'] is! String ||
        (result['session_id'] as String).isEmpty) {
      throw const FormatException('Session response has no runtime identity');
    }
    return result;
  }

  static const historyPageSize = 50;

  /// Passive receipts across this saved chat's retained runtime event rings.
  /// Cold resume mints a new runtime; the process GUI log names earlier runtimes.
  Future<List<GatewayToolActivity>> completedToolActivities(
    String runtimeId, {
    required String sessionId,
  }) async {
    final currentRead = _completedRuntimeTools(runtimeId);
    final runtimes = await _savedToolRuntimes(sessionId);
    final completed = <String, GatewayToolActivity>{};
    void retain(Iterable<GatewayToolActivity> activities) {
      for (final activity in activities) {
        final id = activity.toolId!;
        completed.remove(id);
        completed[id] = activity;
      }
    }

    final previous = runtimes.where((id) => id != runtimeId).toList();
    // Bound simultaneous ring reads. A failed/evicted ring cannot discard
    // measurements from the other runtimes of the same saved conversation.
    for (var offset = 0; offset < previous.length; offset += 4) {
      final pages = await Future.wait(
        previous.skip(offset).take(4).map(_completedRuntimeTools),
      );
      for (final page in pages) {
        retain(page);
      }
    }
    retain(await currentRead);
    return List.unmodifiable(completed.values);
  }

  Future<List<String>> _savedToolRuntimes(String sessionId) async {
    try {
      // GUI logging and replay rings belong to the dashboard process. Do not
      // redirect this read to a named profile's separate agent log directory.
      final log = await _get('logs', {
        'file': 'gui',
        'search': sessionId,
        'lines': '500',
      });
      final lines = log['lines'];
      if (lines is! List) throw const FormatException('Missing GUI log lines');
      final accepted = RegExp(
        r'tui prompt accepted: ui_session=([0-9a-f]{8}) '
        r'session_key=(\S*) agent_session_id=(\S+) kind=',
      );
      final runtimes = <String>{};
      for (final line in lines.whereType<String>()) {
        final match = accepted.firstMatch(line);
        if (match == null ||
            (match.group(2) != sessionId && match.group(3) != sessionId)) {
          continue;
        }
        final id = match.group(1)!;
        runtimes.remove(id);
        runtimes.add(id);
      }
      // Stock replay retains at most 64 runtime rings. No log contents enter
      // the reading cache; only verified identities are used for these reads.
      return runtimes.toList().reversed.take(64).toList().reversed.toList();
    } catch (_) {
      // Log retention/access is independent of the current runtime's replay.
      return const [];
    }
  }

  Future<List<GatewayToolActivity>> _completedRuntimeTools(
    String runtimeId,
  ) async {
    try {
      final snapshot = await call('session.events.since', {
        'session_id': runtimeId,
        'last_seen': 0,
      });
      final events = snapshot['events'];
      if (events is! List) throw const FormatException('Missing event replay');
      final completed = <String, GatewayToolActivity>{};
      for (final event in events) {
        if (event is! Map ||
            event['session_id'] != runtimeId ||
            event['type'] != 'tool.complete' ||
            event['payload'] is! Map<String, dynamic>) {
          continue;
        }
        final activity = GatewayToolActivity.fromGatewayEvent(
          'tool.complete',
          event['payload'] as Map<String, dynamic>,
        );
        final id = activity?.toolId;
        if (id == null || activity!.durationSeconds == null) continue;
        // Deduplicate in last-completion order so bounded retention keeps newest
        // receipts when a replay exceeds the reading owner's observation limit.
        completed.remove(id);
        completed[id] = activity;
      }
      return List.unmodifiable(completed.values);
    } catch (_) {
      // A passive timing read cannot make authoritative history unavailable.
      return const [];
    }
  }

  Future<ProfileHistoryPage> history(
    String id, {
    int offset = 0,
    int limit = historyPageSize,
    bool inlineImages = true,
    String? runtimeId,
  }) async {
    if (id.isEmpty || offset < 0 || limit < 1 || limit > 500) {
      throw ArgumentError('Invalid history page');
    }
    final Map<String, dynamic> result;
    try {
      result = await read('sessions/${Uri.encodeComponent(id)}/messages', {
        'limit': '$limit',
        'offset': '$offset',
        'order': 'latest',
        'include_compacted': 'true',
        'inline_images': '$inlineImages',
      });
    } on DashboardHttpException catch (error) {
      if (error.statusCode != 404 ||
          offset != 0 ||
          runtimeId == null ||
          runtimeId.isEmpty) {
        rethrow;
      }
      // A live session can precede its database row. Read its actual history;
      // a missing durable row alone does not establish an empty transcript.
      return ProfileHistoryPage(
        id,
        await fullHistory(runtimeId),
        0,
        limit,
        isComplete: true,
      );
    }
    final pagination = result['pagination'];
    final rows = records(result['messages']);
    final resolved = result['session_id'];
    if (resolved is! String ||
        resolved.isEmpty ||
        pagination is! Map ||
        pagination['limit'] != limit ||
        pagination['offset'] != offset ||
        pagination['order'] != 'latest' ||
        pagination['returned'] != rows.length ||
        rows.length > limit ||
        rows.any((row) => row['id'] is! int)) {
      throw const FormatException('Invalid history page');
    }
    return ProfileHistoryPage(resolved, rows, offset, limit);
  }

  /// Exact, read-only ownership observation. Search is a discovery surface:
  /// stock Hermes may resolve a matched ID to its compression successor.
  /// Only the stock session-not-found receipt establishes absence; transport,
  /// profile and malformed response failures remain unavailable observations.
  Future<Map<String, dynamic>?> sessionMetadata(String sessionId) async {
    if (sessionId.isEmpty) throw ArgumentError('Missing session');
    await requireProfile();
    final endpoint = 'sessions/${Uri.encodeComponent(sessionId)}';
    final Map<String, dynamic> row;
    try {
      row = await read(endpoint);
    } on DashboardSessionNotFound catch (failure) {
      if (failure.endpoint != endpoint) rethrow;
      await requireProfile();
      return null;
    }
    if (row['id'] != sessionId || row['profile'] != scope.profileName) {
      throw const FormatException('Invalid session metadata owner');
    }
    return row;
  }

  /// Stock search is profile-bound but does not stamp owners in its response.
  /// Keep results in this client's scope; reject any contradictory owner field.
  Future<List<Map<String, dynamic>>> search(
    String query, {
    SessionVisibility visibility = SessionVisibility.chats,
  }) async {
    if (query.trim().isEmpty) return [];
    await requireProfile();
    final rows = records(
      (await read('sessions/search', {
        'q': query.trim(),
        ...visibility.queryParameters,
        'limit': '100',
      }))['results'],
    );
    for (final row in rows) {
      if (row['session_id'] is! String ||
          (row['session_id'] as String).isEmpty ||
          (row.containsKey('profile') && row['profile'] != scope.profileName)) {
        throw const FormatException('Invalid search result owner');
      }
    }
    return rows
        .map(
          (row) => <String, dynamic>{
            ...row,
            'id': row['session_id'],
            'profile': scope.profileName,
          },
        )
        .toList();
  }

  Future<Map<String, dynamic>> _browserCommand(
    String method,
    Map<String, dynamic> params,
    bool Function() canDispatch,
  ) async {
    await connect();
    if (!canDispatch()) {
      throw DashboardRequestNotSentException(
        StateError('Profile changed. Open the menu again.'),
      );
    }
    return call(method, params);
  }

  /// Bot workflows capture a profile before awaiting connection preparation.
  /// Admission is checked immediately before the stock RPC is dispatched.
  Future<Map<String, dynamic>> botCommand(
    String method,
    Map<String, dynamic> params, {
    required bool Function() canDispatch,
    required void Function() onDispatched,
  }) async {
    const allowed = {
      'profiles.configure',
      'profiles.create',
      'profiles.set_asset',
      'session.create',
      'session.title',
      'groups.create',
      'groups.send',
      'groups.rename',
      'groups.stop',
      'groups.disband',
      'groups.approve',
      'groups.retry',
      'image.generate',
      'display.start',
      'display.stop',
    };
    if (!allowed.contains(method)) throw ArgumentError('Unknown bot command');
    await connect();
    if (!canDispatch()) {
      throw DashboardRequestNotSentException(
        StateError('Bot operation closed'),
      );
    }
    onDispatched();
    return call(method, params);
  }

  Future<Map<String, dynamic>> createProject(
    String name,
    String path, {
    required bool Function() canDispatch,
  }) async {
    await requireProfile();
    final result = await _browserCommand('projects.create', {
      'name': name,
      'folders': [path],
      'primary_path': path,
    }, canDispatch);
    if (result['project'] is! Map) {
      throw const FormatException('Missing project');
    }
    return Map<String, dynamic>.from(result['project']);
  }

  /// Asks the selected Hermes host to scan its configured repository roots.
  Future<List<ProjectFolderSuggestion>> discoverProjectFolders() async {
    await requireProfile();
    final result = await call('projects.discover_repos', {'scan': true});
    final repos = result['repos'];
    if (repos is! List) {
      throw const FormatException('Missing discovered repositories');
    }

    final suggestions = <String, ProjectFolderSuggestion>{};
    for (final repo in repos) {
      if (repo is! Map || repo['root'] is! String || repo['label'] is! String) {
        throw const FormatException('Invalid discovered repository');
      }
      final path = (repo['root'] as String).trim();
      final label = (repo['label'] as String).trim();
      if (path.isEmpty || label.isEmpty) {
        throw const FormatException('Invalid discovered repository');
      }
      suggestions.putIfAbsent(
        path,
        () => ProjectFolderSuggestion(path: path, label: label),
      );
    }
    return List.unmodifiable(suggestions.values);
  }

  Future<Map<String, dynamic>> updateProject(
    String id, {
    String? name,
    String? color,
    String? icon,
    required bool Function() canDispatch,
  }) async {
    final projectId = id.trim();
    final projectName = name?.trim();
    if (projectId.isEmpty || projectName != null && projectName.isEmpty) {
      throw ArgumentError('A project id and non-empty name are required');
    }
    final changes = <String, dynamic>{
      if (name != null) 'name': projectName,
      if (color != null) 'color': color.trim(),
      if (icon != null) 'icon': icon.trim(),
    };
    if (changes.isEmpty) throw ArgumentError('No project changes supplied');
    await requireProfile();
    final result = await _browserCommand('projects.update', {
      'id': projectId,
      ...changes,
    }, canDispatch);
    final project = result['project'];
    if (project is! Map || project['id'] != projectId) {
      throw const FormatException('Project update not acknowledged');
    }
    return Map<String, dynamic>.from(project);
  }

  Future<void> deleteProject(
    String id, {
    required bool Function() canDispatch,
  }) async {
    final projectId = id.trim();
    if (projectId.isEmpty) throw ArgumentError('Missing project');
    await requireProfile();
    final result = await _browserCommand('projects.delete', {
      'id': projectId,
    }, canDispatch);
    final projects = result['projects'];
    final activeId = result['active_id'];
    if (projects is! List ||
        projects.any((project) => project is! Map) ||
        projects.any((project) => (project as Map)['id'] == projectId) ||
        activeId != null && activeId is! String ||
        activeId == projectId) {
      throw const FormatException('Project delete not acknowledged');
    }
  }

  Future<Map<String, dynamic>> updateSession(
    String id,
    Map<String, dynamic> changes, {
    required bool Function() canDispatch,
  }) async {
    if (id.isEmpty ||
        changes.isEmpty ||
        changes.keys.any(
          (key) => !{'title', 'pinned', 'archived', 'unread'}.contains(key),
        )) {
      throw ArgumentError('Invalid session update');
    }
    await requireProfile();
    final patch = _ownedPatch;
    if (patch == null) {
      throw StateError('Session mutation transport unavailable');
    }
    final result = await patch(
      'sessions/${Uri.encodeComponent(id)}',
      {...changes, 'profile': scope.profileName},
      canDispatch,
      () {},
    );
    if (result['ok'] != true) {
      throw const FormatException('Session update not acknowledged');
    }
    return result;
  }

  /// Same operation as Desktop: moves the stored workspace, not a local tag.
  Future<Map<String, dynamic>> moveSession(
    String id,
    String cwd, {
    required bool Function() canDispatch,
  }) async {
    if (id.isEmpty || cwd.trim().isEmpty) {
      throw ArgumentError('A chat and project folder are required');
    }
    await requireProfile();
    // Stock workspace.move finds live agents by durable ID without checking
    // profile ownership. Resolve the owner and reject colliding live sessions.
    final live = records((await call('session.active_list'))['sessions']);
    if (live.any((row) => row['session_key'] == id)) {
      final session = _ownedSession(
        await _browserCommand('session.resume', {
          'session_id': id,
          'omit_messages': true,
        }, canDispatch),
      );
      final storedId = session['stored_session_id'] ?? session['session_key'];
      if (storedId != id ||
          session.containsKey('session_key') && session['session_key'] != id) {
        throw const FormatException('Session response has a different chat');
      }
      final matching = records(
        (await call('session.active_list'))['sessions'],
      ).where((row) => row['session_key'] == id).toList();
      if (matching.length != 1 ||
          matching.single['id'] != session['session_id']) {
        throw StateError(
          'Hermes could not verify this chat\'s project owner. '
          'Refresh and try moving again.',
        );
      }
      if (matching.single['status'] != 'idle') {
        throw StateError(
          'This chat is working or waiting for input on Hermes. '
          'Stop it or let it finish before moving.',
        );
      }
    }
    final result = await _browserCommand('session.workspace.move', {
      'session_key': id,
      'cwd': cwd,
    }, canDispatch);
    if (result['cwd'] is! String ||
        (result['cwd'] as String).trim().isEmpty ||
        (result['branch'] != null && result['branch'] is! String) ||
        (result['git_repo_root'] != null &&
            result['git_repo_root'] is! String)) {
      throw const FormatException('Invalid workspace move response');
    }
    return {
      'cwd': result['cwd'],
      'git_branch': result['branch'],
      'git_repo_root': result['git_repo_root'],
    };
  }

  /// Desktop uses the primary folder, then the first repository folder.
  static String projectDirectory(Map<String, dynamic> project) {
    final primary = (project['primary_path'] ?? project['path'])?.toString();
    if (primary != null && primary.trim().isNotEmpty) return primary.trim();
    for (final repo in (project['repos'] as List? ?? const [])) {
      if (repo is Map && repo['path'] is String) {
        final path = (repo['path'] as String).trim();
        if (path.isNotEmpty) return path;
      }
    }
    return '';
  }

  /// Read-only recovery observation for an uncertain deletion receipt. A generic
  /// 404 may mean the profile disappeared; only exact stock detail absence and
  /// fresh profile membership authorize local cleanup. Later server races remain.
  Future<SessionPresence> verifyDeletedSession(String id) async {
    if (id.isEmpty) return SessionPresence.unavailable;
    try {
      await requireProfile();
      final endpoint = 'sessions/${Uri.encodeComponent(id)}';
      final Map<String, dynamic> row;
      try {
        row = await read(endpoint);
      } on DashboardSessionNotFound catch (failure) {
        if (failure.endpoint != endpoint) return SessionPresence.unavailable;
        await requireProfile();
        return SessionPresence.absent;
      }
      if (row['id'] != id || row['profile'] != scope.profileName) {
        return SessionPresence.unavailable;
      }
      await requireProfile();
      return SessionPresence.present;
    } catch (_) {
      return SessionPresence.unavailable;
    }
  }

  Future<void> deleteSession(
    String id, {
    required bool Function() canDispatch,
  }) async {
    if (id.isEmpty) throw ArgumentError('Missing session');
    await requireProfile();
    final remove = _ownedDelete;
    if (remove == null) {
      throw StateError('Session mutation transport unavailable');
    }
    var admitted = false;
    var historyDispatched = false;
    bool active() => canDispatch() || admitted && !historyDispatched;
    final live = records((await call('session.active_list'))['sessions']);
    if (live.any((row) => row['session_key'] == id)) {
      // The live list has no profile owner. Resolve through scoped resume before
      // closing anything: the same durable ID can exist in another profile.
      final session = _ownedSession(
        await _browserCommand('session.resume', {
          'session_id': id,
          'omit_messages': true,
        }, canDispatch),
      );
      // Fresh resumes expose stored_session_id; reusing an open runtime exposes
      // session_key instead. If both are present they must agree.
      final storedId = session['stored_session_id'] ?? session['session_key'];
      if (storedId != id ||
          session.containsKey('session_key') && session['session_key'] != id) {
        throw const FormatException('Session response has a different chat');
      }
      final runtimeId = session['session_id'] as String;
      final current = records((await call('session.active_list'))['sessions'])
          .where((row) => row['id'] == runtimeId && row['session_key'] == id)
          .toList();
      if (current.length != 1 || current.single['status'] != 'idle') {
        throw StateError(
          'This chat is working or waiting for input on Hermes. '
          'Stop it or let it finish before deleting.',
        );
      }
      // Finalize the runtime before removing its stored history, so a later
      // agent flush cannot write into a deleted session.
      final result = await _browserCommand(
        'session.close',
        {'session_id': runtimeId},
        () {
          if (!canDispatch()) return false;
          admitted = true;
          return true;
        },
      );
      if (result['closed'] != true) {
        throw StateError(
          'Hermes could not close this chat. Try deleting again.',
        );
      }
    }
    final result = await remove(
      'sessions/${Uri.encodeComponent(id)}',
      {'profile': scope.profileName},
      active,
      () {
        historyDispatched = true;
      },
    );
    if (result['ok'] != true) {
      throw const FormatException('Session deletion not acknowledged');
    }
  }

  static List<Map<String, dynamic>> records(Object? value) {
    if (value is! List || value.any((row) => row is! Map)) {
      throw const FormatException('Expected a list of records');
    }
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
}
