import '../theme/wing_theme.dart';
import 'studio_error.dart';
import 'package:flutter/material.dart';
import 'anchored_expansion_tile.dart';
import 'profile_transcript_disclosure.dart';

import '../models/gateway_process.dart';
import '../models/session_control.dart';
import '../services/profile_supervision_session.dart';

/// Server-owned recurring work and background processes for one captured chat.
class ProfileBackgroundWorkPanel extends StatefulWidget {
  final ProfileSupervisionSession session;
  final bool initiallyExpanded;

  const ProfileBackgroundWorkPanel({
    super.key,
    required this.session,
    this.initiallyExpanded = false,
  });

  @override
  State<ProfileBackgroundWorkPanel> createState() =>
      _ProfileBackgroundWorkPanelState();
}

class _ProfileBackgroundWorkPanelState
    extends State<ProfileBackgroundWorkPanel> {
  bool _requested = false;
  @override
  void initState() {
    super.initState();
    _requestRefresh();
  }

  @override
  void didUpdateWidget(ProfileBackgroundWorkPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _requested = false;
      _requestRefresh();
    }
  }

  void _requestRefresh() {
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() => widget.session.refreshWork();
  Future<void> _refreshSessionControl() => widget.session.refreshControl();
  Future<void> _refreshProcesses() => widget.session.refreshProcesses();
  Future<void> _control(SessionControlAction action) async {
    await widget.session.control(action);
  }

  Future<void> _confirmClearHeartbeat() async {
    final session = widget.session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear heartbeat?'),
        content: const Text(
          'This removes the heartbeat schedule from the Hermes server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && identical(widget.session, session)) {
      await session.control(SessionControlAction.heartbeatClear);
    }
  }

  Future<void> _stopProcess(GatewayProcessActivity process) =>
      widget.session.stopProcess(process.id);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final chat = widget.session.state;
      final snapshot = chat.sessionControl;
      final working =
          chat.actionBusy ||
          chat.sessionControlLoading ||
          chat.sessionControlWorking;
      final refreshing = chat.sessionControlLoading || chat.processesLoading;
      return ProfileTranscriptDisclosure(
        key: ValueKey(('background-work', chat.key)),
        initiallyExpanded: widget.initiallyExpanded,
        maintainState: false,
        icon: Icons.work_history_outlined,
        label: 'Background work',
        summary: Text(chat.backgroundSummary),
        loading: refreshing,
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 0, 8),
        children: [
          if (snapshot?.loop case final loop?)
            _LoopSection(
              loop: loop,
              actions: chat.loopActions,
              disabled: working,
              onAction: _control,
            ),
          if (snapshot?.heartbeat case final heartbeat?)
            _HeartbeatSection(
              heartbeat: heartbeat,
              actions: chat.heartbeatActions,
              disabled: working,
              onAction: _control,
              onClear: _confirmClearHeartbeat,
            ),
          if (snapshot?.loop == null && snapshot?.heartbeat == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No recurring work is configured for this chat.'),
            ),
          if (chat.sessionControlError case final error?)
            _ErrorRow(
              message: error,
              onRetry: working ? null : _refreshSessionControl,
            ),
          if (chat.actionError case final error?)
            Align(alignment: Alignment.centerLeft, child: StudioError(error)),
          if (chat.sessionControlNotice case final notice?)
            Align(alignment: Alignment.centerLeft, child: Text(notice)),
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Processes',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (chat.processesError case final error?)
            _ErrorRow(
              message: error,
              onRetry: chat.processesLoading ? null : _refreshProcesses,
            ),
          if (chat.processes.isEmpty && chat.processesError == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No background processes are running or retained.'),
            ),
          for (final process in chat.processes)
            _ProcessTile(
              process: process,
              stopping: chat.stopping.contains(process.id),
              error: chat.processErrors[process.id],
              onStop: () => _stopProcess(process),
              onDismiss: () => widget.session.dismissProcess(process.id),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: refreshing || chat.actionBusy ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ),
        ],
      );
    },
  );
}

class _LoopSection extends StatelessWidget {
  final SessionLoop loop;
  final List<SessionControlAction> actions;
  final bool disabled;
  final Future<void> Function(SessionControlAction) onAction;

  const _LoopSection({
    required this.loop,
    required this.disabled,
    required this.actions,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => _WorkSection(
    icon: Icons.repeat,
    title: 'Loop · ${_loopStatus(loop.status)}',
    prompt: loop.prompt,
    details: [
      _loopCadence(loop),
      _loopRunCount(loop),
      if (loop.nextDueAt > 0)
        'Next due ${_serverTime(context, loop.nextDueAt)}',
      if (loop.awaitingResponse) 'Waiting for the current response',
      if (loop.deferredByGoal) 'Deferred while the goal is active',
      if (loop.pausedReason case final reason? when reason.trim().isNotEmpty)
        'Paused: $reason',
      if (loop.lastStopReason case final reason? when reason.trim().isNotEmpty)
        'Stopped: $reason',
    ],
    actions: [
      if (actions.contains(SessionControlAction.loopPause))
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.loopPause),
          icon: const Icon(Icons.pause, size: 18),
          label: const Text('Pause loop'),
        ),
      if (actions.contains(SessionControlAction.loopResume))
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.loopResume),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Resume loop'),
        ),
      if (actions.contains(SessionControlAction.loopStop))
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.loopStop),
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Stop loop'),
        ),
    ],
  );
}

class _HeartbeatSection extends StatelessWidget {
  final SessionHeartbeat heartbeat;
  final List<SessionControlAction> actions;
  final bool disabled;
  final Future<void> Function(SessionControlAction) onAction;
  final Future<void> Function() onClear;

  const _HeartbeatSection({
    required this.heartbeat,
    required this.disabled,
    required this.actions,
    required this.onAction,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => _WorkSection(
    icon: Icons.monitor_heart_outlined,
    title: 'Heartbeat · ${_heartbeatStatus(heartbeat.status)}',
    prompt: heartbeat.prompt,
    details: [
      'Every ${_duration(heartbeat.intervalSeconds)}',
      '${heartbeat.fireCount} runs',
    ],
    actions: [
      if (actions.contains(SessionControlAction.heartbeatPause))
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.heartbeatPause),
          icon: const Icon(Icons.pause, size: 18),
          label: const Text('Pause heartbeat'),
        ),
      if (actions.contains(SessionControlAction.heartbeatResume))
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.heartbeatResume),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Resume heartbeat'),
        ),
      TextButton.icon(
        onPressed: disabled ? null : onClear,
        icon: const Icon(Icons.clear, size: 18),
        label: const Text('Clear heartbeat'),
      ),
    ],
  );
}

class _WorkSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String prompt;
  final List<String> details;
  final List<Widget> actions;

  const _WorkSection({
    required this.icon,
    required this.title,
    required this.prompt,
    required this.details,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              prompt.trim().isEmpty ? 'No prompt provided' : prompt,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [for (final detail in details) Text(detail)],
            ),
            if (actions.isNotEmpty)
              Wrap(spacing: 4, runSpacing: 2, children: actions),
          ],
        ),
      ),
    ),
  );
}

class _ProcessTile extends StatelessWidget {
  final GatewayProcessActivity process;
  final bool stopping;
  final String? error;
  final Future<void> Function() onStop;
  final VoidCallback onDismiss;

  const _ProcessTile({
    required this.process,
    required this.stopping,
    required this.error,
    required this.onStop,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => AnchoredExpansionTile(
    key: ValueKey(('process', process.id)),
    minTileHeight: 44,
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(left: 12, right: 4, bottom: 8),
    title: Text(
      process.command,
      style: WingTokens.of(context).typography.mono,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(_processStatus(process)),
    children: [
      if (process.cwd case final cwd?)
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            'Folder: $cwd',
            style: WingTokens.of(context).typography.mono,
          ),
        ),
      if (process.pid case final pid?)
        Align(alignment: Alignment.centerLeft, child: Text('PID $pid')),
      if (process.detached || process.notifyOnComplete)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            [
              if (process.detached) 'Detached',
              if (process.notifyOnComplete) 'Completion notice enabled',
            ].join(' · '),
          ),
        ),
      if (process.outputTail case final output?) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Recent output',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SelectableText(
            output,
            style: WingTokens.of(context).typography.mono,
          ),
        ),
      ],
      if (error case final message?)
        Align(alignment: Alignment.centerLeft, child: StudioError(message)),
      Align(
        alignment: Alignment.centerRight,
        child: process.isRunning
            ? TextButton.icon(
                onPressed: stopping ? null : onStop,
                icon: stopping
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop, size: 18),
                label: const Text('Stop process'),
              )
            : TextButton.icon(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Dismiss'),
              ),
      ),
    ],
  );
}

class _ErrorRow extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _ErrorRow({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: StudioError(message)),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}

String _loopStatus(SessionLoopStatus status) => switch (status) {
  SessionLoopStatus.active => 'Active',
  SessionLoopStatus.paused => 'Paused',
  SessionLoopStatus.done => 'Stopped',
};

String _heartbeatStatus(SessionHeartbeatStatus status) => switch (status) {
  SessionHeartbeatStatus.active => 'Active',
  SessionHeartbeatStatus.paused => 'Paused',
};

String _loopCadence(SessionLoop loop) => switch (loop.mode) {
  SessionLoopMode.interval => 'Every ${_duration(loop.intervalSeconds)}',
  SessionLoopMode.selfPaced =>
    'Self-paced · ${_duration(loop.currentDelay)} delay',
};

String _loopRunCount(SessionLoop loop) {
  if (loop.times > 0) return '${loop.ticksFired}/${loop.times} runs';
  if (loop.maxTicks > 0) {
    return '${loop.ticksFired}/${loop.maxTicks} tick budget';
  }
  return '${loop.ticksFired} runs';
}

String _serverTime(BuildContext context, num epochSeconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(
    (epochSeconds * 1000).round(),
  ).toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatShortDate(date)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

String _duration(num seconds) {
  final whole = seconds.round();
  if (whole >= 3600 && whole % 3600 == 0) return '${whole ~/ 3600}h';
  if (whole >= 60 && whole % 60 == 0) return '${whole ~/ 60}m';
  return '${seconds.toStringAsFixed(seconds == whole ? 0 : 1)}s';
}

String _processStatus(GatewayProcessActivity process) {
  if (process.isRunning) {
    return process.uptimeSeconds == null
        ? 'Running'
        : 'Running · ${_duration(process.uptimeSeconds!)} uptime';
  }
  return process.exitCode == null
      ? 'Exited'
      : 'Exited · code ${process.exitCode}';
}
