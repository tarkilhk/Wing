import 'package:flutter/foundation.dart';
import '../models/gateway_insight.dart';
import '../models/profile_supervision.dart';
import '../models/session_control.dart';
import 'profile_workspace_controller.dart';
import 'subagent_timeline_session.dart';

/// Captured supervision workflow; borrows canonical live facts and transport.
/// One instance is shared by the current chat's goal, work and subagent views.
final class ProfileSupervisionSession extends ChangeNotifier
    implements SubagentInspectionSession {
  ProfileSupervisionSession({
    required this._controller,
    required ProfileChat chat,
  }) : _chat = chat,
       _runtime = chat.runtime.runtimeId {
    _publishedInputs = _changeInputs;
    _controller.addListener(_changed);
  }
  final ProfileWorkspaceController _controller;
  final ProfileChat _chat;
  final String _runtime;
  bool _closed = false, _actionBusy = false;
  int _notificationDepth = 0;
  bool _notifierDisposed = false;
  String? _actionError;
  final _stopping = <String>{};
  final _processErrors = <String, String>{};
  final _details = <SubagentSupervisionDetail>{};
  Object? _publishedInputs;
  Set<String> _publishedStopping = const {};
  Map<String, String> _publishedProcessErrors = const {};
  Object get _changeInputs =>
      (active, _chat.workRevision, _actionBusy, _actionError);
  bool get active =>
      !_closed &&
      _controller.owns(_chat.key) &&
      identical(_controller.findNotificationChat(_chat.key), _chat) &&
      _chat.runtime.runtimeId == _runtime;
  @override
  ProfileSupervisionObservation get state => ProfileSupervisionObservation(
    key: _chat.key,
    subagents: _chat.currentSubagents,
    unconfirmedSubagentIds: _chat.unconfirmedSubagentIds,
    subagentsLoading: _chat.subagentsLoading,
    subagentsAvailable: _chat.subagentsAvailable,
    subagentsError: _chat.subagentsError,
    sessionControl: _chat.sessionControl,
    sessionControlLoading: _chat.sessionControlLoading,
    sessionControlWorking: _chat.sessionControlWorking,
    sessionControlError: _chat.sessionControlError,
    sessionControlNotice: _chat.sessionControlNotice,
    processes: _chat.currentProcesses,
    processesLoading: _chat.processesLoading,
    processesError: _chat.processesError,
    inlineProcessesError: _chat.inlineProcessesError,
    actionBusy: _actionBusy,
    actionError: _actionError,
    stopping: _stopping,
    processErrors: _processErrors,
  );
  void _changed() {
    if (_closed) return;
    if (!active) {
      for (final detail in _details.toList()) {
        detail.setActive(false);
      }
    }
    final inputs = _changeInputs;
    if (_publishedInputs == inputs &&
        setEquals(_publishedStopping, _stopping) &&
        mapEquals(_publishedProcessErrors, _processErrors)) {
      return;
    }
    _publishedInputs = inputs;
    _publishedStopping = Set.of(_stopping);
    _publishedProcessErrors = Map.of(_processErrors);
    _notificationDepth++;
    try {
      notifyListeners();
    } finally {
      _notificationDepth--;
      if (_closed && _notificationDepth == 0 && !_notifierDisposed) {
        _notifierDisposed = true;
        super.dispose();
      }
    }
  }

  @override
  Future<void> refreshSubagents() async {
    if (!active) return;
    try {
      await _controller.refreshSubagents(_chat);
    } catch (_) {
      /* Canonical owner retains error. */
    }
  }

  Future<void> refreshControl() async {
    if (!active) return;
    try {
      await _controller.refreshSessionControl(_chat);
    } catch (_) {
      /* Canonical owner retains error. */
    }
  }

  Future<void> refreshProcesses() async {
    if (!active) return;
    try {
      await _controller.refreshProcesses(_chat);
    } catch (_) {
      /* Canonical owner retains error. */
    }
  }

  Future<void> refreshWork() async {
    if (!active) return;
    _actionError = null;
    _processErrors.clear();
    _changed();
    if (!active) return;
    await Future.wait([refreshControl(), refreshProcesses()]);
  }

  Future<bool> control(SessionControlAction action) {
    if ({
      SessionControlAction.subgoalAdd,
      SessionControlAction.subgoalRemove,
      SessionControlAction.subgoalClear,
    }.contains(action)) {
      throw ArgumentError('Use the issued criterion editor or review.');
    }
    return _control(action);
  }

  Future<bool> _control(
    SessionControlAction action, {
    Map<String, dynamic> args = const {},
    bool Function()? captured,
  }) async {
    if (!active || _actionBusy) return false;
    _actionBusy = true;
    _actionError = null;
    _changed();
    try {
      if (!active || (captured != null && !captured())) return false;
      final accepted = await _controller.controlSession(
        _chat,
        action,
        args: args,
        canDispatch: () => active && (captured == null || captured()),
      );
      if (!active) return false;
      if (!accepted && _chat.sessionControlError == null) {
        _actionError = 'The server did not accept the action.';
      }
      return accepted;
    } catch (_) {
      if (active && _chat.sessionControlError == null) {
        _actionError = 'The action could not be completed.';
      }
      return false;
    } finally {
      _actionBusy = false;
      _changed();
    }
  }

  GoalCriteriaReview reviewCriteria({int? index}) {
    if (!active) throw StateError('This chat changed. Review the goal.');
    final criteria = List<String>.unmodifiable(
      _chat.sessionControl?.goal?.subgoals ?? const [],
    );
    if (index != null && (index < 0 || index >= criteria.length)) {
      throw StateError('Criteria changed. Review the refreshed list.');
    }
    return GoalCriteriaReview._(this, criteria, index);
  }

  bool _ownsCriteria(GoalCriteriaReview review) {
    if (!active || !identical(review._owner, this)) return false;
    final current = _chat.sessionControl?.goal?.subgoals ?? const <String>[];
    if (review.criteria.length != current.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != review.criteria[i]) return false;
    }
    return true;
  }

  Future<bool> applyCriteriaReview(GoalCriteriaReview review) {
    if (!_ownsCriteria(review)) return Future.value(false);
    return _control(
      review.index == null
          ? SessionControlAction.subgoalClear
          : SessionControlAction.subgoalRemove,
      args: review.index == null ? const {} : {'index': review.index! + 1},
      captured: () => _ownsCriteria(review),
    );
  }

  GoalCriterionEditor editCriterion() => GoalCriterionEditor._(this);
  Future<void> stopProcess(String id) async {
    if (!active || !_stopping.add(id)) return;
    _processErrors.remove(id);
    _changed();
    try {
      if (!active) return;
      final accepted = await _controller.stopProcess(
        _chat,
        id,
        canDispatch: () => active,
      );
      if (active && !accepted && _chat.processesError == null) {
        _processErrors[id] =
            'The server did not confirm that this process stopped.';
      }
    } catch (_) {
      if (active && _chat.processesError == null) {
        _processErrors[id] = 'This process could not be stopped.';
      }
    } finally {
      _stopping.remove(id);
      _changed();
    }
  }

  void dismissProcess(String id) {
    if (!active) return;
    _processErrors.remove(id);
    _controller.dismissProcess(_chat, id);
    _changed();
  }

  @override
  SubagentSupervisionDetail openSubagent(String id) {
    final activity = _chat.subagents.where((item) => item.id == id).firstOrNull;
    if (!active || activity == null) {
      throw StateError('Subagent is no longer available.');
    }
    final detail = SubagentSupervisionDetail._(
      this,
      copySupervisedSubagent(activity),
    );
    _details.add(detail);
    return detail;
  }

  void setActive(bool value) {
    for (final detail in _details.toList()) {
      detail.setActive(value);
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _controller.removeListener(_changed);
    for (final detail in _details.toList()) {
      detail.dispose();
    }
    if (_notificationDepth == 0 && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}

final class GoalCriteriaReview {
  GoalCriteriaReview._(this._owner, this.criteria, this.index);
  final ProfileSupervisionSession _owner;
  final List<String> criteria;
  final int? index;
  bool get current => _owner._ownsCriteria(this);
}

final class GoalCriterionEditor {
  GoalCriterionEditor._(this._owner);
  final ProfileSupervisionSession _owner;
  bool _closed = false;
  String? _error;
  String? get error => _error;
  bool get active => !_closed && _owner.active;
  bool canSubmit(String text) =>
      active &&
      text.trim().isNotEmpty &&
      !_owner.state.sessionControlLoading &&
      !_owner.state.sessionControlWorking &&
      !_owner.state.actionBusy;
  Future<bool> submit(String text) async {
    if (!active) {
      _error = 'This chat changed. Close this dialog and review the goal.';
      return false;
    }
    if (!canSubmit(text)) return false;
    final accepted = await _owner._control(
      SessionControlAction.subgoalAdd,
      args: {'text': text.trim()},
      captured: () => active,
    );
    if (!active) {
      _error = 'This chat changed. Close this dialog and review the goal.';
      return false;
    }
    _error = accepted
        ? null
        : 'Criterion could not be added. Review it and try again.';
    return accepted;
  }

  void dispose() {
    _closed = true;
  }
}

/// One issued detail retains this route's reader and commands; it never duplicates
/// the parent roster or execution owner. Closing revokes further polling/send.
final class SubagentSupervisionDetail extends ChangeNotifier
    implements SubagentInspectionDetail {
  SubagentSupervisionDetail._(this._owner, this._initial) {
    _owner.addListener(_changed);
    timeline = _owner._controller.openSubagentTimeline(
      _owner._chat,
      _initial.id,
    );
  }
  @override
  late final SubagentTimelineSession timeline;
  final ProfileSupervisionSession _owner;
  final GatewaySubagentActivity _initial;
  bool _closed = false, _steering = false, _interrupting = false;
  int _notificationDepth = 0;
  bool _notifierDisposed = false;
  String? _controlMessage;
  bool _controlFailed = false;
  bool get _current => !_closed && _owner.active;
  GatewaySubagentActivity? get _activity => _owner._chat.subagents
      .where((item) => item.id == _initial.id)
      .firstOrNull;
  @override
  SubagentSupervisionObservation get state {
    final activity = _activity ?? _initial;
    final unconfirmed = _owner._chat.unconfirmedSubagentIds.contains(
      _initial.id,
    );
    final controllable =
        _current && _activity != null && !activity.isTerminal && !unconfirmed;
    return SubagentSupervisionObservation(
      activity: activity,
      unconfirmed: unconfirmed,
      canControl: controllable,
      acceptsSteer: controllable && activity.acceptingSteer,
      steering: _steering,
      interrupting: _interrupting,
      controlMessage: _controlMessage,
      controlFailed: _controlFailed,
    );
  }

  void _changed() {
    if (_closed) return;
    _notificationDepth++;
    try {
      notifyListeners();
    } finally {
      _notificationDepth--;
      if (_closed && _notificationDepth == 0 && !_notifierDisposed) {
        _notifierDisposed = true;
        super.dispose();
      }
    }
  }

  @override
  void setActive(bool value) => timeline.setActive(value);

  @override
  Future<bool> steer(String text) async {
    final message = text.trim();
    if (message.isEmpty || _steering || !state.acceptsSteer) return false;
    _steering = true;
    _controlMessage = null;
    _controlFailed = false;
    _changed();
    try {
      if (!_current) return false;
      final accepted = await _owner._controller.steerSubagent(
        _owner._chat,
        _initial.id,
        message,
        canDispatch: () => _current && state.acceptsSteer,
      );
      if (!_current) return false;
      _controlMessage = accepted ? 'Steering queued.' : 'Steer rejected';
      _controlFailed = !accepted;
      return accepted;
    } catch (_) {
      if (_current) {
        _controlMessage = 'Steering failed';
        _controlFailed = true;
      }
      return false;
    } finally {
      _steering = false;
      _changed();
    }
  }

  @override
  Future<void> interrupt() async {
    if (_interrupting || !state.canControl) return;
    _interrupting = true;
    _controlMessage = null;
    _controlFailed = false;
    _changed();
    try {
      if (!_current) return;
      final found = await _owner._controller.interruptSubagent(
        _owner._chat,
        _initial.id,
        canDispatch: () => _current && state.canControl,
      );
      if (_current) {
        _controlMessage = found
            ? 'Interrupt requested.'
            : 'The subagent is no longer running.';
      }
    } catch (_) {
      if (_current) {
        _controlMessage = 'Interrupt failed';
        _controlFailed = true;
      }
    } finally {
      _interrupting = false;
      _changed();
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    timeline.dispose();
    _owner.removeListener(_changed);
    _owner._details.remove(this);
    if (_notificationDepth == 0 && !_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
