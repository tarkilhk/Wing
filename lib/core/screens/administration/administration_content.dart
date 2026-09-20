import 'dart:async';
import '../analytics_content.dart';
import '../../services/administration_overview.dart';
import '../../services/administration_health.dart';
import '../../widgets/profile_diagnostics_panel.dart';
import '../../widgets/workspace_connection_status.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/server_connection_label.dart';
import '../../widgets/profile_selector.dart';
import '../../theme/wing_theme.dart';
import 'admin_profile_overview.dart';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../services/profile_workspace_controller.dart';
import 'admin_identity_page.dart';
import 'admin_profiles_page.dart';
import '../profile_capabilities_screen.dart';
import 'admin_widgets.dart';
import 'admin_settings_page.dart';
import 'admin_memory_page.dart';
import 'admin_providers_page.dart';
import 'admin_health_page.dart';
import 'admin_runtime_health.dart';
import 'admin_defaults_page.dart';
import 'admin_connectors_page.dart';
import 'admin_tool_setup_page.dart';
import 'admin_skills_page.dart';
import 'admin_operations_page.dart';
import 'admin_scheduled_tasks_page.dart';

class HermesAdministrationContent extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final VoidCallback onOpenMenu;
  final VoidCallback? onConnections;
  final AdministrationRepository? repository;
  final Future<void> Function(ProfileSessionKey) onOpenSession;
  final bool healthOnly;
  const HermesAdministrationContent({
    super.key,
    required this.controller,
    required this.onOpenMenu,
    this.onConnections,
    this.repository,
    required this.onOpenSession,
    this.healthOnly = false,
  });
  @override
  State<HermesAdministrationContent> createState() =>
      _HermesAdministrationContentState();
}

class _HermesAdministrationContentState
    extends State<HermesAdministrationContent> {
  late final _healthSession = widget.controller.healthSession(
    repository: widget.repository,
  );
  late final _server = widget.healthOnly
      ? _healthSession.server
      : widget.repository ??
            AdministrationRepository.forConnection(
              widget.controller.connection,
              widget.controller.connectionIdentity,
              connectionStatus: widget.controller.connectionStatus,
            );
  String _search = '';
  int _overviewRevision = 0;
  Set<String> _overviewKeys = const {};

  void _refreshAfter(_Destination destination) {
    if (widget.healthOnly) {
      unawaited(_refreshHealthProfile());
      return;
    }
    unawaited(_health.refreshReadiness());
    setState(() {
      _overviewKeys = destination.summaryKeys;
      _overviewRevision++;
    });
  }

  late final _health = widget.healthOnly
      ? _healthSession.health
      : AdministrationHealth(
          _server,
          connectionStatus: widget.controller.connectionStatus,
        );
  String? _healthProfileName;
  bool _refreshing = false;
  bool get _checkingProfile => _healthSession.checking(_profile?.name);

  void _selectHealthProfile() {
    if (!widget.healthOnly) return;
    _healthSession.select(_profile == null ? null : widget.controller.current);
  }

  Future<void> _refreshHealthProfile() {
    final workspace = widget.controller.current;
    return workspace == null
        ? Future.value()
        : _healthSession.refresh(workspace);
  }

  Future<void> _checkProfile() => _refreshHealthProfile();

  final _accessChecks = <String, ProfileDiagnosticsController>{};

  @override
  void initState() {
    super.initState();
    _healthProfileName = _profile?.name;
    widget.controller.addListener(_workspaceChanged);
    _selectHealthProfile();
    if (widget.healthOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(refreshHealthDiagnostics(context, _health));
      });
    }
  }

  void _workspaceChanged() {
    if (!mounted) return;
    final name = _profile?.name;
    if (name != _healthProfileName) {
      _healthProfileName = name;
      _health.selectProfile(null);
      _selectHealthProfile();
    }
    _checksForCurrentProfile();
    setState(() {});
  }

  ProfileDiagnosticsController? _checksForCurrentProfile() {
    final workspace = widget.controller.current;
    if (workspace == null || workspace.scope != _profile?.scope) return null;
    if (widget.healthOnly) return _healthSession.checksFor(workspace);
    final checks = _accessChecks.putIfAbsent(
      workspace.scope.storageNamespace,
      () {
        final checks = ProfileDiagnosticsController(
          workspace: workspace,
          connectionLabel: _server.connectionLabel,
        );
        checks.addListener(() {
          if (mounted) _health.updateProfileChecks(checks.healthObservation);
        });
        return checks;
      },
    );
    checks.updateWorkspace(
      workspace: workspace,
      connectionLabel: _server.connectionLabel,
    );
    return checks;
  }

  void _observeOverview(AdministrationOverview overview) {
    if (!mounted || overview.profile.scope != _profile?.scope) return;
    final changed = !identical(_health.overview, overview);
    _health.selectProfile(overview);
    if (changed) {
      final checks = _checksForCurrentProfile();
      if (checks != null) _health.updateProfileChecks(checks.healthObservation);
      unawaited(_health.refreshReadiness());
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _overviewKeys = {...AdministrationOverview.endpoints.keys, 'tasks'};
      _overviewRevision++;
    });
    try {
      await Future.wait([
        widget.controller.refresh(),
        if (widget.healthOnly)
          _refreshHealthProfile()
        else
          _health.refreshReadiness(),
      ]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(administrationError(error))));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  final _searchInput = TextEditingController();
  @override
  void dispose() {
    widget.controller.removeListener(_workspaceChanged);
    if (!widget.healthOnly) _health.dispose();
    for (final checks in _accessChecks.values) {
      checks.dispose();
    }
    _searchInput.dispose();
    if (!widget.healthOnly && widget.repository == null) {
      final server = _server;
      scheduleMicrotask(server.close);
    }
    super.dispose();
  }

  ProfileAdministration? get _profile {
    final name = widget.controller.current?.scope.profileName;
    if (name == null || widget.controller.discovery?.named(name) == null) {
      return null;
    }
    return _server.profile(name);
  }

  Future<void> _manageProfiles() async {
    await adminPush(
      context,
      (context) => AdminProfilesPage(
        server: _server,
        onOpenProfile: (name) async {
          await widget.controller.switchProfile(name);
          final opened = widget.controller.current?.scope.profileName == name;
          return opened;
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _selector({bool manage = false}) {
    final profiles = widget.controller.discovery?.profiles ?? [];
    final name = _profile?.name;
    final colors = Theme.of(context).colorScheme;
    final manageAction = manage
        ? Tooltip(
            message: 'Manage profiles',
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: colors.onSurfaceVariant,
                backgroundColor: colors.surfaceContainerLow,
                side: BorderSide(color: colors.outlineVariant),
                shape: RoundedRectangleBorder(borderRadius: WingRadius.control),
              ),
              onPressed: _manageProfiles,
              child: const Icon(Icons.manage_accounts_outlined),
            ),
          )
        : null;
    final selector = profiles.isEmpty
        ? const AdminNotice(
            'No available profiles. Runtime health remains accessible.',
          )
        : ProfileSelector(
            profiles: profiles,
            selectedProfile: name,
            padding: EdgeInsets.zero,
            trailing: manageAction,
            onSelected: widget.controller.switching
                ? null
                : (choice) async {
                    await widget.controller.switchProfile(choice);
                    if (mounted) setState(() {});
                  },
          );
    if (!manage || profiles.isNotEmpty) return selector;
    return Row(
      children: [
        Expanded(child: selector),
        manageAction!,
      ],
    );
  }

  Future<void> _identity(ProfileAdministration profile) async {
    final workspace = widget.controller.current;
    final changed = await showAdminIdentityEditor(
      context,
      gateway: workspace?.scope == profile.scope
          ? workspace!.gateway
          : profile.gateway,
      connectionLabel: _server.connectionLabel,
    );
    if (changed && mounted && _profile?.name == profile.name) {
      await widget.controller.refresh();
    }
  }

  Future<void> _settings(
    ProfileAdministration p,
    String title,
    List<AdminField> fields, {
    String? initialField,
  }) => adminPushProfile(
    context,
    p,
    (context, profile) => AdminSettingsPage(
      profile: profile,
      title: title,
      fields: fields,
      initialField: initialField,
    ),
  );

  Widget _menu(String title, String scope, List<Widget> rows) => AdminPage(
    title: title,
    scope: scope,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [AdminGroup(children: rows)],
    ),
  );

  List<_Destination> _destinations(ProfileAdministration? p) => [
    _Destination(
      'Profile',
      'Models and reasoning',
      'Model, reasoning, helper models and fallbacks',
      Icons.tune,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => AdminDefaultsPage(profile: profile),
            ),
    ),
    _Destination(
      'Profile',
      'Identity',
      'Description and SOUL',
      Icons.person_outline,
      p == null ? null : () => _identity(p),
    ),
    _Destination(
      'Profile',
      'Memory',
      'Retained memories and character budgets',
      Icons.bookmark_border,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => AdminMemoryPage(profile: profile),
            ),
    ),
    _Destination(
      'Profile',
      'Skills and tools',
      'Instructions, toolsets and setup',
      Icons.extension_outlined,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => ProfileCapabilitiesScreen(
                gateway: profile.gateway,
                connectionLabel: _server.connectionLabel,
                onToolSetup: (name) => adminPushProfile(
                  context,
                  profile,
                  (context, profile) =>
                      AdminToolSetupPage(profile: profile, name: name),
                ),
                onLibrary: () => adminPushProfile(
                  context,
                  profile,
                  (context, profile) => AdminSkillLibraryPage(profile: profile),
                ),
                onHub: () => adminPushProfile(
                  context,
                  profile,
                  (context, profile) => AdminSkillHubPage(profile: profile),
                ),
                onPlugins: () => adminPushProfile(
                  context,
                  profile,
                  (context, profile) => AdminPluginsPage(profile: profile),
                ),
              ),
            ),
    ),
    _Destination(
      'Profile',
      'Scheduled tasks',
      'Schedules, runs and results',
      Icons.event_repeat_outlined,
      p == null
          ? null
          : () {
              final root = ModalRoute.of(context);
              final navigator = Navigator.of(context);
              return adminPushProfile(
                context,
                p,
                (context, profile) => AdminScheduledTasksPage(
                  profile: profile,
                  preferences: widget.controller.preferences,
                  onOpenSession: (key) async {
                    await widget.onOpenSession(key);
                    if (navigator.mounted) {
                      navigator.popUntil((route) => route == root);
                    }
                  },
                ),
              );
            },
    ),
    _Destination(
      'Profile',
      'Access and connectors',
      'Provider accounts, API keys and profile connectors',
      Icons.link,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) =>
                  _menu('Access and connectors', profile.label, [
                    AdminRow(
                      title: 'Provider access',
                      subtitle: 'Accounts and API keys for this profile',
                      icon: Icons.key_outlined,
                      onTap: () => adminPushProfile(
                        context,
                        profile,
                        (context, profile) =>
                            AdminProvidersPage(profile: profile),
                      ),
                    ),
                    AdminRow(
                      title: 'MCP connectors',
                      subtitle: 'Status, tools, authentication and access',
                      icon: Icons.link,
                      onTap: () => adminPushProfile(
                        context,
                        profile,
                        (context, profile) =>
                            AdminConnectorsPage(profile: profile),
                      ),
                    ),
                  ]),
            ),
    ),
    _Destination(
      'Profile',
      'Behavior',
      'Execution, approval policy, compression and voice',
      Icons.settings_outlined,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => _menu('Behavior', profile.label, [
                AdminRow(
                  title: 'Execution',
                  subtitle: 'Agent and subagent limits',
                  icon: Icons.rule,
                  onTap: () => _settings(profile, 'Execution', executionFields),
                ),
                AdminRow(
                  title: 'Approval policy',
                  subtitle: 'Approvals and command allowlist',
                  icon: Icons.shield_outlined,
                  onTap: () =>
                      _settings(profile, 'Approval policy', approvalFields),
                ),
                AdminRow(
                  title: 'Compression',
                  subtitle: 'Context thresholds and protected messages',
                  icon: Icons.compress,
                  onTap: () =>
                      _settings(profile, 'Compression', compressionFields),
                ),
                AdminRow(
                  title: 'Reach and recovery',
                  subtitle: 'Private URLs, redaction and checkpoints',
                  icon: Icons.restore,
                  onTap: () =>
                      _settings(profile, 'Reach and recovery', reachFields),
                ),
                AdminRow(
                  title: 'Voice',
                  subtitle: 'Backend speech defaults',
                  icon: Icons.mic_none,
                  onTap: () => adminPushProfile(
                    context,
                    profile,
                    (context, profile) => AdminVoicePage(profile: profile),
                  ),
                ),
              ]),
            ),
    ),
  ];

  List<_Destination> _searchDestinations(ProfileAdministration? p) => [
    ..._destinations(p),
    for (final group in <String, List<AdminField>>{
      'Memory settings': memoryFields,
      'Execution': executionFields,
      'Approval policy': approvalFields,
      'Compression': compressionFields,
      'Reach and recovery': reachFields,
    }.entries)
      for (final field in group.value)
        _Destination(
          'Profile',
          field.label,
          group.key,
          Icons.tune,
          p == null
              ? null
              : () => _settings(
                  p,
                  group.key,
                  group.value,
                  initialField: field.key,
                ),
        ),
    _Destination(
      'Profile',
      'Helper models',
      'Auxiliary assignments and reset',
      Icons.auto_awesome_outlined,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => AdminDefaultsPage(profile: profile),
            ),
    ),
    _Destination(
      'Profile',
      'Skill Hub',
      'Install, uninstall and update skills',
      Icons.download_outlined,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => AdminSkillHubPage(profile: profile),
            ),
    ),
    _Destination(
      'Profile',
      'MCP connectors',
      'Authentication and tool inventory',
      Icons.link,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => AdminConnectorsPage(profile: profile),
            ),
    ),
    _Destination(
      'Profile',
      'Agent plugins',
      'Plugin inventory and enablement',
      Icons.extension_outlined,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => AdminPluginsPage(profile: profile),
            ),
    ),
    _Destination(
      'Analytics',
      'Analytics',
      'Usage, tokens and cost by day and model',
      Icons.bar_chart,
      p == null
          ? null
          : () => adminPushProfile(
              context,
              p,
              (context, profile) => AnalyticsPage(profile: profile),
            ),
    ),
    _Destination(
      'Runtime health',
      'Logs',
      'Errors, severity and search',
      Icons.subject,
      () => adminPush(context, (context) => AdminLogsPage(server: _server)),
    ),
  ];

  Widget _searchField() => TextField(
    controller: _searchInput,
    decoration: InputDecoration(
      hintText: MediaQuery.textScalerOf(context).scale(16) >= 24
          ? 'Search'
          : 'Search settings',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: _search.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchInput.clear();
                setState(() => _search = '');
                FocusScope.of(context).unfocus();
              },
            ),
    ),
    onChanged: (value) => setState(() => _search = value),
  );

  Widget? _searchResults(ProfileAdministration? profile) {
    if (_search.isEmpty) return null;
    final matches = _searchDestinations(
      profile,
    ).where((d) => d.matches(_search)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matches.isEmpty)
          const AdminNotice(
            'No matching settings. Try a feature name such as memory or providers.',
          ),
        for (final destination in matches)
          AdminRow(
            title: destination.title,
            subtitle:
                '${destination.path}\n${destination.tab.startsWith('Profile') ? '${_server.connectionLabel} / ${profile?.name ?? 'Select a profile'}' : _server.connectionLabel}',
            icon: destination.icon,
            onTap: destination.open == null
                ? null
                : () async {
                    await destination.open!();
                    if (mounted) _refreshAfter(destination);
                  },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.healthOnly) {
      return ListenableBuilder(
        listenable: Listenable.merge([
          widget.controller,
          _health,
          _healthSession,
        ]),
        builder: (context, _) => AdminHealthContent(
          server: _server,
          health: _health,
          persistenceError: _healthSession.persistenceError,
          profile: _profile,
          chatController: widget.controller,
          onOpenSession: (key) async {
            final root = ModalRoute.of(context);
            final navigator = Navigator.of(context);
            await widget.onOpenSession(key);
            if (navigator.mounted) {
              navigator.popUntil((route) => route == root);
            }
          },
          onCheckProfile: _checkingProfile || widget.controller.switching
              ? null
              : _checkProfile,
          checkingProfile: _checkingProfile,
          profileCheckedAt: _healthSession.checkedAt(_profile?.name),
          accessChecks: _checksForCurrentProfile,
          onConnections: widget.onConnections,
          onRefresh: _refresh,
          onOpenDestination: (title) async {
            final destination = _destinations(
              _profile,
            ).where((d) => d.title == title).firstOrNull;
            if (destination?.open != null) {
              await destination!.open!();
              if (mounted) _refreshAfter(destination);
            }
          },
        ),
      );
    }
    final profile = _profile;
    final large =
        MediaQuery.textScalerOf(context).scale(16) >= 24 ||
        adminToolbarHeight(context, 'Administration', actions: 1) >
            kToolbarHeight;
    final title = large
        ? const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Administration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          )
        : null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Open navigation menu',
          icon: const Icon(Icons.menu),
          onPressed: widget.onOpenMenu,
        ),
        title: large ? null : const Text('Administration'),
        actions: [
          IconButton(
            tooltip: 'Refresh administration',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshing || widget.controller.switching
                ? null
                : _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.controller.switching) const LinearProgressIndicator(),
          WorkspaceConnectionStatus(status: widget.controller.connectionStatus),
          if (widget.controller.error != null)
            ListTile(
              title: StudioError(widget.controller.error!),
              trailing: TextButton(
                onPressed: widget.controller.retry,
                child: const Text('Retry'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ServerConnectionLabel(
                  label: _server.connectionLabel,
                  suffix: profile?.name,
                  style: Theme.of(context).textTheme.bodySmall,
                  icon: widget.controller.connection.icon,
                  status: widget.controller.connectionStatus,
                ),
              ),
            ),
          ),
          Expanded(
            child: profile == null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ?title,
                      _selector(manage: true),
                      const SizedBox(height: 12),
                      _searchField(),
                      ?_searchResults(profile),
                      if (_search.isEmpty)
                        const AdminNotice(
                          'Choose an available profile to manage its settings. Health remains accessible.',
                        ),
                    ],
                  )
                : AdminProfileOverview(
                    key: ValueKey(profile.scope.storageNamespace),
                    profile: profile,
                    revision: _overviewRevision,
                    refreshKeys: _overviewKeys,
                    metadata: widget.controller.discovery?.named(profile.name),
                    preferences: widget.controller.preferences,
                    selector: _selector(manage: true),
                    search: _searchField(),
                    searchResults: _searchResults(profile),
                    titleBeforeSelector: title,
                    onOverviewChanged: _observeOverview,
                    onRefreshCompleted: _health.refreshReadiness,
                    onTasksChanged: _health.updateTasks,
                    destinations: {
                      for (final d in _destinations(profile)) d.title: d.open,
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The dedicated Health destination keeps the same retained observations and
/// profile-scoped actions as Administration without nesting Health there.
class HermesHealthContent extends HermesAdministrationContent {
  const HermesHealthContent({
    super.key,
    required super.controller,
    required super.onOpenMenu,
    super.onConnections,
    super.repository,
    required super.onOpenSession,
  }) : super(healthOnly: true);
}

class _Destination {
  final String tab, title, subtitle;
  final IconData icon;
  final FutureOr<void> Function()? open;
  const _Destination(this.tab, this.title, this.subtitle, this.icon, this.open);
  Set<String> get summaryKeys {
    if (const {
      'Memory settings',
      'Execution',
      'Approval policy',
      'Compression',
      'Reach and recovery',
    }.contains(subtitle)) {
      return {'config'};
    }
    return switch (title) {
      'Models and reasoning' ||
      'Helper models' => {'model', 'config', 'access'},
      'Memory' || 'Behavior' => {'config'},
      'Skills and tools' => {'skills', 'tools', 'access'},
      'Skill Hub' => {'skills'},
      'Access and connectors' => {'access', 'connectors'},
      'MCP connectors' => {'connectors'},
      'Scheduled tasks' => {'tasks'},
      _ => {},
    };
  }

  String get path {
    if (tab == 'Profile') {
      if (const {
        'Execution',
        'Approval policy',
        'Compression',
        'Reach and recovery',
      }.contains(subtitle)) {
        return 'Profile › Behavior › $subtitle';
      }
      if (subtitle == 'Memory settings') {
        return 'Profile › Memory › Memory settings';
      }
      return switch (title) {
        'Helper models' => 'Profile › Models and reasoning › Helper models',
        'Skill Hub' => 'Profile › Skills and tools › Discover skills',
        'Agent plugins' => 'Profile › Skills and tools › Agent plugins',
        'MCP connectors' => 'Profile › Access and connectors › MCP connectors',
        _ => 'Profile › $title',
      };
    }
    if (tab == 'Analytics') return 'Hermes analytics › Selected profile';
    if (tab == 'Runtime health') return 'Health › Runtime › $title';
    return '$tab › $title';
  }

  bool matches(String query) {
    final vocabulary = switch (title) {
      'Access and connectors' =>
        'providers API key credentials login sign-in account',
      'Behavior' => 'timeout voice approvals compression limits',
      'Models and reasoning' => 'models intelligence reasoning speed',
      'Run time budget' || 'Subagent timeout' => 'timeout duration seconds',
      'Skill Hub' => 'install discover skills',
      _ => '',
    };
    return '$title $subtitle $vocabulary'.toLowerCase().contains(
      query.trim().toLowerCase(),
    );
  }
}
