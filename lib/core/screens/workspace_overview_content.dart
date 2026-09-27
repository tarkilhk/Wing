import 'dart:async';
import '../widgets/studio_error.dart';
import 'package:flutter/material.dart';

import '../models/profile_live_activity.dart';
import '../services/profile_workspace_controller.dart';
export 'administration/administration_content.dart';

enum WorkspaceActivityFilter { all, running, needsInput }

List<ProfileRecentChat> _filterWorkspaceActivity(
  List<ProfileRecentChat> activity,
  WorkspaceActivityFilter filter,
) => switch (filter) {
  WorkspaceActivityFilter.all => activity,
  WorkspaceActivityFilter.running =>
    activity
        .where(
          (item) =>
              item.state == ProfileLiveActivityState.running ||
              item.sideTasksRunning > 0,
        )
        .toList(growable: false),
  WorkspaceActivityFilter.needsInput =>
    activity
        .where((item) => item.state == ProfileLiveActivityState.needsInput)
        .toList(growable: false),
};

class WorkspaceActivityContent extends StatefulWidget {
  const WorkspaceActivityContent({
    super.key,
    required this.controller,
    required this.onOpen,
    this.filter = WorkspaceActivityFilter.all,
    this.onFilterChanged,
  });

  final ProfileWorkspaceController controller;
  final WorkspaceActivityFilter filter;
  final ValueChanged<WorkspaceActivityFilter>? onFilterChanged;
  final ValueChanged<ProfileRecentChat> onOpen;

  @override
  State<WorkspaceActivityContent> createState() =>
      _WorkspaceActivityContentState();
}

class _WorkspaceActivityContentState extends State<WorkspaceActivityContent> {
  late WorkspaceActivityFilter _filter = widget.filter;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _expiryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final allActivity = controller.recentChats();
    final activity = _filterWorkspaceActivity(allActivity, _filter);
    final filtered = _filter != WorkspaceActivityFilter.all;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text('Chats from the last 24 hours and ongoing work.'),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(WorkspaceActivityFilter.all, 'All'),
              _filterChip(WorkspaceActivityFilter.running, 'Running'),
              _filterChip(WorkspaceActivityFilter.needsInput, 'Needs input'),
            ],
          ),
        ),
        if (controller.recentsLoading) const LinearProgressIndicator(),
        if (controller.recentsLoaded &&
            allActivity.isEmpty &&
            controller.recentsAvailableProfiles == 0 &&
            controller.recentsProfileErrors.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: StudioError('Recents unavailable.'),
          )
        else
          for (final message in controller.recentsProfileErrors.values)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StudioError(message),
            ),
        if (activity.isEmpty && controller.recentsLoaded)
          if (controller.recentsAvailableProfiles > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const Icon(Icons.pending_actions_outlined, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    filtered
                        ? (controller.recentsProfileErrors.isNotEmpty
                              ? 'No ${_filterLabel(_filter).toLowerCase()} sessions found in available profiles'
                              : allActivity.isEmpty
                              ? 'No recent chats'
                              : _filterEmptyLabel(_filter))
                        : (controller.recentsProfileErrors.isEmpty
                              ? 'No recent chats'
                              : 'No recent chats found in available profiles'),
                  ),
                ],
              ),
            ),
        for (final item in activity)
          Card(
            child: ListTile(
              key: ValueKey(
                'activity-${item.key.workspace.profileName}-${item.key.sessionId}',
              ),
              leading: Icon(
                item.state == ProfileLiveActivityState.needsInput
                    ? Icons.front_hand_outlined
                    : Icons.chat_bubble_outline,
              ),
              title: Text(
                item.title,
                maxLines: MediaQuery.textScalerOf(context).scale(16) > 24
                    ? null
                    : 2,
                overflow: MediaQuery.textScalerOf(context).scale(16) > 24
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${item.key.workspace.profileName} · '
                '${item.state == ProfileLiveActivityState.needsInput
                    ? 'Needs input'
                    : item.sideTasksRunning > 0
                    ? item.sideTasksRunning == 1
                          ? 'Background work running'
                          : '${item.sideTasksRunning} background tasks running'
                    : item.state == ProfileLiveActivityState.running
                    ? 'Running'
                    : 'Recent'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.switching ? null : () => widget.onOpen(item),
            ),
          ),
      ],
    );
  }

  FilterChip _filterChip(WorkspaceActivityFilter filter, String label) =>
      FilterChip(
        showCheckmark: false,
        label: Text(label),
        selected: _filter == filter,
        onSelected: (selected) {
          if (selected) {
            setState(() => _filter = filter);
            widget.onFilterChanged?.call(filter);
          }
        },
      );

  String _filterLabel(WorkspaceActivityFilter filter) => switch (filter) {
    WorkspaceActivityFilter.all => 'All',
    WorkspaceActivityFilter.running => 'Running',
    WorkspaceActivityFilter.needsInput => 'Needs input',
  };

  String _filterEmptyLabel(WorkspaceActivityFilter filter) => switch (filter) {
    WorkspaceActivityFilter.all => 'No recent chats',
    WorkspaceActivityFilter.running => 'No running sessions',
    WorkspaceActivityFilter.needsInput => 'No sessions need input',
  };
}
