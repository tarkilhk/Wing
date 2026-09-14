import 'package:flutter/material.dart';

import '../models/profile_live_activity.dart';
import '../services/profile_workspace_controller.dart';
import '../widgets/profile_diagnostics_panel.dart';
import '../widgets/backend_version_card.dart';
import '../widgets/profile_editor_sheet.dart';
import '../widgets/profile_default_model_sheet.dart';
import '../widgets/profile_usage_panel.dart';
import '../widgets/composer_action_settings.dart';
import 'profile_capabilities_screen.dart';

enum _ActivityFilter { all, running, needsInput }

List<ProfileLiveActivity> _filterWorkspaceActivity(
  List<ProfileLiveActivity> activity,
  _ActivityFilter filter,
) => switch (filter) {
  _ActivityFilter.all => activity,
  _ActivityFilter.running =>
    activity
        .where(
          (item) =>
              item.state == ProfileLiveActivityState.running ||
              item.sideTasksRunning > 0,
        )
        .toList(growable: false),
  _ActivityFilter.needsInput =>
    activity
        .where((item) => item.state == ProfileLiveActivityState.needsInput)
        .toList(growable: false),
};

class WorkspaceActivityContent extends StatefulWidget {
  const WorkspaceActivityContent({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final ProfileWorkspaceController controller;
  final ValueChanged<ProfileLiveActivity> onOpen;

  @override
  State<WorkspaceActivityContent> createState() =>
      _WorkspaceActivityContentState();
}

class _WorkspaceActivityContentState extends State<WorkspaceActivityContent> {
  _ActivityFilter _filter = _ActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final activity = _filterWorkspaceActivity(controller.liveActivity, _filter);
    final allActivity = controller.liveActivity;
    final filtered = _filter != _ActivityFilter.all;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text('Sessions running across this Hermes connection.'),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(_ActivityFilter.all, 'All'),
              _filterChip(_ActivityFilter.running, 'Running'),
              _filterChip(_ActivityFilter.needsInput, 'Needs input'),
            ],
          ),
        ),
        if (controller.activityLoading) const LinearProgressIndicator(),
        if (controller.activityLoaded &&
            controller.activityAvailableProfiles == 0 &&
            controller.activityProfileErrors.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('Activity unavailable.'),
          )
        else
          for (final message in controller.activityProfileErrors.values)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(message),
            ),
        if (activity.isEmpty && controller.activityLoaded)
          if (controller.activityAvailableProfiles > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const Icon(Icons.pending_actions_outlined, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    filtered
                        ? (controller.activityProfileErrors.isNotEmpty
                              ? 'No ${_filterLabel(_filter).toLowerCase()} sessions found in available profiles'
                              : allActivity.isEmpty
                              ? 'No ongoing sessions'
                              : _filterEmptyLabel(_filter))
                        : (controller.activityProfileErrors.isEmpty
                              ? 'No ongoing sessions'
                              : 'No ongoing sessions found in available profiles'),
                  ),
                ],
              ),
            ),
        for (final item in activity)
          Card(
            child: ListTile(
              key: ValueKey(
                'activity-${item.workspace.profileName}-${item.sessionId}',
              ),
              leading: Icon(
                item.state == ProfileLiveActivityState.needsInput
                    ? Icons.front_hand_outlined
                    : Icons.chat_bubble_outline,
              ),
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${item.workspace.profileName} · '
                '${item.state == ProfileLiveActivityState.needsInput
                    ? 'Needs input'
                    : item.sideTasksRunning > 0
                    ? item.sideTasksRunning == 1
                          ? 'Background work running'
                          : '${item.sideTasksRunning} background tasks running'
                    : 'Running'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.switching ? null : () => widget.onOpen(item),
            ),
          ),
      ],
    );
  }

  FilterChip _filterChip(_ActivityFilter filter, String label) => FilterChip(
    label: Text(label),
    selected: _filter == filter,
    onSelected: (selected) {
      if (selected) setState(() => _filter = filter);
    },
  );

  String _filterLabel(_ActivityFilter filter) => switch (filter) {
    _ActivityFilter.all => 'All',
    _ActivityFilter.running => 'Running',
    _ActivityFilter.needsInput => 'Needs input',
  };

  String _filterEmptyLabel(_ActivityFilter filter) => switch (filter) {
    _ActivityFilter.all => 'No ongoing sessions',
    _ActivityFilter.running => 'No running sessions',
    _ActivityFilter.needsInput => 'No sessions need input',
  };
}

/// Small administration surface for the selected connection and profile.
class HermesAdministrationContent extends StatelessWidget {
  const HermesAdministrationContent({
    super.key,
    required this.controller,
    this.onConnections,
  });

  final ProfileWorkspaceController controller;
  final VoidCallback? onConnections;

  Future<void> _editDefaultModel(BuildContext context) async {
    final workspace = controller.current;
    if (workspace == null) return;
    final changed = await showProfileDefaultModelSheet(
      context,
      gateway: workspace.gateway,
      connectionLabel: controller.connection.label,
    );
    if (changed &&
        context.mounted &&
        identical(controller.current, workspace)) {
      await controller.refresh();
    }
  }

  Future<void> _editProfile(BuildContext context) async {
    final workspace = controller.current;
    if (workspace == null) return;
    final changed = await showProfileEditorSheet(
      context,
      gateway: workspace.gateway,
      connectionLabel: controller.connection.label,
    );
    if (!changed ||
        !context.mounted ||
        !identical(controller.current, workspace)) {
      return;
    }
    await controller.refresh();
    if (context.mounted && controller.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved changes, but profile information could not be refreshed.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = controller.discovery?.named(
      controller.current?.scope.profileName,
    );
    return _AdministrationTabs(
      connection: ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: Text(controller.connection.label),
        subtitle: Text(
          '${controller.connection.host}:${controller.connection.dashboardPort}',
        ),
      ),
      pages: [
        ListView(
          key: const PageStorageKey('administration-profile'),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  if (profile != null) ...[
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(profile.label),
                      subtitle: Text(profile.description ?? profile.name),
                      trailing: IconButton(
                        tooltip: 'Edit selected profile',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: controller.switching
                            ? null
                            : () => _editProfile(context),
                      ),
                    ),
                    ListTile(
                      title: const Text('Default model'),
                      subtitle: Text(profile.model ?? 'Not configured'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: controller.switching
                          ? null
                          : () => _editDefaultModel(context),
                    ),
                    if (profile.provider != null)
                      ListTile(
                        title: const Text('Default provider'),
                        subtitle: Text(profile.provider!),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            ComposerActionSettings(preferences: controller.preferences),
            if (controller.current != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: const Text('Skills and tools'),
                  subtitle: const Text(
                    'Inspect capabilities and manage what this profile can use',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: controller.switching
                      ? null
                      : () {
                          final gateway = controller.current!.gateway;
                          final label = controller.connection.label;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ProfileCapabilitiesScreen(
                                gateway: gateway,
                                connectionLabel: label,
                              ),
                            ),
                          );
                        },
                ),
              ),
            ],
          ],
        ),
        ListView(
          key: const PageStorageKey('administration-server'),
          padding: const EdgeInsets.all(16),
          children: [
            if (onConnections != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.settings_ethernet),
                  title: const Text('Manage connections'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onConnections,
                ),
              ),
            if (controller.current != null) ...[
              const SizedBox(height: 12),
              BackendVersionCard(
                key: ValueKey(controller.current!.gateway),
                gateway: controller.current!.gateway,
                connectionLabel: controller.connection.label,
              ),
            ],
          ],
        ),
        ListView(
          key: const PageStorageKey('administration-health'),
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.current != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Selected profile · ${profile?.label ?? controller.current!.scope.profileName}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              ProfileUsagePanel(
                key: ValueKey(controller.current!.gateway),
                capturedProfileGateway: controller.current!.gateway,
                connectionLabel: controller.connection.label,
              ),
              if (onConnections != null) ...[
                const SizedBox(height: 12),
                ProfileDiagnosticsPanel(
                  key: ValueKey(controller.current!.scope),
                  workspace: controller.current!,
                  connectionLabel: controller.connection.label,
                  onManageConnections: onConnections!,
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}

/// Keep all existing panels mounted so changing tabs preserves their loaded
/// results, disclosure state and pending operations.
class _AdministrationTabs extends StatefulWidget {
  const _AdministrationTabs({required this.connection, required this.pages});
  final Widget connection;
  final List<Widget> pages;

  @override
  State<_AdministrationTabs> createState() => _AdministrationTabsState();
}

class _AdministrationTabsState extends State<_AdministrationTabs> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        widget.connection,
        TabBar(
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          onTap: (index) => setState(() => _selected = index),
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Server'),
            Tab(text: 'Health'),
          ],
        ),
        Expanded(
          child: IndexedStack(index: _selected, children: widget.pages),
        ),
      ],
    ),
  );
}
