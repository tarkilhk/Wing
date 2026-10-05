import 'studio_error.dart';

import 'package:flutter/material.dart';
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
          ListTile(
            key: ValueKey(('subagent', chat.key, activity.id)),
            dense: true,
            minLeadingWidth: 16,
            horizontalTitleGap: 8,
            titleTextStyle: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            subtitleTextStyle: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              chat.unconfirmedSubagentIds.contains(activity.id)
                  ? Icons.help_outline
                  : _statusIcon(activity.status),
              size: 16,
              color:
                  !chat.unconfirmedSubagentIds.contains(activity.id) &&
                      activity.status == GatewaySubagentStatus.failed
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
            minTileHeight: 32,
            minVerticalPadding: 0,
            title: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _goal(activity),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _activitySubtitle(
                    activity,
                    unconfirmed: chat.unconfirmedSubagentIds.contains(
                      activity.id,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
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
                  Text(_activitySubtitle(current, unconfirmed: unconfirmed)),
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
                line,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

String _activitySubtitle(
  GatewaySubagentActivity activity, {
  bool unconfirmed = false,
}) {
  final status = switch (activity.status) {
    GatewaySubagentStatus.queued => 'Queued',
    GatewaySubagentStatus.running => 'Running',
    GatewaySubagentStatus.completed => 'Completed',
    GatewaySubagentStatus.failed => 'Failed',
    GatewaySubagentStatus.interrupted => 'Interrupted',
  };
  final detail = activity.isTerminal
      ? activity.detail ?? activity.lastTool ?? activity.model
      : activity.lastTool ?? activity.detail ?? activity.model;
  final startedAt = activity.startedAt;
  final elapsedSeconds = startedAt == null || activity.isTerminal
      ? null
      : (DateTime.now().millisecondsSinceEpoch / 1000 - startedAt)
            .clamp(0, double.maxFinite)
            .toInt();
  final elapsed = elapsedSeconds == null
      ? null
      : elapsedSeconds < 60
      ? '${elapsedSeconds}s'
      : '${elapsedSeconds ~/ 60}m';
  return [
    unconfirmed ? 'Last seen ${status.toLowerCase()}' : status,
    ?elapsed,
    if (detail != null && detail.isNotEmpty) detail,
  ].join(' · ');
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
