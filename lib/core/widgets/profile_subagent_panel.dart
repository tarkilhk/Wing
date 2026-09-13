import 'dart:async';

import 'package:flutter/material.dart';
import 'profile_transcript_disclosure.dart';

import '../models/gateway_insight.dart';
import '../services/profile_workspace_controller.dart';

class ProfileSubagentPanel extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final ProfileChat chat;
  final bool initiallyExpanded;

  const ProfileSubagentPanel({
    super.key,
    required this.controller,
    required this.chat,
    this.initiallyExpanded = false,
  });

  @override
  State<ProfileSubagentPanel> createState() => _ProfileSubagentPanelState();
}

class _ProfileSubagentPanelState extends State<ProfileSubagentPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded || widget.chat.subagents.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void didUpdateWidget(ProfileSubagentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chat, widget.chat) &&
        (widget.initiallyExpanded || widget.chat.subagents.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    try {
      await widget.controller.refreshSubagents(widget.chat);
    } catch (_) {
      // The controller retains the profile-scoped error for the panel.
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final chat = widget.chat;
      return ProfileTranscriptDisclosure(
        key: ValueKey(('subagents', chat.key)),
        initiallyExpanded: widget.initiallyExpanded,
        maintainState: false,
        onExpansionChanged: (expanded) {
          if (expanded) _refresh();
        },
        icon: Icons.account_tree_outlined,
        label: 'Subagents',
        summary: Text(_summary(chat.subagents, chat.unconfirmedSubagentIds)),
        loading: chat.subagentsLoading,
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 0, 8),
        children: [
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
                Expanded(child: Text(error)),
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
              titleTextStyle: Theme.of(context).textTheme.bodyMedium,
              subtitleTextStyle: Theme.of(context).textTheme.labelMedium,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                chat.unconfirmedSubagentIds.contains(activity.id)
                    ? Icons.help_outline
                    : _statusIcon(activity.status),
                size: 16,
              ),
              title: Text(
                _goal(activity),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _activitySubtitle(
                  activity,
                  unconfirmed: chat.unconfirmedSubagentIds.contains(
                    activity.id,
                  ),
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _SubagentDetailSheet(
                  controller: widget.controller,
                  chat: chat,
                  subagentId: activity.id,
                  initialActivity: activity,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: chat.subagentsLoading ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ),
        ],
      );
    },
  );
}

class _SubagentDetailSheet extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final ProfileChat chat;
  final String subagentId;
  final GatewaySubagentActivity initialActivity;

  const _SubagentDetailSheet({
    required this.controller,
    required this.chat,
    required this.subagentId,
    required this.initialActivity,
  });

  @override
  State<_SubagentDetailSheet> createState() => _SubagentDetailSheetState();
}

class _SubagentDetailSheetState extends State<_SubagentDetailSheet>
    with WidgetsBindingObserver {
  final _steer = TextEditingController();
  Timer? _tailTimer;
  GatewaySubagentTail? _tail;
  String? _tailError;
  String? _controlMessage;
  int _tailFailures = 0;
  bool _loadingTail = false;
  bool _steering = false;
  bool _interrupting = false;
  GatewaySubagentTail? _lastAvailableTail;
  bool _expandedGoal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTail());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTail();
    } else {
      _tailTimer?.cancel();
      _tailTimer = null;
    }
  }

  void _startTail() {
    if (!mounted || _tailTimer != null) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    unawaited(_refreshTail());
    _tailTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshTail()),
    );
  }

  Future<void> _refreshTail() async {
    if (!mounted || _loadingTail) {
      return;
    }
    setState(() => _loadingTail = true);
    try {
      final tail = await widget.controller.loadSubagentTail(
        widget.chat,
        widget.subagentId,
      );
      if (!mounted) {
        return;
      }
      if (tail == null) {
        throw StateError('Live output is unavailable.');
      }
      setState(() {
        _tail = tail;
        if (tail.available && tail.text.isNotEmpty) _lastAvailableTail = tail;
        _tailError = null;
        _tailFailures = 0;
      });
      final activity = widget.chat.subagents
          .where((item) => item.id == widget.subagentId)
          .firstOrNull;
      if (!tail.available && activity?.isTerminal == true) {
        _tailTimer?.cancel();
        _tailTimer = null;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tailFailures += 1;
        _tailError = 'Could not refresh live output.';
      });
      if (_tailFailures >= 3) {
        _tailTimer?.cancel();
        _tailTimer = null;
      }
    } finally {
      if (mounted) {
        setState(() => _loadingTail = false);
      }
    }
  }

  void _retryTail() {
    setState(() {
      _tailFailures = 0;
      _tailError = null;
    });
    _tailTimer?.cancel();
    _tailTimer = null;
    _startTail();
  }

  Future<void> _submitSteer() async {
    final text = _steer.text.trim();
    if (text.isEmpty || _steering) {
      return;
    }
    setState(() {
      _steering = true;
      _controlMessage = null;
    });
    try {
      final accepted = await widget.controller.steerSubagent(
        widget.chat,
        widget.subagentId,
        text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (accepted) {
          _steer.clear();
          _controlMessage = 'Steering queued.';
        } else {
          _controlMessage = 'The subagent did not accept that steering.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _controlMessage = 'Steering could not be queued.');
      }
    } finally {
      if (mounted) {
        setState(() => _steering = false);
      }
    }
  }

  Future<void> _interrupt() async {
    if (_interrupting) {
      return;
    }
    setState(() {
      _interrupting = true;
      _controlMessage = null;
    });
    try {
      final found = await widget.controller.interruptSubagent(
        widget.chat,
        widget.subagentId,
      );
      if (mounted) {
        setState(() {
          _controlMessage = found
              ? 'Interrupt requested.'
              : 'The subagent is no longer running.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _controlMessage = 'Interrupt could not be requested.');
      }
    } finally {
      if (mounted) {
        setState(() => _interrupting = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tailTimer?.cancel();
    _steer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final activity = widget.chat.subagents
          .where((item) => item.id == widget.subagentId)
          .firstOrNull;
      final current = activity ?? widget.initialActivity;
      final unconfirmed = widget.chat.unconfirmedSubagentIds.contains(
        widget.subagentId,
      );
      final canControl =
          activity != null && !activity.isTerminal && !unconfirmed;
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
                      enabled: !_steering,
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
                          onPressed: _interrupting ? null : _interrupt,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Interrupt'),
                        ),
                      if (current.acceptingSteer && canControl)
                        FilledButton(
                          onPressed: _steering ? null : _submitSteer,
                          child: const Text('Steer'),
                        ),
                    ],
                  ),
                  if (_controlMessage case final message?) ...[
                    const SizedBox(height: 8),
                    Text(message),
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
    final tail = _tail;
    final readableTail = tail != null && tail.available && tail.text.isNotEmpty
        ? tail
        : _lastAvailableTail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Live output')),
            if (_loadingTail)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            IconButton(
              tooltip: 'Refresh live output',
              onPressed: _loadingTail ? null : _refreshTail,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_tailError case final error?) ...[
          Text(error),
          if (_tailFailures >= 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _retryTail,
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
          if (_tailError != null ||
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

String _summary(
  List<GatewaySubagentActivity> activities,
  Set<String> unconfirmedIds,
) {
  if (activities.isEmpty) {
    return 'No live tasks';
  }
  final running = activities.where((activity) => !activity.isTerminal).length;
  final unconfirmed = activities
      .where(
        (activity) =>
            !activity.isTerminal && unconfirmedIds.contains(activity.id),
      )
      .length;
  if (unconfirmed > 0) {
    return [
      if (running > unconfirmed) '${running - unconfirmed} active',
      '$unconfirmed unconfirmed',
      '${activities.length} total',
    ].join(' · ');
  }
  return running == 0
      ? '${activities.length} finished'
      : '$running active · ${activities.length} total';
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
  GatewaySubagentStatus.completed => Icons.check_circle_outline,
  GatewaySubagentStatus.failed => Icons.error_outline,
  GatewaySubagentStatus.interrupted => Icons.stop_circle_outlined,
};
