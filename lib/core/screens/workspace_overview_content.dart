import 'dart:async';
import '../widgets/studio_error.dart';
import 'package:flutter/material.dart';

import '../models/profile_live_activity.dart';
import '../theme/profile_colors.dart';
import '../theme/wing_theme.dart';
import '../utils/relative_time.dart';
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
  final void Function(ProfileRecentChat, List<ProfileRecentChat>) onOpen;

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
    final ongoing = activity.where((item) => item.activity != null).toList();
    final history = activity.where((item) => item.activity == null).toList();
    final displayed = List<ProfileRecentChat>.unmodifiable([
      ...ongoing,
      ...history,
    ]);
    final tokens = WingTokens.of(context);
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(WorkspaceActivityFilter.all, 'All', allActivity),
              _filterChip(
                WorkspaceActivityFilter.running,
                'Running',
                allActivity,
              ),
              _filterChip(
                WorkspaceActivityFilter.needsInput,
                'Needs input',
                allActivity,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Row(
            children: [
              Icon(Icons.history, size: 16, color: tokens.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Last 24 hours + ongoing work',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
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
        if (ongoing.isNotEmpty) ...[
          _sectionHeading('Ongoing', ongoing.length),
          Material(
            key: const ValueKey('recents-ongoing'),
            color: tokens.raised,
            shape: RoundedRectangleBorder(
              borderRadius: WingRadius.card,
              side: BorderSide(color: tokens.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < ongoing.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: tokens.border),
                  _chatRow(ongoing[i], now, displayed, ongoing: true),
                ],
              ],
            ),
          ),
        ],
        if (history.isNotEmpty) ...[
          _sectionHeading('Last 24 hours', history.length),
          for (var i = 0; i < history.length; i++) ...[
            if (i > 0) Divider(height: 1, color: tokens.border),
            _chatRow(history[i], now, displayed, ongoing: false),
          ],
        ],
      ],
    );
  }

  Widget _sectionHeading(String title, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  Widget _chatRow(
    ProfileRecentChat item,
    DateTime now,
    List<ProfileRecentChat> displayed, {
    required bool ongoing,
  }) => _RecentChatRow(
    key: ValueKey(
      'activity-${item.key.workspace.profileName}-${item.key.sessionId}',
    ),
    item: item,
    now: now,
    ongoing: ongoing,
    isDefault:
        widget.controller.discovery
            ?.named(item.key.workspace.profileName)
            ?.isDefault ==
        true,
    onTap: widget.controller.switching
        ? null
        : () => widget.onOpen(item, displayed),
  );

  FilterChip _filterChip(
    WorkspaceActivityFilter filter,
    String label,
    List<ProfileRecentChat> items,
  ) => FilterChip(
    showCheckmark: false,
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label)),
        const SizedBox(width: 8),
        Text(
          '${_filterWorkspaceActivity(items, filter).length}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
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

class _RecentChatRow extends StatelessWidget {
  const _RecentChatRow({
    super.key,
    required this.item,
    required this.now,
    required this.ongoing,
    required this.isDefault,
    required this.onTap,
  });

  final ProfileRecentChat item;
  final DateTime now;
  final bool ongoing;
  final bool isDefault;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = WingTokens.of(context);
    final needsInput = item.state == ProfileLiveActivityState.needsInput;
    final statusColor = needsInput ? tokens.blocked : tokens.running;
    final status = needsInput
        ? 'Needs input'
        : item.sideTasksRunning > 0
        ? item.sideTasksRunning == 1
              ? 'Background work running'
              : '${item.sideTasksRunning} background tasks running'
        : 'Running';
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    final profileName = item.key.workspace.profileName;
    final profileColor = desktopProfileColor(profileName) ?? tokens.muted;
    final profileIcon = ExcludeSemantics(
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: profileColor.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: isDefault
            ? Icon(Icons.home_outlined, size: 12, color: profileColor)
            : Text(
                profileName.characters.first.toUpperCase(),
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 10, color: profileColor),
              ),
      ),
    );
    final title = Text(
      item.title,
      style: theme.textTheme.bodyMedium,
      maxLines: largeText ? null : 2,
      overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
    );
    final age = formatRelativeTime(now, item.lastActive);
    final timestamp = Semantics(
      label: age == 'now' ? 'Updated now' : 'Updated $age ago',
      child: ExcludeSemantics(
        child: Text(
          age,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ongoing ? 12 : 4,
          vertical: 14,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ongoing) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: profileIcon,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (largeText) ...[
                    title,
                    const SizedBox(height: 6),
                    timestamp,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 12),
                        timestamp,
                      ],
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!ongoing) ...[
                            profileIcon,
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              profileName,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (ongoing) ...[
                        Text('·', style: theme.textTheme.bodySmall),
                        Text(
                          status,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
