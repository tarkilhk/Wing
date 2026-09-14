import 'package:flutter/material.dart';

import '../models/profile_live_activity.dart';
import '../services/profile_workspace_controller.dart';
export 'administration/administration_content.dart';

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
