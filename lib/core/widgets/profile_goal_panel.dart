import 'package:flutter/material.dart';
import 'anchored_expansion_tile.dart';

import '../models/session_control.dart';
import '../services/profile_workspace_controller.dart';

/// Displays the server-owned goal for one captured chat and its supported
/// controls. The containing screen decides whether an empty panel is shown.
class ProfileGoalPanel extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final ProfileChat chat;
  final bool initiallyExpanded;

  const ProfileGoalPanel({
    super.key,
    required this.controller,
    required this.chat,
    this.initiallyExpanded = false,
  });

  @override
  State<ProfileGoalPanel> createState() => _ProfileGoalPanelState();
}

class _ProfileGoalPanelState extends State<ProfileGoalPanel> {
  bool _requested = false;
  final _criterionDraft = TextEditingController();

  @override
  void dispose() {
    _criterionDraft.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _requestRefresh();
  }

  @override
  void didUpdateWidget(ProfileGoalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chat, widget.chat)) {
      _requested = false;
      _criterionDraft.clear();
      _requestRefresh();
    }
  }

  void _requestRefresh() {
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await widget.controller.refreshSessionControl(widget.chat);
      } catch (_) {
        // The controller retains the error for the panel.
      }
    });
  }

  Future<void> _refresh() async {
    try {
      await widget.controller.refreshSessionControl(widget.chat);
    } catch (_) {
      // The controller retains the error for the panel.
    }
  }

  Future<void> _run(SessionControlAction action) async {
    try {
      await widget.controller.controlSession(widget.chat, action);
    } catch (_) {
      // The controller retains the error and notice for the panel.
    }
  }

  Future<void> _addCriterion() async {
    final controller = widget.controller;
    final chat = widget.chat;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AddCriterionDialog(
        controller: controller,
        chat: chat,
        initialText: _criterionDraft.text,
        ownsDestination: () =>
            mounted &&
            identical(widget.controller, controller) &&
            identical(widget.chat, chat),
        onDraftChanged: (value) {
          if (mounted &&
              identical(widget.controller, controller) &&
              identical(widget.chat, chat)) {
            _criterionDraft.text = value;
          }
        },
        onAccepted: () {
          if (mounted &&
              identical(widget.controller, controller) &&
              identical(widget.chat, chat)) {
            _criterionDraft.clear();
          }
        },
      ),
    );
  }

  Future<void> _removeCriterion(int index, String text) async {
    final controller = widget.controller;
    final chat = widget.chat;
    final criteria = List<String>.of(
      chat.sessionControl?.goal?.subgoals ?? const <String>[],
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Remove criterion ${index + 1}?'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !identical(widget.controller, controller) ||
        !identical(widget.chat, chat)) {
      return;
    }
    if (!_sameCriteria(
      criteria,
      chat.sessionControl?.goal?.subgoals ?? const <String>[],
    )) {
      await _showCriteriaChanged();
      return;
    }
    await controller.controlSession(
      chat,
      SessionControlAction.subgoalRemove,
      args: {'index': index + 1},
    );
  }

  Future<void> _clearCriteria() async {
    final controller = widget.controller;
    final chat = widget.chat;
    final criteria = List<String>.of(
      chat.sessionControl?.goal?.subgoals ?? const <String>[],
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Clear all criteria?'),
        content: const Text('This removes every criterion from this goal.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear criteria'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !identical(widget.controller, controller) ||
        !identical(widget.chat, chat)) {
      return;
    }
    if (!_sameCriteria(
      criteria,
      chat.sessionControl?.goal?.subgoals ?? const <String>[],
    )) {
      await _showCriteriaChanged();
      return;
    }
    await controller.controlSession(chat, SessionControlAction.subgoalClear);
  }

  Future<void> _showCriteriaChanged() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Criteria changed'),
      content: const Text(
        'Hermes updated these criteria. Review the refreshed list before trying again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  static bool _sameCriteria(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear goal?'),
        content: const Text('This clears the goal on the Hermes server.'),
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
    if (confirmed == true && mounted) {
      await _run(SessionControlAction.goalClear);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final chat = widget.chat;
      final snapshot = chat.sessionControl;
      final goal = snapshot?.goal;
      final working = chat.sessionControlLoading || chat.sessionControlWorking;
      final error = chat.sessionControlError;
      return AnchoredExpansionTile(
        key: ValueKey(('goal', chat.key)),
        initiallyExpanded: widget.initiallyExpanded,
        minTileHeight: 48,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.track_changes_outlined, size: 20),
        title: const Text('Goal'),
        subtitle: Text(_summary(goal, chat.sessionControlNotice)),
        trailing: chat.sessionControlLoading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          if (error != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(error)),
                TextButton(
                  onPressed: working ? null : _refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          if (goal == null && error == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Hermes has no active goal for this chat.'),
            ),
          if (goal != null) _GoalDetails(goal: goal),
          if (goal != null)
            _CriteriaSection(
              goal: goal,
              disabled: working,
              onAdd: _addCriterion,
              onRemove: _removeCriterion,
              onClear: _clearCriteria,
            ),
          if (goal != null)
            _GoalActions(
              goal: goal,
              disabled: working,
              onAction: _run,
              onClear: _clear,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: working ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ),
          if (chat.sessionControlNotice case final notice?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(notice),
            ),
        ],
      );
    },
  );

  static String _summary(SessionGoal? goal, String? notice) {
    if (goal == null) return notice ?? 'Server state';
    return '${_statusLabel(goal.status)} · ${goal.turnsUsed}/${goal.maxTurns} turns';
  }

  static String _statusLabel(SessionGoalStatus status) => switch (status) {
    SessionGoalStatus.active => 'Active',
    SessionGoalStatus.done => 'Done',
    SessionGoalStatus.paused => 'Paused',
  };
}

class _AddCriterionDialog extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final ProfileChat chat;
  final String initialText;
  final bool Function() ownsDestination;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onAccepted;

  const _AddCriterionDialog({
    required this.controller,
    required this.chat,
    required this.initialText,
    required this.ownsDestination,
    required this.onDraftChanged,
    required this.onAccepted,
  });

  @override
  State<_AddCriterionDialog> createState() => _AddCriterionDialogState();
}

class _AddCriterionDialogState extends State<_AddCriterionDialog> {
  late final TextEditingController _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!widget.ownsDestination()) {
      setState(() {
        _error = 'This chat changed. Close this dialog and review the goal.';
      });
      return;
    }
    final accepted = await widget.controller.controlSession(
      widget.chat,
      SessionControlAction.subgoalAdd,
      args: {'text': _draft.text.trim()},
    );
    if (!mounted) {
      return;
    }
    if (!widget.ownsDestination()) {
      setState(() {
        _error = 'This chat changed. Close this dialog and review the goal.';
      });
      return;
    }
    if (accepted) {
      widget.onAccepted();
      Navigator.pop(context);
      return;
    }
    setState(() {
      _error = 'Criterion could not be added. Review it and try again.';
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final working =
          widget.chat.sessionControlLoading ||
          widget.chat.sessionControlWorking;
      return PopScope(
        canPop: !working,
        child: AlertDialog(
          scrollable: true,
          title: const Text('Add criterion'),
          content: TextField(
            key: const ValueKey('goal-criterion-draft'),
            controller: _draft,
            enabled: !working,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Criterion',
              hintText: 'What must be true before this goal is done?',
              errorText: _error,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              widget.onDraftChanged(value);
              setState(() {});
            },
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: working || _draft.text.trim().isEmpty ? null : _add,
              child: const Text('Add'),
            ),
          ],
        ),
      );
    },
  );
}

class _GoalDetails extends StatelessWidget {
  final SessionGoal goal;

  const _GoalDetails({required this.goal});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 360),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(goal.title),
          const SizedBox(height: 8),
          _Field(label: 'Outcome', value: goal.contract.outcome),
          _Field(label: 'Verification', value: goal.contract.verification),
          _Field(label: 'Constraints', value: goal.contract.constraints),
          _Field(label: 'Boundaries', value: goal.contract.boundaries),
          _Field(label: 'Stop when', value: goal.contract.stopWhen),
          if (goal.gates.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'Verification gates',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final gate in goal.gates)
              SelectableText(
                '${gate.command} · ${gate.attempts} attempts · ${gate.maxRetries} retries allowed · ${gate.timeoutSeconds}s timeout · ${gate.lastExitCode == null ? 'not run' : 'exit ${gate.lastExitCode}'}',
              ),
          ],
          if (goal.pausedReason != null)
            _Field(label: 'Paused', value: goal.pausedReason!),
          if (goal.lastVerdict != null)
            _Field(
              label: 'Last verdict',
              value: _verdictText(goal.lastVerdict!),
            ),
          if (goal.lastReason != null)
            _Field(label: 'Reason', value: goal.lastReason!),
          if (goal.waitBarrier != null)
            _Field(
              label: 'Waiting',
              value: _barrierText(context, goal.waitBarrier!),
            ),
        ],
      ),
    ),
  );

  String _barrierText(BuildContext context, SessionGoalWaitBarrier barrier) {
    if (barrier.type == SessionGoalWaitType.until) {
      final local = DateTime.fromMillisecondsSinceEpoch(
        (barrier.untilAt! * 1000).round(),
      ).toLocal();
      final material = MaterialLocalizations.of(context);
      final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
      return '${barrier.reason} (until ${material.formatFullDate(local)} $time)';
    }
    return switch (barrier.type) {
      SessionGoalWaitType.session =>
        '${barrier.reason} (session ${barrier.sessionTarget})',
      SessionGoalWaitType.pid =>
        '${barrier.reason} (process ${barrier.processId})',
      SessionGoalWaitType.until => barrier.reason,
    };
  }

  static String _verdictText(SessionGoalVerdict verdict) => switch (verdict) {
    SessionGoalVerdict.blocked => 'Blocked',
    SessionGoalVerdict.continueRunning => 'Continue',
    SessionGoalVerdict.done => 'Done',
    SessionGoalVerdict.skipped => 'Skipped',
    SessionGoalVerdict.wait => 'Waiting',
  };
}

class _Field extends StatelessWidget {
  final String label;
  final String value;

  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: value.trim().isEmpty
        ? const SizedBox.shrink()
        : SelectableText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
  );
}

class _CriteriaSection extends StatelessWidget {
  final SessionGoal goal;
  final bool disabled;
  final Future<void> Function() onAdd;
  final Future<void> Function(int index, String text) onRemove;
  final Future<void> Function() onClear;

  const _CriteriaSection({
    required this.goal,
    required this.disabled,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Criteria (${goal.subgoals.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 4,
          runSpacing: 2,
          children: [
            TextButton.icon(
              onPressed: disabled ? null : onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add criterion'),
            ),
            if (goal.subgoals.isNotEmpty)
              TextButton.icon(
                onPressed: disabled ? null : onClear,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear criteria'),
              ),
          ],
        ),
        for (var index = 0; index < goal.subgoals.length; index++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SelectableText(
                    '${index + 1}. ${goal.subgoals[index]}',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove criterion ${index + 1}',
                onPressed: disabled
                    ? null
                    : () => onRemove(index, goal.subgoals[index]),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
      ],
    ),
  );
}

class _GoalActions extends StatelessWidget {
  final SessionGoal goal;
  final bool disabled;
  final Future<void> Function(SessionControlAction) onAction;
  final Future<void> Function() onClear;

  const _GoalActions({
    required this.goal,
    required this.disabled,
    required this.onAction,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      if (goal.status == SessionGoalStatus.active)
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.goalPause),
          icon: const Icon(Icons.pause, size: 18),
          label: const Text('Pause'),
        ),
      if (goal.status == SessionGoalStatus.paused ||
          goal.status == SessionGoalStatus.done)
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.goalResume),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Resume'),
        ),
      if (goal.waitBarrier != null)
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => onAction(SessionControlAction.goalUnwait),
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: const Text('Resume now'),
        ),
      TextButton.icon(
        onPressed: disabled ? null : onClear,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('Clear'),
      ),
    ],
  );
}
