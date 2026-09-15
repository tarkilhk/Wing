import 'core/widgets/studio_action_label.dart';
import 'core/widgets/studio_error.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/widgets/compact_switch.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/android_launch_intent_service.dart';
import 'core/services/android_share_intent_service.dart';
import 'core/services/config_backup.dart';
import 'core/services/config_backup_io.dart';
import 'core/services/config_backup_service.dart';
import 'core/services/connection_manager.dart';
import 'core/services/composer_draft_store.dart';
import 'core/services/ws_client.dart';
import 'core/services/text_size_preference.dart';
import 'core/screens/profile_workspace_screen.dart';
import 'core/screens/shared_draft_review.dart';
import 'core/services/profile_workspace_controller.dart';
import 'core/services/profile_connection_identity.dart';
import 'core/services/profile_workspace_registry.dart';
import 'core/services/profile_gateway.dart';
import 'core/services/profiles_repository.dart';
import 'core/models/hermes_profile.dart';
import 'core/services/turn_notification_service.dart';
import 'core/services/background_push_service.dart';
import 'core/theme/wing_theme.dart';
import 'core/theme/profile_workspace_theme.dart';
import 'core/widgets/app_drawer.dart';
import 'core/widgets/wing_welcome.dart';
import 'core/screens/app_settings_content.dart';
import 'core/widgets/config_backup_card.dart';
import 'core/widgets/gateway_headers_editor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final connManager = await ConnectionManager.create(prefs);
  final shareIntents = AndroidShareIntentService();
  final launchIntents = AndroidLaunchIntentService();
  await Future.wait([shareIntents.initialize(), launchIntents.initialize()]);
  runApp(
    WingApp(
      connManager: connManager,
      shareIntents: shareIntents,
      launchIntents: launchIntents,
    ),
  );
}

class WingApp extends StatefulWidget {
  final ConnectionManager connManager;
  final AndroidShareIntentService? shareIntents;
  final AndroidLaunchIntentService? launchIntents;
  final Future<void>? startupExternalNavigationReady;

  /// When supplied, this app owns and disposes the registry.
  final ProfileWorkspaceRegistry? profileControllers;
  const WingApp({
    required this.connManager,
    this.shareIntents,
    this.launchIntents,
    this.startupExternalNavigationReady,
    this.profileControllers,
    super.key,
  });

  @override
  State<WingApp> createState() => WingAppState();

  static ThemeMode getThemeMode(SharedPreferences prefs) {
    final stored = prefs.getString('theme_mode') ?? 'system';
    switch (stored) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(
    SharedPreferences prefs,
    ThemeMode mode,
  ) async {
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await prefs.setString('theme_mode', value);
  }

  static TextSizePreference getTextSizePreference(SharedPreferences prefs) {
    return TextSizePreferenceStore(prefs).read();
  }
}

class WingAppState extends State<WingApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _homeKey = GlobalKey<HomeScreenState>();
  final _notificationRoutes = <ProfileWorkspaceController, Route<void>>{};
  late final ProfileWorkspaceRegistry _profileControllers;
  late final PluginTurnNotificationSink _profileNotifications;
  late final PushDeliveryLedger _notificationDeliveries;
  late final Future<void> _notificationsReady;
  Future<BackgroundPushService?>? _backgroundPushReady;
  late final ValueNotifier<BackgroundPushState> _backgroundPushState;
  ProfileSessionKey? _pendingNotificationKey;
  Future<void>? _pendingNotificationOpen;
  int _notificationOpenGeneration = 0;
  String? _deferredShareId;
  bool _disposed = false;

  Future<ProfileWorkspaceController> profileController(
    SavedConnection connection,
  ) async {
    // Home and incoming share routes can hold an older metadata snapshot after
    // settings edits or config restore. Resolve the current secure credentials.
    final current = (await widget.connManager.loadConnectionsWithSecrets())
        .where((c) => c.id == connection.id)
        .firstOrNull;
    if (current == null) throw StateError('The connection is unavailable');
    return _profileControllers.forConnection(current);
  }

  Future<void> enableProfileNotifications() async {
    await _notificationsReady;
    final granted = await _profileNotifications.requestPermission();
    if (granted == false) {
      throw StateError('Notifications are disabled in Android settings.');
    }
    await widget.connManager.prefs.setBool(
      backgroundPushPermissionRequestedKey,
      true,
    );
    await _profileNotifications.show(
      const TurnNotification(
        id: 214600,
        title: 'Wing notification test',
        body: 'Local alerts are working on this device.',
        payload: '',
        channel: TurnNotificationService.turnChannel,
      ),
    );
    unawaited(_syncBackgroundPush());
  }

  Future<void> openProfileNotification(String payload) async {
    if (payload.isEmpty) return; // Test alerts have no conversation target.
    final ProfileSessionKey key;
    try {
      key = ProfileSessionKey.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
    } catch (_) {
      _notificationOpenGeneration++;
      _pendingNotificationKey = null;
      _pendingNotificationOpen = null;
      _showNotificationOpenError();
      return;
    }
    _deferPendingShareForNotification();

    final pending = _pendingNotificationOpen;
    if (_pendingNotificationKey == key && pending != null) return pending;

    final generation = ++_notificationOpenGeneration;
    final opening = _openProfileNotificationTarget(key, generation);
    _pendingNotificationKey = key;
    _pendingNotificationOpen = opening;
    try {
      await opening;
    } finally {
      if (identical(_pendingNotificationOpen, opening)) {
        _pendingNotificationKey = null;
        _pendingNotificationOpen = null;
      }
    }
  }

  void _deferPendingShareForNotification() {
    final pendingShareId = widget.shareIntents?.pendingShare.value?.id;
    if (pendingShareId == null) return;
    _deferredShareId = pendingShareId;
    _homeKey.currentState?.deferPendingShareAutoOpen(pendingShareId);
  }

  bool _isCurrentNotificationOpen(int generation) =>
      mounted && generation == _notificationOpenGeneration;

  Future<void> _openProfileNotificationTarget(
    ProfileSessionKey key,
    int generation,
  ) async {
    try {
      final connection = (await widget.connManager.loadConnectionsWithSecrets())
          .where((c) => c.id == key.workspace.connectionId)
          .firstOrNull;
      if (!_isCurrentNotificationOpen(generation)) return;
      if (connection == null) {
        throw StateError('The original connection is unavailable');
      }
      final controller = await _profileControllers.forSession(connection, key);
      if (!_isCurrentNotificationOpen(generation)) return;
      if (controller.discovery == null) await controller.initialize();
      if (!_isCurrentNotificationOpen(generation)) return;
      await controller.openSession(key);
      if (!_isCurrentNotificationOpen(generation)) return;
      if (controller.current?.scope != key.workspace ||
          controller.current?.chat?.key != key) {
        throw StateError('The notification target is unavailable');
      }
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        throw StateError('Notification navigation is unavailable');
      }
      final existingRoute = _notificationRoutes[controller];
      if (existingRoute != null && existingRoute.isActive) {
        navigator.popUntil((route) => identical(route, existingRoute));
        return;
      }
      final route = MaterialPageRoute<void>(
        builder: (_) => ProfileWorkspaceScreen(
          controller: controller,
          enableNotifications: enableProfileNotifications,
          onConnections: openConnections,
          onPreferencesChanged: refreshPreferences,
        ),
      );
      _notificationRoutes[controller] = route;
      unawaited(
        route.popped.then((_) {
          if (identical(_notificationRoutes[controller], route)) {
            _notificationRoutes.remove(controller);
          }
        }),
      );
      navigator.push(route);
    } catch (_) {
      if (!_isCurrentNotificationOpen(generation)) return;
      // Malformed or removed targets cannot be rerouted to a default profile.
      _showNotificationOpenError();
    }
  }

  void _showNotificationOpenError() {
    final context = _navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: StudioError(
            'This chat is unavailable on its original host or profile.',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profileNotifications = PluginTurnNotificationSink(
      onOpen: (payload) {
        if (payload.isNotEmpty) _deferPendingShareForNotification();
        unawaited(
          WidgetsBinding.instance.endOfFrame.then(
            (_) => openProfileNotification(payload),
          ),
        );
      },
    );
    _notificationDeliveries = PushDeliveryLedger(widget.connManager.prefs);
    _backgroundPushState = ValueNotifier(
      wingFirebaseOptions() == null
          ? BackgroundPushState.unavailableBuild
          : BackgroundPushState.syncing,
    );
    _notificationsReady =
        widget.startupExternalNavigationReady ??
        _profileNotifications.initialize().catchError((Object _) {});
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) => _syncBackgroundPush()),
    );
    _profileControllers =
        widget.profileControllers ??
        ProfileWorkspaceRegistry(
          identities: ProfileConnectionIdentity(),
          create: (connection, identity) => ProfileWorkspaceController(
            connection: connection,
            connectionIdentity: identity,
            preferences: widget.connManager.prefs,
            onAttention: (chat, needsInput, [eventId]) async {
              final preference = needsInput
                  ? attentionNotificationsKey
                  : completionNotificationsKey;
              if (widget.connManager.prefs.getBool(preference) == false) return;
              await _notificationsReady;
              if (await _profileNotifications.notificationsEnabled() == false) {
                return;
              }
              if (eventId != null &&
                  !await _notificationDeliveries.claim(eventId)) {
                return;
              }
              final payload = jsonEncode(chat.key.toJson());
              try {
                await _profileNotifications.show(
                  TurnNotification(
                    id: TurnNotificationService.notificationIdFor(
                      eventId == null ? payload : 'push-event:$eventId',
                    ),
                    title: needsInput
                        ? 'Needs your attention'
                        : 'Finished working',
                    body:
                        widget.connManager.prefs.getBool(
                              notificationTitlesKey,
                            ) ==
                            true
                        ? chat.title
                        : 'Tap to open the chat.',
                    payload: payload,
                    channel: TurnNotificationService.turnChannel,
                  ),
                );
              } catch (_) {
                if (eventId != null) {
                  await _notificationDeliveries.release(eventId);
                }
                rethrow;
              }
            },
          ),
        );
  }

  void refreshPreferences() {
    if (mounted) setState(() {});
    unawaited(_syncBackgroundPush());
  }

  Future<void> _syncBackgroundPush() async {
    if (_disposed) return;
    try {
      await (await _backgroundPush())?.sync();
    } catch (_) {
      if (!_disposed) {
        _backgroundPushState.value = BackgroundPushState.unavailableServer;
      }
      // Registration failure must not interrupt local Wing use.
    }
  }

  Future<BackgroundPushService?> _backgroundPush() {
    if (wingFirebaseOptions() == null) return Future.value(null);
    final existing = _backgroundPushReady;
    if (existing != null) return existing;
    final attempt = BackgroundPushService.create(
      preferences: widget.connManager.prefs,
      connectionManager: widget.connManager,
      notifications: _profileNotifications,
      deliveries: _notificationDeliveries,
      onOpen: openProfileNotification,
      state: _backgroundPushState,
    );
    _backgroundPushReady = attempt;
    return attempt.catchError((Object error) {
      if (identical(_backgroundPushReady, attempt)) {
        _backgroundPushReady = null;
      }
      if (!_disposed) {
        _backgroundPushState.value = BackgroundPushState.unavailableServer;
      }
      throw error;
    });
  }

  Future<void> _unregisterBackgroundPush(SavedConnection connection) async {
    try {
      await (await _backgroundPush())?.unregisterConnection(connection);
    } catch (_) {
      // The server expires registrations that cannot be removed while offline.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncBackgroundPush());
    }
  }

  void openConnections() {
    _homeKey.currentState?.showConnections();
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  Future<void> setTextSizePreference(TextSizePreference preference) async {
    await TextSizePreferenceStore(widget.connManager.prefs).save(preference);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Wing',
      themeMode: WingApp.getThemeMode(widget.connManager.prefs),
      theme: profileWorkspaceTheme(
        wingTheme(Brightness.light),
        accent: WorkspaceAccent.fromName(
          widget.connManager.prefs.getString(WorkspaceAccent.preferenceKey),
        ),
      ),
      darkTheme: profileWorkspaceTheme(
        wingTheme(Brightness.dark),
        accent: WorkspaceAccent.fromName(
          widget.connManager.prefs.getString(WorkspaceAccent.preferenceKey),
        ),
      ),
      builder: (context, child) {
        final systemMediaQuery = MediaQuery.of(context);
        final preference = WingApp.getTextSizePreference(
          widget.connManager.prefs,
        );
        return MediaQuery(
          data: systemMediaQuery.copyWith(
            textScaler: preference.applyTo(systemMediaQuery.textScaler),
          ),
          child: child!,
        );
      },
      home: HomeScreen(
        key: _homeKey,
        profileController: profileController,
        enableProfileNotifications: enableProfileNotifications,
        connManager: widget.connManager,
        onPreferencesChanged: refreshPreferences,
        onConfigurationChanged: () => unawaited(_syncBackgroundPush()),
        onConnectionInvalidated: _unregisterBackgroundPush,
        backgroundPushState: _backgroundPushState,
        shareIntents: widget.shareIntents,
        launchIntents: widget.launchIntents,
        startupExternalNavigationReady: _notificationsReady,
        deferredShareId: _deferredShareId,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final backgroundPush = _backgroundPushReady;
    if (backgroundPush != null) {
      unawaited(() async {
        try {
          await (await backgroundPush)?.dispose();
        } catch (_) {
          // A failed initialization has no live subscriptions to release.
        } finally {
          _backgroundPushState.dispose();
        }
      }());
    } else {
      _backgroundPushState.dispose();
    }
    _profileControllers.dispose();
    super.dispose();
  }
}

class HomeScreen extends StatefulWidget {
  final FutureOr<ProfileWorkspaceController> Function(SavedConnection)?
  profileController;
  final Future<void> Function()? enableProfileNotifications;
  final ConnectionManager connManager;
  final VoidCallback? onPreferencesChanged;
  final VoidCallback? onConfigurationChanged;
  final Future<void> Function(SavedConnection connection)?
  onConnectionInvalidated;
  final ValueListenable<BackgroundPushState>? backgroundPushState;
  final AndroidShareIntentService? shareIntents;
  final AndroidLaunchIntentService? launchIntents;
  final Future<void>? startupExternalNavigationReady;
  final String? deferredShareId;
  final Future<String> Function(String passphrase)? exportBackup;
  final Future<String?> Function(String contents)? deliverBackup;
  final Future<String?> Function()? pickBackupFile;
  final Future<ConfigImportResult> Function(
    String contents,
    String passphrase,
    ConfigImportMode mode,
  )?
  importBackup;

  const HomeScreen({
    this.profileController,
    this.enableProfileNotifications,
    required this.connManager,
    this.onPreferencesChanged,
    this.onConfigurationChanged,
    this.onConnectionInvalidated,
    this.backgroundPushState,
    this.shareIntents,
    this.launchIntents,
    this.startupExternalNavigationReady,
    this.deferredShareId,
    this.exportBackup,
    this.deliverBackup,
    this.pickBackupFile,
    this.importBackup,
    super.key,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<SavedConnection> _connections = [];
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _autoNavigated = false;
  bool _opening = false;
  bool _exportingBackup = false;
  bool _reviewingShare = false;
  bool _discardingShare = false;
  bool _startupExternalNavigationReady = false;
  String? _deferredShareId;
  AppDestination _destination = AppDestination.connections;
  static const String _lastConnectionKey = 'last_connection_id';

  void _refresh() {
    setState(() => _connections = widget.connManager.getConnections());
    widget.onConfigurationChanged?.call();
  }

  /// Public only so the import flow and its widget test can refresh Home after
  /// restoring connections without restarting the process.
  void refreshConnections() => _refresh();

  void showConnections() {
    if (mounted) setState(() => _destination = AppDestination.connections);
  }

  ConfigBackupIo get _backupIo =>
      ConfigBackupIo(connectionManager: widget.connManager);

  Future<void> _showBackupConfig() async {
    if (_exportingBackup) return;
    setState(() => _exportingBackup = true);
    try {
      final choice = await showModalBottomSheet<ExportPassphraseChoice>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const ExportPassphraseSheet(),
      );
      if (choice == null || !mounted) return;

      final exporter = widget.exportBackup ?? _backupIo.exportBackup;
      final deliver = widget.deliverBackup ?? _backupIo.deliverExport;
      final contents = await exporter(choice.passphrase);
      if (!mounted) return;
      final destination = await deliver(contents);
      if (!mounted || destination == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup exported — $destination')));
    } catch (error) {
      if (!mounted) return;
      final message = error is ConfigBackupException
          ? error.message
          : 'The backup could not be exported.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: StudioError(message)));
    } finally {
      if (mounted) setState(() => _exportingBackup = false);
    }
  }

  Future<void> _showRestoreConfig() async {
    String? contents;
    try {
      contents =
          await (widget.pickBackupFile?.call() ?? _backupIo.pickBackupFile());
    } catch (error) {
      if (!mounted) return;
      _showRestoreError(error);
      return;
    }
    if (contents == null || !mounted) return;

    final choice = await showModalBottomSheet<ImportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ImportOptionsSheet(),
    );
    if (choice == null || !mounted) return;

    try {
      final importer = widget.importBackup ?? _backupIo.importBackup;
      final result = await importer(contents, choice.passphrase, choice.mode);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.summary)));
    } catch (error) {
      if (!mounted) return;
      _showRestoreError(error);
    }
  }

  void _showRestoreError(Object error) {
    final message = error is ConfigBackupException
        ? error.message
        : 'The backup could not be restored.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: StudioError(message)));
  }

  @override
  void initState() {
    super.initState();
    _deferredShareId = widget.deferredShareId;
    _refresh();
    widget.shareIntents?.pendingShare.addListener(_onSharedText);
    widget.shareIntents?.intakeError.addListener(_onShareError);
    widget.launchIntents?.pendingQuickChat.addListener(_onQuickChat);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onShareError();
      _onQuickChat();
    });
    final ready = widget.startupExternalNavigationReady;
    if (ready == null) {
      _startupExternalNavigationReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSharedText());
    } else {
      unawaited(_enableStartupExternalNavigation(ready));
    }
  }

  Future<void> _enableStartupExternalNavigation(Future<void> ready) async {
    await ready;
    if (!mounted) return;
    _startupExternalNavigationReady = true;
    _onSharedText();
  }

  void deferPendingShareAutoOpen(String id) {
    _deferredShareId = id;
  }

  SavedConnection? _connectionForExternalAction() {
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    final preferred = _connections
        .where((connection) => connection.id == lastId)
        .firstOrNull;
    return preferred ?? (_connections.length == 1 ? _connections.single : null);
  }

  void _onSharedText() => _openSharedText(explicit: false);

  void _reviewPendingShare() => _openSharedText(explicit: true);

  void _openSharedText({required bool explicit}) {
    if (!mounted) return;
    setState(() {});
    final payload = widget.shareIntents?.pendingShare.value;
    if (payload == null ||
        !_startupExternalNavigationReady ||
        (!explicit && payload.id == _deferredShareId) ||
        _reviewingShare ||
        _discardingShare ||
        _connections.isEmpty) {
      return;
    }
    _autoNavigated = true;
    unawaited(_reviewIncomingShare());
  }

  void _onShareError() {
    final message = widget.shareIntents?.intakeError.value;
    if (!mounted || message == null) return;
    widget.shareIntents?.intakeError.value = null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: StudioError(message)));
  }

  Future<void> _discardIncomingShare() async {
    final service = widget.shareIntents;
    final payload = service?.pendingShare.value;
    if (service == null || payload == null || _discardingShare) return;
    setState(() => _discardingShare = true);
    final discarded = await service.acknowledgeShare(payload);
    if (!mounted) return;
    setState(() => _discardingShare = false);
    if (!discarded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: StudioError(
            'The shared content could not be discarded. Please try again.',
          ),
        ),
      );
    } else {
      _onSharedText();
    }
  }

  Future<void> _reviewIncomingShare() async {
    final payload = widget.shareIntents?.pendingShare.value;
    if (payload == null || _reviewingShare) return;
    _reviewingShare = true;
    try {
      final originalConnection = _connections
          .where((connection) => connection.id == payload.target?['connection'])
          .firstOrNull;
      final connection =
          originalConnection ??
          (_connections.length == 1
              ? _connections.single
              : await showModalBottomSheet<SavedConnection>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        const ListTile(
                          title: Text(
                            'Choose a connection for this shared draft',
                          ),
                        ),
                        for (final connection in _connections)
                          ListTile(
                            title: Text(connection.label),
                            onTap: () => Navigator.pop(context, connection),
                          ),
                      ],
                    ),
                  ),
                ));
      if (connection != null && mounted) {
        await _navigateToWorkspace(connection, sharedPayload: payload);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: StudioError(
              'The shared draft could not be opened. It is still available to review.',
            ),
          ),
        );
      }
    } finally {
      _reviewingShare = false;
      if (mounted) {
        setState(() {});
        final next = widget.shareIntents?.pendingShare.value;
        if (next != null && !identical(next, payload)) _onSharedText();
      }
    }
  }

  void _onQuickChat() {
    if (!mounted || widget.launchIntents?.pendingQuickChat.value != true) {
      return;
    }
    final connection = _connectionForExternalAction();
    if (connection == null) return;
    _autoNavigated = true;
    _navigateToWorkspace(connection);
  }

  @override
  void dispose() {
    widget.shareIntents?.pendingShare.removeListener(_onSharedText);
    widget.shareIntents?.intakeError.removeListener(_onShareError);
    widget.launchIntents?.pendingQuickChat.removeListener(_onQuickChat);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoNavigated && _connections.isNotEmpty) {
      _autoNavigated = true;
      _maybeAutoNavigate();
    }
  }

  void _maybeAutoNavigate() {
    // The share listener owns this route so the regular last-connection
    // auto-navigation cannot stack a second Workspace above the shared draft.
    if (widget.shareIntents?.pendingShare.value != null ||
        widget.launchIntents?.pendingQuickChat.value == true) {
      return;
    }
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    if (lastId == null) return;
    final conn = _connections.where((c) => c.id == lastId).firstOrNull;
    if (conn == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToWorkspace(conn);
    });
  }

  Future<void> _navigateToWorkspace(
    SavedConnection conn, {
    AppDestination destination = AppDestination.chats,
    AndroidSharePayload? sharedPayload,
  }) async {
    if (_opening || (_reviewingShare && sharedPayload == null)) return;
    setState(() => _opening = true);
    final ProfileWorkspaceController controller;
    try {
      controller = await widget.profileController!(conn);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: StudioError(
              'Connection ownership could not be verified securely.',
            ),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) return;
    widget.connManager.prefs.setString(_lastConnectionKey, conn.id);
    if (sharedPayload != null) {
      if (controller.discovery == null) await controller.initialize();
      ProfileChat? initialChat;
      ({ProfileSessionKey key, ComposerDraftSnapshot draft})? recoverableDraft;
      ProfileSessionKey? verifiedTarget;
      final target = sharedPayload.target;
      if (target != null) {
        try {
          final key = ProfileSessionKey.fromJson(target);
          if (controller.owns(key) &&
              controller.discovery?.named(key.workspace.profileName) != null) {
            verifiedTarget = key;
            await controller.navigateProfile(key.workspace.profileName);
            final opened = await controller.openSession(
              key,
              recoverExpiredDraft: true,
            );
            if (opened != null && identical(controller.current?.chat, opened)) {
              initialChat = opened;
            }
          }
        } catch (error) {
          // Keep the photo available for explicit destination selection.
          if (error is JsonRpcError &&
              error.method == 'session.resume' &&
              error.code == 4007 &&
              error.message.trim().toLowerCase() == 'session not found' &&
              verifiedTarget != null &&
              controller.current?.chats.containsKey(verifiedTarget.sessionId) ==
                  false) {
            final draft = await controller.savedDraft(verifiedTarget);
            if (draft != null) {
              recoverableDraft = (key: verifiedTarget, draft: draft);
            }
          }
        }
      }
      final profile = controller.current?.scope.profileName;
      if (profile == null) {
        throw StateError('No profile is available for this shared draft.');
      }
      if (initialChat == null) await controller.navigateProfile(profile);
      if (!mounted) return;
      final applied = await reviewSharedDraft(
        context,
        controller,
        sharedPayload,
        initialChat: initialChat,
        recoverableDraft: recoverableDraft,
        destinationNotice: target != null && initialChat == null
            ? 'The original chat could not be reopened. Choose a destination below.'
            : null,
      );
      if (!mounted || !applied) return;
      final acknowledged = await widget.shareIntents!.acknowledgeShare(
        sharedPayload,
      );
      if (!mounted) return;
      if (!acknowledged) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: StudioError(
              'Content was added to the draft, but the incoming share could not be cleared. Discard it from Home to avoid adding it twice.',
            ),
          ),
        );
      }
    }
    final initialQuickChat =
        widget.launchIntents?.takePendingQuickChat() == true &&
        sharedPayload == null;
    if (sharedPayload?.target != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileWorkspaceScreen(
          controller: controller,
          onCapturePhoto: widget.shareIntents == null
              ? null
              : (key) => widget.shareIntents!.capturePhoto(key.toJson()),
          enableNotifications: widget.enableProfileNotifications,
          initialDestination: sharedPayload != null || initialQuickChat
              ? AppDestination.chats
              : destination,
          onConnections: () {
            if (mounted) {
              setState(() => _destination = AppDestination.connections);
            }
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          onPreferencesChanged: widget.onPreferencesChanged,
          initialQuickChat: initialQuickChat,
        ),
      ),
    );
  }

  void _showAddDialog() => _showConnectionDialog();

  void _showEditConnectionDialog(SavedConnection conn) {
    _showConnectionDialog(existing: conn);
  }

  void _showConnectionDialog({SavedConnection? existing}) {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(
        initialConnection: existing,
        onSave:
            (
              label,
              host,
              port,
              apiKey, {
              gatewayPrefix,
              dashboardPrefix,
              dashboardProxied = false,
              desktopGatewayUrl,
              dashboardPort,
              dashboardUsername,
              dashboardPassword,
              gatewayHeaders,
            }) async {
              if (existing == null) {
                await widget.connManager.saveConnection(
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  desktopGatewayUrl: desktopGatewayUrl,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                  gatewayHeaders: resolveGatewayHeaderUpdate(
                    const {},
                    gatewayHeaders,
                  ),
                );
              } else {
                final unregister = widget.onConnectionInvalidated?.call(
                  existing,
                );
                if (unregister != null) unawaited(unregister);
                await widget.connManager.updateConnection(
                  existing.id,
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  desktopGatewayUrl: desktopGatewayUrl,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                  gatewayHeaders: gatewayHeaders,
                );
              }
              _refresh();
            },
      ),
    );
  }

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(
            Icons.dns_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(conn.label),
        subtitle: Text(
          '${conn.host}:${conn.dashboardPort}${conn.dashboardPrefix ?? ''}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') {
              try {
                final unregister = widget.onConnectionInvalidated?.call(conn);
                if (unregister != null) unawaited(unregister);
                await widget.connManager.deleteConnection(conn.id);
                if (mounted) _refresh();
              } on CredentialStorageException {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: StudioError(
                      'The connection could not be deleted safely.',
                    ),
                  ),
                );
              }
            } else if (v == 'edit') {
              _showEditConnectionDialog(conn);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit connection')),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
        onTap: _opening ? null : () => _navigateToWorkspace(conn),
      ),
    );
  }

  void _selectDestination(AppDestination destination) {
    if (destination == AppDestination.connections ||
        destination == AppDestination.settings) {
      setState(() => _destination = destination);
      return;
    }
    final connection = _connectionForExternalAction();
    if (connection != null) {
      _navigateToWorkspace(connection, destination: destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = _connectionForExternalAction();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_scaffoldKey.currentState?.isDrawerOpen == true) {
            unawaited(SystemNavigator.pop());
          } else {
            _scaffoldKey.currentState?.openDrawer();
          }
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: AppDrawer(
          selected: _destination,
          connectionLabel: connection?.label,
          hasConnection: connection != null && widget.profileController != null,
          onSelected: _selectDestination,
        ),
        appBar: AppBar(
          title:
              _connections.isEmpty && _destination == AppDestination.connections
              ? null
              : Text(_destination.label),
          actions: [
            if (_destination == AppDestination.connections &&
                _connections.isNotEmpty)
              IconButton(
                key: const Key('home_backup_config_menu'),
                tooltip: 'Backup configuration',
                onPressed: _exportingBackup ? null : _showBackupConfig,
                icon: const Icon(Icons.upload_file),
              ),
            if (_destination == AppDestination.connections &&
                _connections.isNotEmpty)
              IconButton(
                key: const Key('home_restore_config_menu'),
                tooltip: 'Restore configuration',
                onPressed: _exportingBackup ? null : _showRestoreConfig,
                icon: const Icon(Icons.settings_backup_restore),
              ),
          ],
        ),
        body: _destination == AppDestination.settings
            ? AppSettingsContent(
                preferences: widget.connManager.prefs,
                enableNotifications: widget.enableProfileNotifications,
                backgroundPushState: widget.backgroundPushState,
                onChanged: () {
                  setState(() {});
                  widget.onPreferencesChanged?.call();
                },
              )
            : Column(
                children: [
                  if (_opening) const LinearProgressIndicator(),
                  if (widget.shareIntents?.pendingShare.value != null)
                    ListTile(
                      title: const Text('Shared draft ready'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Choose where to add it before sending.'),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed:
                                    _reviewingShare ||
                                        _discardingShare ||
                                        _connections.isEmpty
                                    ? null
                                    : _reviewPendingShare,
                                child: const Text('Review'),
                              ),
                              TextButton(
                                onPressed: _reviewingShare || _discardingShare
                                    ? null
                                    : _discardIncomingShare,
                                child: const Text('Discard'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _connections.isEmpty
                        ? WingWelcome(
                            onConnect: _showAddDialog,
                            onRestore: _showRestoreConfig,
                          )
                        : Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: ListView.builder(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 96,
                                ),
                                itemCount: _connections.length,
                                itemBuilder: (_, i) =>
                                    _buildConnectionCard(_connections[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
        floatingActionButton:
            _destination == AppDestination.connections &&
                _connections.isNotEmpty
            ? FloatingActionButton.extended(
                tooltip: 'Add Connection',
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add connection'),
              )
            : null,
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  final SavedConnection? initialConnection;
  final Future<void> Function(
    String label,
    String host,
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
    Map<String, String?>? gatewayHeaders,
  })
  onSave;
  const _AddDialog({required this.onSave, this.initialConnection});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, String?> _gatewayHeaderEdits;
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _dashboardPrefix;
  late final TextEditingController _dashPort;
  late final TextEditingController _dashUser;
  late final TextEditingController _dashPass;
  late final TextEditingController _desktopGatewayUrl;
  late bool _showDashboard;
  late bool _dashboardProxied;
  bool _validating = false;
  String? _error;

  bool get _isEditing => widget.initialConnection != null;

  @override
  void initState() {
    super.initState();
    final conn = widget.initialConnection;
    _gatewayHeaderEdits = {
      for (final name in conn?.gatewayHeaders.keys ?? const <String>[])
        name: null,
    };
    _label = TextEditingController(text: conn?.label ?? 'Home');
    _host = TextEditingController(
      text: conn == null
          ? ''
          : conn.useHttps
          ? 'https://${conn.host}'
          : conn.host,
    );
    _port = TextEditingController(text: (conn?.port ?? 9119).toString());
    _dashboardPrefix = TextEditingController(text: conn?.dashboardPrefix ?? '');
    _dashPort = TextEditingController(
      text: conn?.dashboardPortOverride?.toString() ?? '',
    );
    _dashUser = TextEditingController(text: conn?.dashboardUsername ?? '');
    _dashPass = TextEditingController(text: conn?.dashboardPassword ?? '');
    // The Desktop Gateway URL is an advanced override, not a default: the
    // app derives the JSON-RPC/WebSocket origin from the dashboard details
    // when this field is blank. Pre-filling a hardcoded example here made
    // every new connection silently point at a dead host and wedge Project
    // loading. See docs/ANDROID_FINAL_UI_SPEC_DRAFT.md.
    _desktopGatewayUrl = TextEditingController(
      text: conn?.desktopGatewayUrl ?? '',
    );
    _dashboardProxied = conn?.dashboardProxied ?? false;
    _showDashboard =
        conn?.gatewayPrefix?.isNotEmpty == true ||
        conn?.dashboardPrefix?.isNotEmpty == true ||
        conn?.dashboardPortOverride != null ||
        conn?.dashboardUsername?.isNotEmpty == true ||
        conn?.dashboardPassword?.isNotEmpty == true ||
        _dashboardProxied ||
        conn?.gatewayHeaders.isNotEmpty == true ||
        conn?.desktopGatewayUrl?.isNotEmpty == true;
  }

  Future<void> _validateAndSave() async {
    if (_validating) return;
    if (!_formKey.currentState!.validate()) {
      setState(() => _showDashboard = true);
      return;
    }
    final label = _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 9119;
    if (label.isEmpty || host.isEmpty || port <= 0 || port > 65535) return;
    setState(() {
      _validating = true;
      _error = null;
    });
    ProfileGateway? probe;
    try {
      final normalized = SavedConnection.normalizeHostAndPort(host, port);
      final dashPort = int.tryParse(_dashPort.text.trim()) ?? normalized.port;
      final uri = Uri.tryParse(host.contains('://') ? host : 'http://$host');
      final prefix = _dashboardPrefix.text.trim().isNotEmpty
          ? _dashboardPrefix.text.trim()
          : uri?.path ?? '';
      final dashUser = _dashUser.text.trim();
      final dashPass = _dashPass.text.trim();
      final gatewayUrl = _desktopGatewayUrl.text.trim();
      final gatewayHeaders = resolveGatewayHeaderUpdate(
        widget.initialConnection?.gatewayHeaders ?? const {},
        _gatewayHeaderEdits,
      );
      final candidate = SavedConnection(
        id: 'connection-probe',
        label: label,
        host: normalized.host,
        port: normalized.port,
        useHttps: normalized.useHttps,
        apiKey: '',
        dashboardPortOverride: dashPort,
        dashboardPrefix: prefix,
        dashboardUsername: dashUser.isEmpty ? null : dashUser,
        dashboardPassword: dashPass.isEmpty ? null : dashPass,
        dashboardProxied: _dashboardProxied,
        desktopGatewayUrl: gatewayUrl.isEmpty ? null : gatewayUrl,
        gatewayHeaders: gatewayHeaders,
      );
      final repository = ProfilesRepository.forConnection(candidate);
      late final ProfilesProbeResult discovery;
      try {
        discovery = await repository.probe();
      } finally {
        repository.close();
      }
      if (discovery.discovery == null) {
        throw StateError(discovery.message ?? 'Profile API unavailable');
      }
      probe = ProfileGateway.forConnection(
        candidate,
        WorkspaceScope(
          connectionId: candidate.id,
          profileName: discovery.discovery!.serverPreferred.name,
        ),
      );
      await probe.connect();
      await probe.sessions();
      if (!mounted) return;
      await widget.onSave(
        label,
        host,
        normalized.port,
        '',
        dashboardPrefix: prefix.isEmpty ? null : prefix,
        dashboardProxied: _dashboardProxied,
        desktopGatewayUrl: gatewayUrl.isEmpty ? null : gatewayUrl,
        dashboardPort: dashPort,
        dashboardUsername: dashUser.isEmpty ? null : dashUser,
        dashboardPassword: dashPass.isEmpty ? null : dashPass,
        gatewayHeaders: _gatewayHeaderEdits,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not connect to Hermes. Check the address, password and proxy settings, then try again.';
          _validating = false;
        });
      }
    } finally {
      probe?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit connection' : 'Add connection'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: WingRadius.card,
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              TextField(
                enabled: !_validating,
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: !_validating,
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText:
                      '192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net',
                ),
                keyboardType: TextInputType.text,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: !_validating,
                controller: _port,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: 'Hermes dashboard port',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: !_validating,
                controller: _dashUser,
                decoration: const InputDecoration(
                  labelText: 'Username (optional)',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                enabled: !_validating,
                controller: _dashPass,
                decoration: const InputDecoration(
                  labelText: 'Password (optional)',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 4),
              InkWell(
                onTap: _validating
                    ? null
                    : () => setState(() => _showDashboard = !_showDashboard),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _showDashboard
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Custom proxy and dashboard details',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_showDashboard) ...[
                const SizedBox(height: 8),
                const SizedBox(height: 12),
                TextField(
                  enabled: !_validating,
                  controller: _dashboardPrefix,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard path prefix',
                    hintText: 'e.g. /dashboard (proxy path before /api/)',
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                CompactSwitchListTile(
                  value: _dashboardProxied,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dashboard behind proxy'),
                  subtitle: const Text('The proxy supplies authentication.'),
                  onChanged: _validating
                      ? null
                      : (v) => setState(() => _dashboardProxied = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Use the gateway address and authentication configured on your Hermes host.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextField(
                  enabled: !_validating,
                  controller: _dashPort,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard Port',
                    hintText: 'Leave blank to use the gateway port',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  enabled: !_validating,
                  controller: _desktopGatewayUrl,
                  decoration: const InputDecoration(
                    labelText: 'Desktop Gateway URL (optional)',
                    hintText: 'https://hermes-desktop.example.lan',
                    helperMaxLines: 4,
                    helperText:
                        'Override the gateway address supplied by the dashboard.',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
              ],
              Visibility(
                visible: _showDashboard,
                maintainState: true,
                child: GatewayHeadersEditor(
                  savedNames:
                      widget.initialConnection?.gatewayHeaders.keys.toSet() ??
                      const {},
                  enabled: !_validating,
                  onChanged: (values) => _gatewayHeaderEdits = values,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _validating ? null : _validateAndSave,
          child: StudioActionLabel(
            _isEditing ? 'Save Changes' : 'Connect',
            busy: _validating,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _dashboardPrefix.dispose();
    _dashPort.dispose();
    _dashUser.dispose();
    _dashPass.dispose();
    _desktopGatewayUrl.dispose();
    super.dispose();
  }
}
