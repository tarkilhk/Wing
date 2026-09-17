import 'dart:async';
import '../../widgets/server_connection_label.dart';
import '../../widgets/profile_selector.dart';
import 'admin_profile_overview.dart';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../services/profile_workspace_controller.dart';
import 'admin_identity_page.dart';
import '../profile_capabilities_screen.dart';
import 'admin_widgets.dart';
import 'admin_settings_page.dart';
import 'admin_memory_page.dart';
import 'admin_providers_page.dart';
import 'admin_health_page.dart';
import 'admin_profiles_page.dart';
import 'admin_defaults_page.dart';
import 'admin_connectors_page.dart';
import 'admin_tool_setup_page.dart';
import 'admin_skills_page.dart';
import 'admin_operations_page.dart';
import 'admin_scheduled_tasks_page.dart';

class HermesAdministrationContent extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final VoidCallback? onConnections;
  final AdministrationRepository? repository;
  final Future<void> Function(ProfileSessionKey) onOpenSession;
  const HermesAdministrationContent({
    super.key,
    required this.controller,
    this.onConnections,
    this.repository,
    required this.onOpenSession,
  });
  @override
  State<HermesAdministrationContent> createState() =>
      _HermesAdministrationContentState();
}

class _HermesAdministrationContentState
    extends State<HermesAdministrationContent>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  late final _server =
      widget.repository ??
      AdministrationRepository.forConnection(
        widget.controller.connection,
        widget.controller.connectionIdentity,
        connectionStatus: widget.controller.connectionStatus,
      );
  String _search = '';
  int _overviewRevision = 0;
  final _searchInput = TextEditingController();
  @override
  void dispose() {
    _tabs.dispose();
    _searchInput.dispose();
    if (widget.repository == null) _server.close();
    super.dispose();
  }

  ProfileAdministration? get _profile {
    final name = widget.controller.current?.scope.profileName;
    if (name == null || widget.controller.discovery?.named(name) == null) {
      return null;
    }
    return _server.profile(name);
  }

  Widget _selector() {
    final profiles = widget.controller.discovery?.profiles ?? [];
    final name = _profile?.name;
    if (profiles.isEmpty) {
      return const AdminNotice(
        'No available profiles. Server controls remain accessible.',
      );
    }
    return ProfileSelector(
      profiles: profiles,
      selectedProfile: name,
      padding: EdgeInsets.zero,
      onSelected: widget.controller.switching
          ? null
          : (choice) async {
              await widget.controller.switchProfile(choice);
              if (mounted) setState(() {});
            },
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
  }) => adminPush(
    context,
    AdminSettingsPage(
      profile: p,
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

  Future<void> _providers() async {
    try {
      final root = await _server.sharedProviders();
      if (mounted) {
        await adminPush(
          context,
          AdminProvidersPage(profile: root, shared: true),
        );
      }
    } catch (e) {
      if (mounted) adminMessage(context, administrationError(e), isError: true);
    }
  }

  List<_Destination> _destinations(ProfileAdministration? p) => [
    _Destination(
      'Profile',
      'Models and reasoning',
      'Model, reasoning, helper models and fallbacks',
      Icons.tune,
      p == null
          ? null
          : () => adminPush(context, AdminDefaultsPage(profile: p)),
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
      p == null ? null : () => adminPush(context, AdminMemoryPage(profile: p)),
    ),
    _Destination(
      'Profile',
      'Skills and tools',
      'Instructions, toolsets and setup',
      Icons.extension_outlined,
      p == null
          ? null
          : () => adminPush(
              context,
              ProfileCapabilitiesScreen(
                gateway: p.gateway,
                connectionLabel: _server.connectionLabel,
                onToolSetup: (name) => adminPush(
                  context,
                  AdminToolSetupPage(profile: p, name: name),
                ),
                onLibrary: () =>
                    adminPush(context, AdminSkillLibraryPage(profile: p)),
                onHub: () => adminPush(context, AdminSkillHubPage(profile: p)),
                onPlugins: () =>
                    adminPush(context, AdminPluginsPage(profile: p)),
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
              return adminPush(
                context,
                AdminScheduledTasksPage(
                  profile: p,
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
      'Shared access, overrides and profile connectors',
      Icons.link,
      p == null
          ? null
          : () => adminPush(
              context,
              _menu('Access and connectors', p.label, [
                AdminRow(
                  title: 'Provider access',
                  subtitle: 'Effective access and explicit profile overrides',
                  icon: Icons.key_outlined,
                  onTap: () => adminPush(
                    context,
                    AdminProvidersPage(profile: p, shared: false),
                  ),
                ),
                AdminRow(
                  title: 'MCP connectors',
                  subtitle: 'Status, tools, authentication and access',
                  icon: Icons.link,
                  onTap: () =>
                      adminPush(context, AdminConnectorsPage(profile: p)),
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
          : () => adminPush(
              context,
              _menu('Behavior', p.label, [
                AdminRow(
                  title: 'Execution',
                  subtitle: 'Agent and subagent limits',
                  icon: Icons.rule,
                  onTap: () => _settings(p, 'Execution', executionFields),
                ),
                AdminRow(
                  title: 'Approval policy',
                  subtitle: 'Approvals and command allowlist',
                  icon: Icons.shield_outlined,
                  onTap: () => _settings(p, 'Approval policy', approvalFields),
                ),
                AdminRow(
                  title: 'Compression',
                  subtitle: 'Context thresholds and protected messages',
                  icon: Icons.compress,
                  onTap: () => _settings(p, 'Compression', compressionFields),
                ),
                AdminRow(
                  title: 'Reach and recovery',
                  subtitle: 'Private URLs, redaction and checkpoints',
                  icon: Icons.restore,
                  onTap: () => _settings(p, 'Reach and recovery', reachFields),
                ),
                AdminRow(
                  title: 'Voice',
                  subtitle: 'Backend speech defaults',
                  icon: Icons.mic_none,
                  onTap: () => adminPush(context, AdminVoicePage(profile: p)),
                ),
              ]),
            ),
    ),
    _Destination(
      'Server',
      'Connection',
      'Saved connection and device-held access details',
      Icons.dns_outlined,
      widget.onConnections,
    ),
    _Destination(
      'Server',
      'Providers',
      'Shared accounts and service credentials',
      Icons.key_outlined,
      _providers,
    ),
    _Destination(
      'Server',
      'Profiles',
      'Create, clone, rename and delete',
      Icons.people_outline,
      () => adminPush(
        context,
        AdminProfilesPage(
          server: _server,
          onOpenProfile: (name) async {
            await widget.controller.switchProfile(name);
            final opened = widget.controller.current?.scope.profileName == name;
            if (mounted && opened) _tabs.animateTo(0);
            return opened;
          },
        ),
      ),
    ),
    _Destination(
      'Server',
      'Runtime',
      'Backend version and eligible updates',
      Icons.memory,
      () => adminPush(context, AdminRuntimePage(server: _server)),
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
          : () => adminPush(context, AdminDefaultsPage(profile: p)),
    ),
    _Destination(
      'Profile',
      'Skill Hub',
      'Install, uninstall and update skills',
      Icons.download_outlined,
      p == null
          ? null
          : () => adminPush(context, AdminSkillHubPage(profile: p)),
    ),
    _Destination(
      'Profile',
      'MCP connectors',
      'Authentication and tool inventory',
      Icons.link,
      p == null
          ? null
          : () => adminPush(context, AdminConnectorsPage(profile: p)),
    ),
    _Destination(
      'Profile',
      'Agent plugins',
      'Plugin inventory and enablement',
      Icons.extension_outlined,
      p == null ? null : () => adminPush(context, AdminPluginsPage(profile: p)),
    ),
    _Destination(
      'Profile health',
      'Usage',
      'Rolling ranges and per-model detail',
      Icons.bar_chart,
      p == null ? null : () => adminPush(context, AdminUsagePage(profile: p)),
    ),
    _Destination(
      'Runtime health',
      'Logs',
      'Errors, severity and search',
      Icons.subject,
      () async {
        final identity = await _server.runtimeIdentity();
        if (mounted) {
          await adminPush(
            context,
            AdminLogsPage(
              server: _server,
              runtimeLabel: identity['label'] as String,
            ),
          );
        }
      },
    ),
  ];

  @override
  Widget build(BuildContext context) => Theme(
    data: administrationTheme(Theme.of(context)),
    child: DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) {
          final p = _profile;
          final destinations = _destinations(p);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ServerConnectionLabel(
                  label: _server.connectionLabel,
                  icon: widget.controller.connection.icon,
                  status: widget.controller.connectionStatus,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
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
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Visibility(
                      visible: _search.isEmpty,
                      maintainState: true,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TabBar(
                              dividerHeight: 0,
                              isScrollable:
                                  MediaQuery.textScalerOf(context).scale(14) >=
                                  21,
                              tabAlignment:
                                  MediaQuery.textScalerOf(context).scale(14) >=
                                      21
                                  ? TabAlignment.start
                                  : TabAlignment.fill,
                              controller: _tabs,
                              tabs: const [
                                Tab(text: 'Profile'),
                                Tab(text: 'Server'),
                                Tab(text: 'Health'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: TabBarView(
                              controller: _tabs,
                              children: <Widget>[
                                if (p != null)
                                  AdminProfileOverview(
                                    key: ValueKey(p.scope.storageNamespace),
                                    profile: p,
                                    revision: _overviewRevision,
                                    metadata: widget.controller.discovery
                                        ?.named(p.name),
                                    preferences: widget.controller.preferences,
                                    selector: _selector(),
                                    destinations: {
                                      for (final d in destinations.where(
                                        (d) => d.tab == 'Profile',
                                      ))
                                        d.title: d.open,
                                    },
                                  )
                                else
                                  ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      _selector(),
                                      const AdminNotice(
                                        'Choose an available profile to manage its settings.',
                                      ),
                                    ],
                                  ),
                                ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    AdminGroup(
                                      children: [
                                        for (final d in destinations.where(
                                          (d) => d.tab == 'Server',
                                        ))
                                          AdminRow(
                                            title: d.title,
                                            subtitle: d.subtitle,
                                            icon: d.icon,
                                            onTap: d.open == null
                                                ? null
                                                : () async {
                                                    await d.open!();
                                                    if (mounted) {
                                                      setState(
                                                        () =>
                                                            _overviewRevision++,
                                                      );
                                                    }
                                                  },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                AdminHealthContent(
                                  server: _server,
                                  profile: p,
                                  profileSelector: _selector(),
                                  workspace: widget.controller.current,
                                  onConnections: widget.onConnections,
                                ),
                              ].map((child) => _AdministrationTab(child: child)).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_search.isNotEmpty)
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (!_searchDestinations(
                            p,
                          ).any((d) => d.matches(_search)))
                            const AdminNotice(
                              'No matching settings. Try a feature name such as memory or providers.',
                            ),
                          for (final d in _searchDestinations(
                            p,
                          ).where((d) => d.matches(_search)))
                            AdminRow(
                              title: d.title,
                              subtitle:
                                  '${d.tab} › ${d.subtitle}\n${d.tab.startsWith('Profile') ? '${_server.connectionLabel} / ${p?.name ?? 'Select a profile'}' : _server.connectionLabel}',
                              icon: d.icon,
                              onTap: d.open == null
                                  ? null
                                  : () async {
                                      await d.open!();
                                      if (mounted) {
                                        setState(() => _overviewRevision++);
                                      }
                                    },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Destination {
  final String tab, title, subtitle;
  final IconData icon;
  final FutureOr<void> Function()? open;
  const _Destination(this.tab, this.title, this.subtitle, this.icon, this.open);
  bool matches(String query) {
    final vocabulary = switch (title) {
      'Providers' ||
      'Access and connectors' => 'API key credentials login sign-in account',
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

/// Keep the originating tab's observations, findings and scroll context while
/// searching or visiting another owner. No background operational checks run.
class _AdministrationTab extends StatefulWidget {
  const _AdministrationTab({required this.child});
  final Widget child;
  @override
  State<_AdministrationTab> createState() => _AdministrationTabState();
}

class _AdministrationTabState extends State<_AdministrationTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
