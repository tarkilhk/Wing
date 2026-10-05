import 'profile_session_key.dart';
import 'gateway_insight.dart';
import 'gateway_process.dart';
import 'session_control.dart';

/// Detached supervision facts. Runtime/session-control remain controller-owned.
final class ProfileSupervisionObservation {
  ProfileSupervisionObservation({
    required this.key,
    required Iterable<GatewaySubagentActivity> subagents,
    required Iterable<String> unconfirmedSubagentIds,
    required this.subagentsLoading,
    required this.subagentsError,
    required SessionControlSnapshot? sessionControl,
    required this.sessionControlLoading,
    required this.sessionControlWorking,
    required this.sessionControlError,
    required this.sessionControlNotice,
    required Iterable<GatewayProcessActivity> processes,
    required this.processesLoading,
    required this.processesError,
    required this.actionBusy,
    required this.actionError,
    required Iterable<String> stopping,
    required Map<String, String> processErrors,
  }) : subagents = List.unmodifiable(subagents.map(copySupervisedSubagent)),
       unconfirmedSubagentIds = Set.unmodifiable(unconfirmedSubagentIds),
       sessionControl = copySupervisedControl(sessionControl),
       processes = List.unmodifiable(processes),
       stopping = Set.unmodifiable(stopping),
       processErrors = Map.unmodifiable(processErrors);
  final ProfileSessionKey key;
  final List<GatewaySubagentActivity> subagents;
  final Set<String> unconfirmedSubagentIds;
  final bool subagentsLoading;
  final String? subagentsError;
  final SessionControlSnapshot? sessionControl;
  final bool sessionControlLoading, sessionControlWorking;
  final String? sessionControlError, sessionControlNotice;
  final List<GatewayProcessActivity> processes;
  final bool processesLoading;
  final String? processesError;
  final bool actionBusy;
  final String? actionError;
  final Set<String> stopping;
  final Map<String, String> processErrors;

  List<SessionControlAction> get goalActions {
    final goal = sessionControl?.goal;
    return List.unmodifiable([
      if (goal?.status == SessionGoalStatus.active)
        SessionControlAction.goalPause,
      if (goal?.status == SessionGoalStatus.paused ||
          goal?.status == SessionGoalStatus.done)
        SessionControlAction.goalResume,
      if (goal?.waitBarrier != null) SessionControlAction.goalUnwait,
    ]);
  }

  List<SessionControlAction> get loopActions {
    final loop = sessionControl?.loop;
    return List.unmodifiable([
      if (loop?.status == SessionLoopStatus.active)
        SessionControlAction.loopPause,
      if (loop?.status == SessionLoopStatus.paused)
        SessionControlAction.loopResume,
      if (loop != null && loop.status != SessionLoopStatus.done)
        SessionControlAction.loopStop,
    ]);
  }

  List<SessionControlAction> get heartbeatActions => List.unmodifiable([
    if (sessionControl?.heartbeat?.status == SessionHeartbeatStatus.active)
      SessionControlAction.heartbeatPause,
    if (sessionControl?.heartbeat?.status == SessionHeartbeatStatus.paused)
      SessionControlAction.heartbeatResume,
  ]);

  String get subagentSummary {
    if (subagents.isEmpty) return 'No live tasks';
    final running = subagents.where((item) => !item.isTerminal).length;
    final unconfirmed = subagents
        .where(
          (item) =>
              !item.isTerminal && unconfirmedSubagentIds.contains(item.id),
        )
        .length;
    if (unconfirmed > 0) {
      return [
        if (running > unconfirmed) '${running - unconfirmed} active',
        '$unconfirmed unconfirmed',
        '${subagents.length} total',
      ].join(' · ');
    }
    return running == 0
        ? '${subagents.length} finished'
        : '$running active · ${subagents.length} total';
  }

  String get backgroundSummary {
    final recurring = [
      sessionControl?.loop,
      sessionControl?.heartbeat,
    ].where((value) => value != null).length;
    final running = processes.where((value) => value.isRunning).length;
    return recurring == 0 && processes.isEmpty
        ? 'Server state'
        : '$recurring recurring · $running running';
  }
}

final class SubagentSupervisionObservation {
  SubagentSupervisionObservation({
    required GatewaySubagentActivity activity,
    required this.unconfirmed,
    required this.canControl,
    required this.acceptsSteer,
    required this.tail,
    required this.lastAvailableTail,
    required this.tailError,
    required this.tailFailures,
    required this.loadingTail,
    required this.steering,
    required this.interrupting,
    required this.controlMessage,
    required this.controlFailed,
  }) : activity = copySupervisedSubagent(activity);
  final GatewaySubagentActivity activity;
  final bool unconfirmed, canControl, acceptsSteer;
  final GatewaySubagentTail? tail, lastAvailableTail;
  final String? tailError, controlMessage;
  final int tailFailures;
  final bool loadingTail, steering, interrupting, controlFailed;
}

GatewaySubagentActivity copySupervisedSubagent(GatewaySubagentActivity value) =>
    GatewaySubagentActivity(
      id: value.id,
      goal: value.goal,
      phase: value.phase,
      parentId: value.parentId,
      depth: value.depth,
      delegationId: value.delegationId,
      model: value.model,
      detail: value.detail,
      status: value.status,
      acceptingSteer: value.acceptingSteer,
      taskIndex: value.taskIndex,
      taskCount: value.taskCount,
      startedAt: value.startedAt,
      toolCount: value.toolCount,
      lastTool: value.lastTool,
      recentActivity: List.unmodifiable(value.recentActivity),
    );

SessionControlSnapshot? copySupervisedControl(SessionControlSnapshot? value) {
  if (value == null) return null;
  final goal = value.goal;
  return SessionControlSnapshot(
    goal: goal == null
        ? null
        : SessionGoal(
            title: goal.title,
            status: goal.status,
            turnsUsed: goal.turnsUsed,
            maxTurns: goal.maxTurns,
            contract: goal.contract,
            subgoals: List.unmodifiable(goal.subgoals),
            gates: List.unmodifiable(goal.gates),
            createdAt: goal.createdAt,
            updatedAt: goal.updatedAt,
            pausedReason: goal.pausedReason,
            lastVerdict: goal.lastVerdict,
            lastReason: goal.lastReason,
            waitBarrier: goal.waitBarrier,
          ),
    loop: value.loop,
    heartbeat: value.heartbeat,
    revision: value.revision,
    updatedAt: value.updatedAt,
  );
}
