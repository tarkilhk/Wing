import '../../widgets/studio_select.dart';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../services/profile_workspace_controller.dart';
import '../../widgets/profile_editor_sheet.dart';
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

class HermesAdministrationContent extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final VoidCallback? onConnections;
  final AdministrationRepository? repository;
  const HermesAdministrationContent({
    super.key,
    required this.controller,
    this.onConnections,
    this.repository,
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
      );
  String _search = '';
  @override
  void dispose() {
    _tabs.dispose();
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: StudioSelect<String>(
        key: ValueKey(name),
        value: name,
        label: 'Profile',
        options: [for (final p in profiles) (value: p.name, label: p.label)],
        onChanged: widget.controller.switching
            ? null
            : (value) {
                if (value != null) widget.controller.switchProfile(value);
              },
      ),
    );
  }

  Future<void> _identity(ProfileAdministration profile) async {
    final workspace = widget.controller.current;
    final changed = await showProfileEditorSheet(
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

  void _settings(
    ProfileAdministration p,
    String title,
    List<AdminField> fields,
  ) => adminPush(
    context,
    AdminSettingsPage(profile: p, title: title, fields: fields),
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
      'Defaults',
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
              _menu('Skills and tools', p.label, [
                AdminRow(
                  title: 'Enabled capabilities',
                  subtitle: 'Skills, toolsets and individual switches',
                  icon: Icons.toggle_on_outlined,
                  onTap: () => adminPush(
                    context,
                    ProfileCapabilitiesScreen(
                      gateway: p.gateway,
                      connectionLabel: _server.connectionLabel,
                    ),
                  ),
                ),
                AdminRow(
                  title: 'Skill library',
                  subtitle: 'Usage, instructions and local corrections',
                  icon: Icons.menu_book_outlined,
                  onTap: () =>
                      adminPush(context, AdminSkillLibraryPage(profile: p)),
                ),
                AdminRow(
                  title: 'Skill Hub',
                  subtitle: 'Preview, install and update skills',
                  icon: Icons.download_outlined,
                  onTap: () =>
                      adminPush(context, AdminSkillHubPage(profile: p)),
                ),
                AdminRow(
                  title: 'Tool setup',
                  subtitle: 'Providers, keys, models and requirements',
                  icon: Icons.build_outlined,
                  onTap: () =>
                      adminPush(context, AdminToolSetupList(profile: p)),
                ),
                AdminRow(
                  title: 'Agent plugins',
                  subtitle: 'Inventory and individual enablement',
                  icon: Icons.extension_outlined,
                  onTap: () => adminPush(context, AdminPluginsPage(profile: p)),
                ),
              ]),
            ),
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
          p == null ? null : () => _settings(p, group.key, group.value),
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
                child: Text(_server.connectionLabel),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search settings',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              if (_search.isNotEmpty)
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!_searchDestinations(p).any(
                        (d) => '${d.title} ${d.subtitle}'
                            .toLowerCase()
                            .contains(_search.toLowerCase()),
                      ))
                        const AdminNotice(
                          'No matching settings. Try a feature name such as memory or providers.',
                        ),
                      for (final d in _searchDestinations(p).where(
                        (d) => '${d.title} ${d.subtitle}'
                            .toLowerCase()
                            .contains(_search.toLowerCase()),
                      ))
                        AdminRow(
                          title: d.title,
                          subtitle:
                              '${d.tab} · ${d.tab.startsWith('Profile') ? '${_server.connectionLabel} / ${p?.name ?? 'Select a profile'}' : _server.connectionLabel}',
                          icon: d.icon,
                          onTap: d.open,
                        ),
                    ],
                  ),
                )
              else ...[
                TabBar(
                  controller: _tabs,
                  tabs: const [
                    Tab(text: 'Profile'),
                    Tab(text: 'Server'),
                    Tab(text: 'Health'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _selector(),
                          if (p == null)
                            const AdminNotice(
                              'Choose an available profile to manage its settings.',
                            ),
                          AdminGroup(
                            children: [
                              for (final d in destinations.where(
                                (d) => d.tab == 'Profile',
                              ))
                                AdminRow(
                                  title: d.title,
                                  subtitle: d.subtitle,
                                  icon: d.icon,
                                  onTap: d.open,
                                ),
                            ],
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
                                  onTap: d.open,
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
                    ],
                  ),
                ),
              ],
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
  final VoidCallback? open;
  const _Destination(this.tab, this.title, this.subtitle, this.icon, this.open);
}
