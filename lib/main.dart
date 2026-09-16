import 'core/widgets/server_connection_label.dart';
import 'core/widgets/connection_icon_picker.dart';
import 'core/services/network_availability.dart';
import 'core/screens/connection_setup_screen.dart';
import 'core/widgets/studio_error.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform, kIsWeb;
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
import 'core/services/turn_notification_service.dart';
import 'core/services/background_monitoring_service.dart';
import 'core/services/notification_delivery_ledger.dart';
import 'core/theme/wing_theme.dart';
import 'core/theme/profile_workspace_theme.dart';
import 'core/widgets/app_drawer.dart';
import 'core/widgets/wing_welcome.dart';
import 'core/screens/app_settings_content.dart';
import 'core/widgets/config_backup_card.dart';

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
  static const _notificationPermissionRequestedKey =
      'notification_permission_requested';
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _homeKey = GlobalKey<HomeScreenState>();
  final _notificationRoutes = <ProfileWorkspaceController, Route<void>>{};
  late final ProfileWorkspaceRegistry _profileControllers;
  late final PluginTurnNotificationSink _profileNotifications;
  late final NotificationDeliveryLedger _notificationDeliveries;
  late final Future<void> _notificationsReady;
  late final BackgroundMonitoringService _backgroundMonitoring;
  ProfileSessionKey? _pendingNotificationKey;
  Future<void>? _pendingNotificationOpen;
  int _notificationOpenGeneration = 0;
  String? _deferredShareId;
  bool _disposed = false;
  ProfileWorkspaceController? _openingNotificationController;
  final _networkAvailability = NetworkAvailability();

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
    await _profileNotifications.show(
      const TurnNotification(
        id: 214600,
        title: 'Wing notification test',
        body: 'Local alerts are working on this device.',
        payload: '',
        channel: TurnNotificationService.turnChannel,
      ),
    );
    unawaited(_syncBackgroundMonitoring());
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
      _openingNotificationController?.cancelNotificationOpen();
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
      final previous = _openingNotificationController;
      if (previous != null && previous != controller) {
        previous.cancelNotificationOpen();
        final previousRoute = _notificationRoutes.remove(previous);
        if (previousRoute != null && previousRoute.isActive) {
          _navigatorKey.currentState?.removeRoute(previousRoute);
        }
      }
      _openingNotificationController = controller;
      final opening = controller.openNotification(
        key,
        isCurrent: () => _isCurrentNotificationOpen(generation),
      );
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        throw StateError('Notification navigation is unavailable');
      }
      final existingRoute = _notificationRoutes[controller];
      if (existingRoute != null && existingRoute.isActive) {
        navigator.popUntil((route) => identical(route, existingRoute));
        await opening;
        return;
      }
      final route = MaterialPageRoute<void>(
        builder: (_) => ProfileWorkspaceScreen(
          controller: controller,
          enableNotifications: enableProfileNotifications,
          backgroundMonitoringState: _backgroundMonitoring.state,
          openMonitoringBatterySettings:
              _backgroundMonitoring.openBatterySettings,
          onConnections: openConnections,
          onPreferencesChanged: refreshPreferences,
        ),
      );
      _notificationRoutes[controller] = route;
      unawaited(
        route.popped.then((_) {
          if (identical(_notificationRoutes[controller], route)) {
            _notificationRoutes.remove(controller);
            controller.cancelNotificationOpen();
          }
        }),
      );
      navigator.push(route);
      await opening;
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
    _notificationDeliveries = NotificationDeliveryLedger(
      widget.connManager.prefs,
    );
    _backgroundMonitoring = BackgroundMonitoringService(
      preferences: widget.connManager.prefs,
      hasActiveChats: () => _profileControllers.hasActiveChats,
      notificationsEnabled: _profileNotifications.notificationsEnabled,
    );
    _notificationsReady =
        widget.startupExternalNavigationReady ??
        _profileNotifications.initialize().catchError((Object _) {});
    unawaited(
      WidgetsBinding.instance.endOfFrame.then((_) async {
        await _requestStartupNotificationPermission();
        await _syncBackgroundMonitoring();
      }),
    );
    _profileControllers =
        widget.profileControllers ??
        ProfileWorkspaceRegistry(
          identities: ProfileConnectionIdentity(),
          create: (connection, identity) => ProfileWorkspaceController(
            connection: connection,
            connectionIdentity: identity,
            preferences: widget.connManager.prefs,
            onAttention: (notification) async {
              final eventId = notification.eventId;
              final preference = notification.content.needsAttention
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
              final payload = jsonEncode(notification.key.toJson());
              try {
                await _profileNotifications.show(
                  TurnNotification.chat(
                    payload: payload,
                    title: notification.title,
                    scopeLabel:
                        '${notification.connectionLabel} / ${notification.key.workspace.profileName}',
                    content: notification.content,
                    showPreview:
                        widget.connManager.prefs.getBool(
                          notificationPreviewsKey,
                        ) ??
                        true,
                    eventId: eventId,
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
    _profileControllers.addListener(_monitoringActivityChanged);
    _networkAvailability.start(
      _profileControllers.recoverConnections,
      _profileControllers.networkUnavailable,
    );
  }

  void _monitoringActivityChanged() {
    unawaited(_syncBackgroundMonitoring());
  }

  void refreshPreferences() {
    if (mounted) setState(() {});
    unawaited(_syncBackgroundMonitoring());
  }

  Future<void> _requestStartupNotificationPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final prefs = widget.connManager.prefs;
    if (prefs.getBool(_notificationPermissionRequestedKey) == true) return;
    try {
      await _notificationsReady;
      if (!mounted) return;
      final enabled = await _profileNotifications.notificationsEnabled();
      if (!mounted) return;
      if (enabled != true) {
        await _profileNotifications.requestPermission();
      }
      // Remember both acceptance and denial; further requests are user-driven
      // through App settings. A platform failure remains retryable next launch.
      await prefs.setBool(_notificationPermissionRequestedKey, true);
    } catch (_) {
      // Notification setup must not prevent the app from opening.
    }
  }

  Future<void> _syncBackgroundMonitoring() async {
    if (_disposed) return;
    await _notificationsReady;
    if (!_disposed) await _backgroundMonitoring.sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncBackgroundMonitoring());
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
        onConfigurationChanged: () => unawaited(_syncBackgroundMonitoring()),
        backgroundMonitoringState: _backgroundMonitoring.state,
        openMonitoringBatterySettings:
            _backgroundMonitoring.openBatterySettings,
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
    _networkAvailability.dispose();
    _profileControllers.removeListener(_monitoringActivityChanged);
    _backgroundMonitoring.dispose();
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
  final ValueListenable<BackgroundMonitoringState>? backgroundMonitoringState;
  final Future<void> Function()? openMonitoringBatterySettings;
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
    this.backgroundMonitoringState,
    this.openMonitoringBatterySettings,
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
  bool _settingUpConnection = false;
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
    widget.launchIntents?.pendingAction.addListener(_onLauncherAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onShareError();
      _onLauncherAction();
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
        _settingUpConnection ||
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
                            horizontalTitleGap: 0,
                            leading: _serverIndicator(connection),
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

  void _onLauncherAction() {
    if (!mounted ||
        _settingUpConnection ||
        widget.launchIntents?.pendingAction.value == null) {
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
    widget.launchIntents?.pendingAction.removeListener(_onLauncherAction);
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
        widget.launchIntents?.pendingAction.value != null) {
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
      if (initialChat != null) {
        // Camera already chose its destination when launched from the composer.
        // Save the attachment before acknowledging its native intake copy.
        await controller.stageSharedDraft(initialChat, sharedPayload);
      } else {
        final applied = await reviewSharedDraft(
          context,
          controller,
          sharedPayload,
          recoverableDraft: recoverableDraft,
          destinationNotice: target != null
              ? 'The original chat could not be reopened. Choose a destination below.'
              : null,
        );
        if (!applied) return;
      }
      if (!mounted) return;
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
    final launchAction = sharedPayload == null
        ? widget.launchIntents?.takePendingAction()
        : null;
    final initialQuickChat = launchAction == AndroidLaunchAction.quickChat;
    if (launchAction != null) {
      final departingRoutes = <Future<dynamic>>[];
      setState(() => _opening = true);
      Navigator.of(context).popUntil((route) {
        if (route.isFirst) return true;
        if (route is TransitionRoute) departingRoutes.add(route.completed);
        return false;
      });
      // Let the previous screen release the shared controller before the new
      // screen claims its visibility and search focus.
      await Future.wait(departingRoutes);
      if (!mounted) return;
      setState(() => _opening = false);
    } else if (sharedPayload?.target != null) {
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
          backgroundMonitoringState: widget.backgroundMonitoringState,
          openMonitoringBatterySettings: widget.openMonitoringBatterySettings,
          initialDestination: switch (launchAction) {
            AndroidLaunchAction.activity => AppDestination.activity,
            AndroidLaunchAction.quickChat ||
            AndroidLaunchAction.searchChats => AppDestination.chats,
            null => sharedPayload != null ? AppDestination.chats : destination,
          },
          onConnections: () {
            if (mounted) {
              setState(() => _destination = AppDestination.connections);
            }
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          onPreferencesChanged: widget.onPreferencesChanged,
          initialQuickChat: initialQuickChat,
          initialSearchChats: launchAction == AndroidLaunchAction.searchChats,
        ),
      ),
    );
    _onLauncherAction();
  }

  void _addConnection() => _setupConnection();

  void _editConnection(SavedConnection connection) {
    _setupConnection(existing: connection);
  }

  Future<void> _setupConnection({SavedConnection? existing}) async {
    if (_settingUpConnection) return;
    _settingUpConnection = true;
    final saved = await Navigator.of(context).push<SavedConnection>(
      MaterialPageRoute(
        builder: (_) => ConnectionSetupScreen(
          initialConnection: existing,
          onSaveIcon: existing == null
              ? null
              : (icon) => _saveConnectionIcon(existing, icon),
          onSave: (candidate) async {
            if (existing == null) {
              return widget.connManager.saveConnection(
                candidate.label,
                candidate.baseUrl,
                candidate.port,
                '',
                icon: candidate.icon,
                dashboardPrefix: candidate.dashboardPrefix,
                dashboardProxied: candidate.dashboardProxied,
                desktopGatewayUrl: candidate.desktopGatewayUrl,
                dashboardPort: candidate.dashboardPort,
                dashboardUsername: candidate.dashboardUsername,
                dashboardPassword: candidate.dashboardPassword,
                gatewayHeaders: candidate.gatewayHeaders,
              );
            }
            await widget.connManager.updateConnection(
              existing.id,
              candidate.label,
              candidate.baseUrl,
              candidate.port,
              '',
              icon: candidate.icon,
              gatewayPrefix: '',
              dashboardPrefix: candidate.dashboardPrefix ?? '',
              dashboardProxied: candidate.dashboardProxied,
              desktopGatewayUrl: candidate.desktopGatewayUrl ?? '',
              dashboardPort: candidate.dashboardPort,
              dashboardUsername: candidate.dashboardUsername ?? '',
              dashboardPassword: candidate.dashboardPassword ?? '',
              gatewayHeaders: candidate.gatewayHeaders,
            );
            return widget.connManager.getConnections().firstWhere(
              (c) => c.id == existing.id,
            );
          },
        ),
      ),
    );
    _settingUpConnection = false;
    if (!mounted) return;
    if (saved != null) {
      _autoNavigated = true;
      _refresh();
      if (existing == null && widget.profileController != null) {
        await _navigateToWorkspace(saved);
      }
    }
    _onSharedText();
    _onLauncherAction();
  }

  final _connectionOwners =
      <SavedConnection, Future<ProfileWorkspaceController>>{};

  Future<void> _saveConnectionIcon(
    SavedConnection connection,
    ConnectionIcon icon,
  ) async {
    await widget.connManager.updateConnectionIcon(connection.id, icon);
    if (mounted) _refresh();
  }

  Future<void> _pickConnectionIcon(SavedConnection connection) =>
      showConnectionIconPicker(
        context,
        connectionName: connection.label,
        initialIcon: connection.icon,
        onSave: (icon) => _saveConnectionIcon(connection, icon),
      );

  Widget _serverIndicator(SavedConnection connection) =>
      FutureBuilder<ProfileWorkspaceController>(
        key: ValueKey(connection),
        future: widget.profileController == null
            ? null
            : _connectionOwners.putIfAbsent(
                connection,
                () async => await widget.profileController!(connection),
              ),
        builder: (context, snapshot) => ServerConnectionIndicator(
          label: connection.label,
          icon: connection.icon,
          onIconPressed: () => _pickConnectionIcon(connection),
          status: snapshot.data?.connectionStatus,
        ),
      );

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        horizontalTitleGap: 0,
        leading: _serverIndicator(conn),
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
              _editConnection(conn);
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
        drawer: FutureBuilder<ProfileWorkspaceController>(
          key: ValueKey(connection),
          future: connection == null || widget.profileController == null
              ? null
              : _connectionOwners.putIfAbsent(
                  connection,
                  () async => await widget.profileController!(connection),
                ),
          builder: (context, snapshot) => AppDrawer(
            selected: _destination,
            connectionLabel: connection?.label,
            connectionStatus: snapshot.data?.connectionStatus,
            hasConnection:
                connection != null && widget.profileController != null,
            onSelected: _selectDestination,
          ),
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
                backgroundMonitoringState: widget.backgroundMonitoringState,
                openMonitoringBatterySettings:
                    widget.openMonitoringBatterySettings,
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
                            onConnect: _addConnection,
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
                onPressed: _addConnection,
                icon: const Icon(Icons.add),
                label: const Text('Add connection'),
              )
            : null,
      ),
    );
  }
}
