import 'studio_error.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../presentation/tool_call_presentation.dart';
import '../theme/wing_theme.dart';
import 'activity_time.dart';
import 'profile_transcript_disclosure.dart';

import '../models/gateway_insight.dart';
import '../services/profile_supervision_session.dart';

class ProfileSubagentPanel extends StatefulWidget {
  final ProfileSupervisionSession session;
  final bool initiallyExpanded;
  final bool embedded;

  const ProfileSubagentPanel({
    super.key,
    required this.session,
    this.initiallyExpanded = false,
    this.embedded = false,
  });

  @override
  State<ProfileSubagentPanel> createState() => _ProfileSubagentPanelState();
}

class _ProfileSubagentPanelState extends State<ProfileSubagentPanel> {
  @override
  void initState() {
    super.initState();
    if (!widget.embedded &&
        (widget.initiallyExpanded || widget.session.state.subagents.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void didUpdateWidget(ProfileSubagentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.embedded &&
        !identical(oldWidget.session, widget.session) &&
        (widget.initiallyExpanded || widget.session.state.subagents.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    try {
      await widget.session.refreshSubagents();
    } catch (_) {
      // The controller retains the profile-scoped error for the panel.
    }
  }

  Future<void> _openSubagent(String id) async {
    final detail = widget.session.openSubagent(id);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _SubagentDetailSheet(session: detail),
      );
    } finally {
      detail.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final chat = widget.session.state;
      final children = <Widget>[
        if (widget.embedded && chat.subagentsLoading)
          const LinearProgressIndicator(minHeight: 1),
        if (chat.unconfirmedSubagentIds.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Refresh could not confirm every subagent. Showing their last known activity.',
            ),
          ),
        if (chat.subagentsError case final error?)
          Row(
            children: [
              Expanded(child: StudioError(error)),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        if (!chat.subagentsLoading &&
            chat.subagentsError == null &&
            chat.subagents.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('No live subagents for this chat.'),
          ),
        for (final activity in chat.subagents)
          _SubagentRow(
            key: ValueKey(('subagent', chat.key, activity.id)),
            activity: activity,
            unconfirmed: chat.unconfirmedSubagentIds.contains(activity.id),
            onTap: () => _openSubagent(activity.id),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: chat.subagentsLoading ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ),
      ];
      if (widget.embedded) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      }
      return ProfileTranscriptDisclosure(
        key: ValueKey(('subagents', chat.key)),
        initiallyExpanded: widget.initiallyExpanded,
        maintainState: false,
        onExpansionChanged: (expanded) {
          if (expanded) _refresh();
        },
        icon: Icons.account_tree_outlined,
        label: 'Subagents',
        summary: Text(chat.subagentSummary),
        loading: chat.subagentsLoading,
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 0, 8),
        children: children,
      );
    },
  );
}

class _SubagentDetailSheet extends StatefulWidget {
  final SubagentSupervisionDetail session;
  const _SubagentDetailSheet({required this.session});

  @override
  State<_SubagentDetailSheet> createState() => _SubagentDetailSheetState();
}

class _SubagentDetailSheetState extends State<_SubagentDetailSheet>
    with WidgetsBindingObserver {
  final _steer = TextEditingController();
  bool _expandedGoal = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.session.setActive(
          WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.session.setActive(state == AppLifecycleState.resumed);
  Future<void> _submitSteer() async {
    final text = _steer.text;
    final accepted = await widget.session.steer(text);
    if (mounted && accepted && _steer.text == text) _steer.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _steer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final state = widget.session.state;
      final current = state.activity;
      final unconfirmed = state.unconfirmed;
      final canControl = state.canControl;
      return SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ListView(
                children: [
                  Text(
                    _goal(current),
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: _expandedGoal ? null : 3,
                    overflow: _expandedGoal ? null : TextOverflow.ellipsis,
                  ),
                  if (_goal(current).length > 120)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _expandedGoal = !_expandedGoal),
                        child: Text(
                          _expandedGoal ? 'Show less' : 'Show full task',
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  _SubagentStatusLine(
                    activity: current,
                    unconfirmed: unconfirmed,
                  ),
                  if (_activityText(current) case final text?) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      text,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _SubagentMetadata(activity: current),
                  if (current.acceptingSteer && canControl) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _steer,
                      minLines: 1,
                      maxLines: 3,
                      enabled: !widget.session.state.steering,
                      decoration: const InputDecoration(
                        labelText: 'Steer subagent',
                        hintText: 'Add guidance for the current task',
                      ),
                    ),
                  ],
                  if (canControl) const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canControl)
                        OutlinedButton.icon(
                          onPressed: widget.session.state.interrupting
                              ? null
                              : widget.session.interrupt,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Interrupt'),
                        ),
                      if (current.acceptingSteer && canControl)
                        FilledButton(
                          onPressed: widget.session.state.steering
                              ? null
                              : _submitSteer,
                          child: const Text('Steer'),
                        ),
                    ],
                  ),
                  if (widget.session.state.controlMessage
                      case final message?) ...[
                    const SizedBox(height: 8),
                    widget.session.state.controlFailed
                        ? StudioError(message)
                        : Text(message),
                  ],
                  const SizedBox(height: 12),
                  _tailBody(current),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _tailBody(GatewaySubagentActivity activity) {
    final tail = widget.session.state.tail;
    final readableTail = tail != null && tail.available && tail.text.isNotEmpty
        ? tail
        : widget.session.state.lastAvailableTail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Live output')),
            if (widget.session.state.loadingTail)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            IconButton(
              tooltip: 'Refresh live output',
              onPressed: widget.session.state.loadingTail
                  ? null
                  : widget.session.refreshTail,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (widget.session.state.tailError case final error?) ...[
          StudioError(error),
          if (widget.session.state.tailFailures >= 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.session.retryTail,
                child: const Text('Retry'),
              ),
            ),
        ] else if (tail == null) ...[
          const Text('Loading live output...'),
        ] else if (!tail.available) ...[
          Text(
            activity.isTerminal
                ? 'Live output is unavailable after completion.'
                : 'Hermes has not provided a live transcript for this subagent.',
          ),
        ] else if (tail.text.isEmpty) ...[
          const Text('Waiting for transcript text...'),
        ],
        if (readableTail != null) ...[
          if (widget.session.state.tailError != null ||
              tail?.available != true ||
              tail!.text.isEmpty)
            const Text('Showing the last received output.'),
          if (readableTail.truncated)
            const Text('Showing the latest 16 KiB of live output.'),
          const SizedBox(height: 6),
          SelectableText(readableTail.text),
        ],
        if (activity.recentActivity.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Recent activity'),
          const SizedBox(height: 6),
          for (final line in activity.recentActivity)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText(
                _recentActivityText(line),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

String _statusLabel(GatewaySubagentActivity activity, bool unconfirmed) {
  final status = switch (activity.status) {
    GatewaySubagentStatus.queued => 'Queued',
    GatewaySubagentStatus.running => 'Running',
    GatewaySubagentStatus.completed => 'Completed',
    GatewaySubagentStatus.failed => 'Failed',
    GatewaySubagentStatus.interrupted => 'Interrupted',
  };
  return unconfirmed ? 'Last seen ${status.toLowerCase()}' : status;
}

String? _activityText(GatewaySubagentActivity activity) {
  if (activity.isTerminal && activity.detail != null) return activity.detail;
  if (activity.phase == GatewaySubagentPhase.thinking) return 'Thinking';
  if (activity.lastTool case final tool?) {
    final label = ToolCallPresentation.titleFor(
      tool,
      completed: activity.isTerminal,
    );
    final detail = activity.detail;
    return detail == null || detail == tool ? label : '$label · $detail';
  }
  return activity.detail;
}

String _recentActivityText(String line) {
  if (!line.startsWith('Tool: ')) return line;
  final value = line.substring(6);
  final split = value.indexOf(' · ');
  final name = split < 0 ? value : value.substring(0, split);
  final caption = ToolCallPresentation.titleFor(name, completed: false);
  return split < 0 ? caption : '$caption${value.substring(split)}';
}

class _SubagentRow extends StatelessWidget {
  const _SubagentRow({
    super.key,
    required this.activity,
    required this.unconfirmed,
    required this.onTap,
  });
  final GatewaySubagentActivity activity;
  final bool unconfirmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    final metadata = [
      ?activity.model,
      if (activity.toolCount case final count?)
        '$count ${count == 1 ? 'tool call' : 'tool calls'}',
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      minTileHeight: 48,
      minLeadingWidth: 16,
      horizontalTitleGap: 8,
      leading: Icon(
        unconfirmed ? Icons.help_outline : _statusIcon(activity.status),
        size: 16,
        color: unconfirmed
            ? colors.muted
            : activity.status == GatewaySubagentStatus.failed
            ? colors.danger
            : activity.status == GatewaySubagentStatus.completed
            ? colors.success
            : activity.status == GatewaySubagentStatus.running
            ? colors.accent
            : colors.muted,
      ),
      title: Text(
        _goal(activity),
        // ListTile's inherited title style defaults to one line. Explicitly
        // allow the bounded backend goal to wrap at accessibility text sizes.
        maxLines: MediaQuery.textScalerOf(context).scale(14) > 21 ? 99 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.3,
          color: colors.onSurface,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 3),
          _SubagentStatusLine(activity: activity, unconfirmed: unconfirmed),
          if (_activityText(activity) case final text?)
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.5, color: colors.muted),
            ),
          if (metadata.isNotEmpty)
            Text(
              metadata,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.5, color: colors.muted),
            ),
        ],
      ),
      trailing: Icon(Icons.chevron_right, size: 16, color: colors.muted),
      onTap: onTap,
    );
  }
}

class _SubagentStatusLine extends StatelessWidget {
  const _SubagentStatusLine({
    required this.activity,
    required this.unconfirmed,
  });
  final GatewaySubagentActivity activity;
  final bool unconfirmed;
  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            _statusLabel(activity, unconfirmed),
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: unconfirmed
                  ? colors.muted
                  : activity.status == GatewaySubagentStatus.failed
                  ? colors.danger
                  : activity.status == GatewaySubagentStatus.completed
                  ? colors.success
                  : activity.status == GatewaySubagentStatus.running
                  ? colors.accent
                  : colors.muted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ActivityTime(
          subject: 'Agent',
          durationSeconds: activity.isTerminal
              ? activity.durationSeconds
              : null,
          backendStartedAt:
              !unconfirmed && activity.status == GatewaySubagentStatus.running
              ? activity.startedAt
              : null,
        ),
      ],
    );
  }
}

class _SubagentMetadata extends StatelessWidget {
  const _SubagentMetadata({required this.activity});
  final GatewaySubagentActivity activity;
  @override
  Widget build(BuildContext context) {
    final values = [
      'Agent ID: ${activity.id}',
      if (activity.parentId case final value?) 'Parent agent: $value',
      if (activity.delegationId case final value?) 'Delegation ID: $value',
      if (activity.model case final value?) 'Model: $value',
      if (activity.toolCount case final value?) 'Tool calls: $value',
      if (activity.startedAt case final value?)
        'Backend start (Unix seconds): $value',
      if (activity.durationSeconds case final value?)
        'Backend duration (seconds): $value',
    ].join('\n');
    return ProfileTranscriptDisclosure(
      label: 'Details',
      icon: Icons.info_outline,
      children: [
        SelectableText(
          values,
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: values)),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('Copy details'),
          ),
        ),
      ],
    );
  }
}

String _goal(GatewaySubagentActivity activity) =>
    activity.goal.trim().isEmpty ? 'Subagent' : activity.goal;

IconData _statusIcon(GatewaySubagentStatus status) => switch (status) {
  GatewaySubagentStatus.queued => Icons.schedule_outlined,
  GatewaySubagentStatus.running => Icons.sync,
  GatewaySubagentStatus.completed => Icons.flag_outlined,
  GatewaySubagentStatus.failed => Icons.error_outline,
  GatewaySubagentStatus.interrupted => Icons.stop_circle_outlined,
};
