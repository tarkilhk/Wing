import 'dart:convert';
import '../models/chat_runtime.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_approval.dart';
import '../models/gateway_clarify.dart';
import '../models/gateway_insight.dart';
import '../models/gateway_sensitive_prompt.dart';
import '../utils/tool_activity_clock.dart';

class ChatRuntimeRead {
  ChatRuntimeRead._(
    this._owner,
    this.runtimeId,
    this._read,
    this._turn,
    this._resume,
    this._event,
    this._input,
    this._execution,
    this._recovery,
  );
  final ChatRuntime _owner;
  final String runtimeId;
  final int _read, _turn, _resume, _event;
  final String _input;
  final ChatExecution _execution;
  final ChatRecovery _recovery;
  bool get current => _owner._owns(this);
}

/// Captures an operation's original facts for definite refusal.
/// It never grants permission to call a gateway.
class ChatRuntimeOperation {
  ChatRuntimeOperation._(
    this._owner,
    this.runtimeId,
    this._turn,
    this._execution,
    this._main,
    this._tool,
  );
  final ChatRuntime _owner;
  final String runtimeId;
  final int _turn;
  final ChatExecution _execution;
  final ChatMainActivity _main;
  final GatewayToolActivity? _tool;
}

class ChatRuntimeApprovalRead {
  ChatRuntimeApprovalRead._(
    this._owner,
    this.runtimeId,
    this._read,
    this._revision,
  );
  final ChatRuntime _owner;
  final String runtimeId;
  final int _read, _revision;
}

/// Issued only for a returned slash prompt. It binds the command and exact
/// preflight; it never grants transport or composer authority.
class ChatRuntimeCommandPrompt {
  ChatRuntimeCommandPrompt._(
    this._owner,
    this.runtimeId,
    this._command,
    this._turn,
    this._preflight,
  );
  final ChatRuntime _owner;
  final String runtimeId;
  final int _command;
  int _turn;
  final GatewaySensitivePromptRequest? _preflight;
  bool _accepted = false, _revoked = false;
  bool get current => _owner._ownsCommandPrompt(this);
}

class ChatRuntimeAnswer {
  ChatRuntimeAnswer._(
    this._owner,
    this.runtimeId,
    this._request,
    this._turn,
    this._events,
  );
  final ChatRuntime _owner;
  final String runtimeId;
  final Object _request;
  final int _turn, _events;
  bool get current => _owner._ownsAnswer(this);
}

/// One execution/recovery/input writer. It owns no gateway, transcript, draft
/// store or secret response value. Transport admission remains with the workspace.
class ChatRuntime {
  ChatRuntime({required this._runtimeId});
  String _runtimeId;
  bool _closed = false;
  bool _liveSessionConfirmed = true;
  ChatExecution _execution = ChatExecution.idle;
  ChatRecovery _recovery = ChatRecovery.ready;
  String? _openingError, _error;
  ChatMainActivity _main = ChatMainActivity.working;
  bool _compacting = false;
  GatewayToolActivity? _mainTool;
  final _tools = <GatewayToolActivity>[];
  String _reasoning = '';
  final _approvals = GatewayApprovalQueue();
  final _approvalCorrelations = <String, Object>{};
  bool _approvalResponding = false;
  Object? _answeringApproval;
  ChatQuestions? _questions;
  GatewaySensitivePromptRequest? _secure;
  bool _secureResponding = false;
  bool _commandRunning = false,
      _changingAnswer = false,
      _commandDispatchPending = false;
  GatewaySensitivePromptRequest? _commandPreflight;
  ChatRuntimeCommandPrompt? _commandPrompt;
  int _commandRevision = 0;
  int _turn = 0, _resume = 0, _read = 0, _events = 0, _approvalRead = 0;
  String? _decisionError, _decisionErrorRequestId;

  ChatApproval _approval(Map<String, dynamic> raw) => ChatApproval(
    correlation: _approvalCorrelations.putIfAbsent(
      raw['request_id'] as String,
      Object.new,
    ),
    requestId: raw['request_id'] as String,
    serverRequestId: raw['server_request_id'] is String
        ? raw['server_request_id'] as String
        : null,
    request: GatewayApprovalRequest.fromEventData(raw),
    eventId: raw['mobile_push_event_id'] is String
        ? (raw['mobile_push_event_id'] as String).trim()
        : null,
  );
  ChatRuntimeObservation get observation => ChatRuntimeObservation(
    runtimeId: _runtimeId,
    execution: _execution,
    recovery: _recovery,
    liveSessionConfirmed: _liveSessionConfirmed,
    openingError: _openingError,
    mainActivity: _main,
    compacting: _compacting,
    mainToolActivity: _mainTool,
    toolActivities: _tools,
    reasoning: _reasoning,
    approvals: _approvals.requests.map(_approval),
    approvalPosition: _approvals.position,
    approvalTotal: _approvals.total,
    approvalResponding: _approvalResponding,
    questions: _questions,
    secureInput: _secure,
    secureResponding: _secureResponding,
    commandRunning: _commandRunning,
    changingAnswer: _changingAnswer,
    error: _error,
    decisionError: _decisionError,
    decisionErrorRequestId: _decisionErrorRequestId,
  );
  int get turnRevision => _turn;
  int get resumeRevision => _resume;
  bool get commandDispatchPending => _commandDispatchPending;

  /// A returned slash prompt may continue while the exact command preflight
  /// response receipt is outstanding. Ordinary sends/drains remain blocked.
  bool get canContinueCommandPrompt =>
      !_closed &&
      _commandRunning &&
      !observation.executionActive &&
      _recovery == ChatRecovery.ready &&
      _approvals.requests.isEmpty &&
      _questions?.pending == null &&
      (_secure == null ||
          (identical(_secure, _commandPreflight) && _secureResponding));
  ChatRuntimeCommandPrompt captureCommandPrompt() {
    if (!canContinueCommandPrompt) {
      throw StateError('The command continuation is no longer available.');
    }
    return _commandPrompt = ChatRuntimeCommandPrompt._(
      this,
      _runtimeId,
      _commandRevision,
      _turn,
      _commandPreflight,
    );
  }

  bool _ownsCommandPrompt(ChatRuntimeCommandPrompt capture) =>
      !_closed &&
      identical(capture._owner, this) &&
      identical(_commandPrompt, capture) &&
      !capture._revoked &&
      _commandRunning &&
      capture._command == _commandRevision &&
      capture.runtimeId == _runtimeId &&
      capture._turn == _turn &&
      _recovery == ChatRecovery.ready &&
      _approvals.requests.isEmpty &&
      _questions?.pending == null &&
      (capture._preflight == null
          ? _secure == null
          : identical(_secure, capture._preflight) && _secureResponding ||
                _secure == null && capture._accepted);
  void beginCommandPrompt(ChatRuntimeCommandPrompt capture) {
    if (!capture.current) {
      throw StateError('The command continuation has changed.');
    }
    beginTurn(submitting: true);
    capture._turn = _turn;
  }

  void _revokeCommandPrompt() {
    _commandPrompt?._revoked = true;
  }

  String _inputSignature() => jsonEncode([
    _approvals.requests,
    _approvals.total,
    _approvalResponding,
    _questions?.questions
        .map(
          (q) => [
            q.requestId,
            q.questionId,
            q.question,
            q.choices,
            q.multiSelect,
          ],
        )
        .toList(),
    _questions?.answeredIds.toList(),
    _secure == null
        ? null
        : [
            _secure!.kind.name,
            _secure!.requestId,
            _secure!.title,
            _secure!.description,
            _secure!.fieldLabel,
          ],
    _secureResponding,
    _decisionError,
    _decisionErrorRequestId,
  ]);
  Map<String, dynamic> _approvalWire(Map<String, dynamic> raw) {
    final id = raw['request_id'];
    final previous = _approvals.requests
        .where((r) => r['request_id'] == id)
        .firstOrNull;
    final combined = {...?previous, ...raw};
    final parsed = GatewayApprovalRequest.fromEventData(combined);
    return {
      'request_id': id,
      'command': parsed.command,
      'description': parsed.description,
      'allow_permanent': parsed.allowPermanent,
      'smart_denied': parsed.smartDenied,
      'choices': parsed.choices.map((v) => v.wireValue).toList(growable: false),
      if (combined['server_request_id'] is String)
        'server_request_id': combined['server_request_id'],
      if (combined['mobile_push_event_id'] is String)
        'mobile_push_event_id': combined['mobile_push_event_id'],
    };
  }

  bool _owns(ChatRuntimeRead capture) =>
      !_closed &&
      identical(capture._owner, this) &&
      capture.runtimeId == _runtimeId &&
      capture._read == _read &&
      capture._turn == _turn &&
      capture._resume == _resume &&
      capture._event == _events &&
      capture._input == _inputSignature() &&
      capture._execution == _execution &&
      capture._recovery == _recovery;
  ChatRuntimeRead captureRead({bool startRead = true}) {
    if (startRead) _read++;
    return ChatRuntimeRead._(
      this,
      _runtimeId,
      _read,
      _turn,
      _resume,
      _events,
      _inputSignature(),
      _execution,
      _recovery,
    );
  }

  void observeEvent(String type, Map<String, dynamic> data) {
    if (_closed) return;
    final wasCompacting = _compacting;
    final compressionStatus =
        type == 'status.update' &&
        const {
          'compacting',
          'compressing',
          'compacted',
          'ready',
        }.contains(data['kind']);
    if (compressionStatus) {
      _compacting =
          data['kind'] == 'compacting' || data['kind'] == 'compressing';
    } else if (const {
          'message.start',
          'message.delta',
          'message.interim',
          'message.complete',
          'turn.end',
          'reasoning.delta',
          'reasoning.available',
          'tool.start',
          'tool.generating',
          'tool.complete',
          'turn.error',
          'error',
        }.contains(type) ||
        type == 'session.info' && data['running'] == false) {
      // Retire only on stock completion or evidence that the main work resumed.
      // Child progress and a running heartbeat do not finish compression.
      _compacting = false;
    }
    final relevant = switch (type) {
      'session.info' => const [
        'open_requests',
        'side_tasks',
        'model',
        'provider',
        'reasoning_effort',
        'yolo',
        'title',
      ].any(data.containsKey),
      'session.title' ||
      'message.start' ||
      'message.delta' ||
      'message.interim' ||
      'message.complete' ||
      'turn.end' ||
      'reasoning.delta' ||
      'reasoning.available' ||
      'tool.start' ||
      'tool.generating' ||
      'tool.complete' ||
      'todo.updated' ||
      'btw.complete' ||
      'background.complete' ||
      'approval' ||
      'clarify' ||
      'request.cancel' ||
      'sudo' ||
      'secret' ||
      'vault.unlock_prompt' ||
      'vault.save_login' ||
      'vault.code' ||
      'turn.error' ||
      'error' => true,
      _ => false,
    };
    if (relevant || compressionStatus || wasCompacting != _compacting) {
      _events++;
    }
  }

  ChatRuntimeOperation beginTurn({required bool submitting}) {
    final original = ChatRuntimeOperation._(
      this,
      _runtimeId,
      ++_turn,
      _execution,
      _main,
      _mainTool,
    );
    if (!_closed) {
      _execution = submitting
          ? ChatExecution.submitting
          : ChatExecution.running;
      _main = ChatMainActivity.working;
      _compacting = false;
      _mainTool = null;
      _tools.clear();
      _reasoning = '';
      _error = null;
    }
    return original;
  }

  ChatRuntimeOperation beginAnswerChange({required bool submitting}) {
    final capture = ChatRuntimeOperation._(
      this,
      _runtimeId,
      _turn,
      _execution,
      _main,
      _mainTool,
    );
    if (!_closed) {
      _changingAnswer = true;
      if (submitting) _execution = ChatExecution.submitting;
      _main = ChatMainActivity.working;
      _mainTool = null;
      _error = null;
    }
    return capture;
  }

  void acceptTurn() {
    if (!_closed) _execution = ChatExecution.running;
  }

  void finishAnswerChange() {
    _changingAnswer = false;
  }

  void rejectRegeneration(
    ChatRuntimeOperation capture, {
    required bool dispatched,
    required String error,
  }) => _rejectAnswerChange(
    capture,
    dispatched: dispatched,
    failed: dispatched,
    error: error,
  );

  void rejectSavedPromptEdit(
    ChatRuntimeOperation capture, {
    required bool dispatched,
    required String error,
  }) => _rejectAnswerChange(
    capture,
    dispatched: dispatched,
    failed: false,
    error: error,
  );

  void _rejectAnswerChange(
    ChatRuntimeOperation capture, {
    required bool dispatched,
    required bool failed,
    required String error,
  }) {
    // An owned, definitely unsent operation may settle after disposal. Closure
    // never grants dispatch authority, and a newer runtime/turn still wins.
    if ((_closed && dispatched) ||
        !identical(capture._owner, this) ||
        capture.runtimeId != _runtimeId ||
        capture._turn != _turn) {
      return;
    }
    _execution = failed ? ChatExecution.failed : capture._execution;
    if (!failed) {
      _main = capture._main;
      _mainTool = capture._tool;
    }
    _error = error;
  }

  void deliveryUncertain(String error) {
    if (!_closed) {
      _recovery = ChatRecovery.reconnecting;
      _error = error;
    }
  }

  void failTurn(String error) {
    if (!_closed) {
      _compacting = false;
      _execution = ChatExecution.failed;
      _error = error;
    }
  }

  void completeTurn({
    required bool failed,
    required bool cancelled,
    required String? error,
  }) {
    if (_closed) return;
    _compacting = false;
    _execution = failed
        ? ChatExecution.failed
        : cancelled
        ? ChatExecution.cancelled
        : ChatExecution.completed;
    _mainTool = null;
    _secureResponding = false;
    _commandPreflight = null;
    _error = error;
  }

  void reportError(String? error) {
    if (!_closed) _error = error;
  }

  void beginCommand() {
    if (!_closed) {
      _commandRevision++;
      _commandPrompt = null;
      _commandRunning = true;
      _error = null;
    }
  }

  void beginCommandDispatch() {
    if (!_closed) _commandDispatchPending = true;
  }

  void finishCommandDispatch() {
    _commandDispatchPending = false;
  }

  void finishCommand() {
    _commandRunning = false;
    _revokeCommandPrompt();
    _commandPrompt = null;
  }

  void observeText(String text) {
    if (!_closed && text.isNotEmpty) _main = ChatMainActivity.writing;
  }

  void finishSegment() {
    if (!_closed) {
      _reasoning = '';
      _main = ChatMainActivity.working;
    }
  }

  void reconcileHistoricalTools() {
    if (!_closed) _tools.removeWhere((activity) => activity.isTerminal);
  }

  void finishActivity() {
    if (!_closed) {
      _tools.clear();
      _reasoning = '';
    }
  }

  void observeReasoning(String type, Map<String, dynamic> data) {
    if (_closed) return;
    final update = GatewayReasoningUpdate.fromGatewayEvent(type, data);
    if (update == null) return;
    _reasoning = update.applyTo(_reasoning);
    if (type == 'reasoning.delta') _main = ChatMainActivity.thinking;
  }

  GatewayToolActivity? observeTool(
    String type,
    Map<String, dynamic> data, {
    bool live = true,
    Duration? receivedAt,
  }) {
    if (_closed) return null;
    final update = GatewayToolActivity.fromGatewayEvent(
      type,
      data,
      receivedAt: live ? receivedAt ?? toolActivityNow() : null,
    );
    if (update == null) return null;
    // Argument generation announces a name, not a call identity or a start.
    if (type == 'tool.generating') {
      _mainTool = update;
      _main = ChatMainActivity.tool;
      return update;
    }
    if (update.toolId == null) return null;
    final index = _tools.indexWhere((a) => a.toolId == update.toolId);
    if (index >= 0 && _tools[index].isTerminal && !update.isTerminal) {
      return _tools[index];
    }
    final merged = index < 0 ? update : _tools[index].merge(update);
    if (index < 0) {
      _tools.add(merged);
    } else {
      _tools[index] = merged;
    }
    if (type != 'tool.complete') {
      _mainTool = merged;
      _main = ChatMainActivity.tool;
    } else if (!_tools.any((a) => identical(a, _mainTool) && !a.isTerminal)) {
      _mainTool = _tools.reversed.where((a) => !a.isTerminal).firstOrNull;
      if (_main == ChatMainActivity.tool) {
        _main = _mainTool == null
            ? ChatMainActivity.working
            : ChatMainActivity.tool;
      }
    }
    return merged;
  }

  void observeExecutionSnapshot(Map<String, dynamic> data) {
    if (_closed || data['running'] is! bool) return;
    if (data['running'] == true) {
      _execution = ChatExecution.running;
    } else {
      _compacting = false;
      if (observation.executionActive) _execution = ChatExecution.completed;
    }
  }

  void beginRecovery() {
    if (!_closed) {
      _revokeCommandPrompt();
      _recovery = ChatRecovery.reconnecting;
      _secureResponding = false;
    }
  }

  void installOfflineReading() {
    if (!_closed) {
      _liveSessionConfirmed = false;
      _recovery = ChatRecovery.offline;
    }
  }

  void beginOpening() {
    if (!_closed) {
      _recovery = ChatRecovery.opening;
      _openingError = null;
    }
  }

  void finishOpening({String? error}) {
    if (!_closed) {
      _openingError = error;
      if (error == null) _liveSessionConfirmed = true;
      _recovery = error == null ? ChatRecovery.ready : ChatRecovery.opening;
    }
  }

  void cancelOpening() {
    if (!_closed && _recovery == ChatRecovery.opening) {
      _recovery = ChatRecovery.offline;
    }
  }

  void recovered() {
    if (!_closed) {
      _liveSessionConfirmed = true;
      _recovery = ChatRecovery.ready;
      _openingError = null;
    }
  }

  void invalidateResume() {
    _resume++;
  }

  void resetCompleted() {
    if (!_closed && !observation.blocksTurnAdmission) {
      _execution = ChatExecution.idle;
    }
  }

  void bindProvisional(String runtimeId) {
    if (!_closed) {
      _runtimeId = runtimeId;
      _liveSessionConfirmed = true;
      _recovery = ChatRecovery.ready;
    }
  }

  void rollbackProvisional(
    ChatRuntimeRead capture, {
    required String runtimeId,
    required ChatRecovery recovery,
    required bool liveSessionConfirmed,
  }) {
    if (capture.current) {
      _runtimeId = runtimeId;
      _liveSessionConfirmed = liveSessionConfirmed;
      _recovery = recovery;
    }
  }

  void replaceRuntime(String runtimeId) {
    if (_closed) return;
    _runtimeId = runtimeId;
    _liveSessionConfirmed = true;
    _read++;
    _resume++;
    _turn++;
    _execution = ChatExecution.idle;
    _compacting = false;
    _recovery = ChatRecovery.ready;
    _error = null;
    _approvals.clear();
    _approvalCorrelations.clear();
    _questions = null;
    _secure = null;
    _approvalResponding = false;
    _answeringApproval = null;
    _secureResponding = false;
    _commandPreflight = null;
    _mainTool = null;
    finishActivity();
  }

  bool receiveApproval(Map<String, dynamic> request) {
    if (_closed) return false;
    _revokeCommandPrompt();
    final wire = _approvalWire(request);
    final previous = _approvals.requests
        .where((r) => r['request_id'] == wire['request_id'])
        .firstOrNull;
    final changed = jsonEncode(previous) != jsonEncode(wire);
    final added = _approvals.add(wire);
    final id = request['request_id'];
    if (id is String && id.isNotEmpty) {
      if (changed) _approvalCorrelations[id] = Object();
    }
    return added;
  }

  ChatRuntimeApprovalRead captureApprovalRead() => ChatRuntimeApprovalRead._(
    this,
    _runtimeId,
    ++_approvalRead,
    _approvals.revision,
  );
  bool reconcileApprovals(
    ChatRuntimeApprovalRead capture,
    List<Map<String, dynamic>> requests,
  ) {
    if (_closed ||
        !identical(capture._owner, this) ||
        capture.runtimeId != _runtimeId ||
        capture._read != _approvalRead ||
        capture._revision != _approvals.revision) {
      return false;
    }
    final before = {
      for (final r in _approvals.requests) r['request_id']: jsonEncode(r),
    };
    final wire = requests.map(_approvalWire).toList();
    if (wire.isNotEmpty) _revokeCommandPrompt();
    _approvals.reconcile(wire);
    final ids = _approvals.requests.map((r) => r['request_id']).toSet();
    _approvalCorrelations.removeWhere((id, _) => !ids.contains(id));
    for (final raw in _approvals.requests) {
      final id = raw['request_id'] as String;
      if (before[id] != jsonEncode(raw)) _approvalCorrelations[id] = Object();
    }
    if (_recovery == ChatRecovery.reconnecting) _recovery = ChatRecovery.ready;
    return true;
  }

  ChatRuntimeAnswer beginApprovalAnswer(String id, String choice) {
    final request = observation.approval;
    if (_closed || request == null || request.requestId != id) {
      throw StateError(
        'This approval has changed. Review the current command.',
      );
    }
    if (_approvalResponding) {
      throw StateError('Approval is already being submitted.');
    }
    if (!request.request.choices.any((v) => v.wireValue == choice)) {
      throw ArgumentError('Approval choice is unavailable');
    }
    _approvalResponding = true;
    _answeringApproval = request.correlation;
    _decisionError = null;
    return ChatRuntimeAnswer._(
      this,
      _runtimeId,
      request.correlation,
      _turn,
      _events,
    );
  }

  bool _ownsAnswer(ChatRuntimeAnswer capture) =>
      _answerCurrent(capture) &&
      (identical(_questions?.correlation, capture._request) ||
          identical(_secure, capture._request) ||
          _approvalCorrelations.values.any(
            (value) => identical(value, capture._request),
          ));
  bool _answerCurrent(ChatRuntimeAnswer capture) =>
      !_closed &&
      identical(capture._owner, this) &&
      capture.runtimeId == _runtimeId;
  void finishApprovalAnswer(
    ChatRuntimeAnswer capture,
    String id, {
    required bool accepted,
    String? error,
  }) {
    if (!_answerCurrent(capture)) return;
    if (identical(_approvalCorrelations[id], capture._request) && accepted) {
      _approvals.remove(id);
      _approvalCorrelations.remove(id);
    }
    if (error != null &&
        identical(_approvalCorrelations[id], capture._request)) {
      _decisionError = error;
      _decisionErrorRequestId = id;
    }
    if (identical(_answeringApproval, capture._request)) {
      _approvalResponding = false;
      _answeringApproval = null;
    }
  }

  void reportDecisionError(String id, String error) {
    if (!_closed && observation.approvals.any((a) => a.requestId == id)) {
      _decisionError = error;
      _decisionErrorRequestId = id;
    }
  }

  void receiveQuestions(Map<String, dynamic> data) {
    if (_closed) return;
    final parsed = GatewayClarifyRequest.fromEventDataList(data);
    if (parsed.isNotEmpty) _revokeCommandPrompt();
    _questions = parsed.isEmpty
        ? null
        : ChatQuestions(
            correlation: Object(),
            questions: parsed,
            answeredIds: data['answers'] is Map
                ? (data['answers'] as Map).keys.whereType<String>()
                : const [],
            lockedAnswers: data['answers'] is Map
                ? {
                    for (final e in (data['answers'] as Map).entries)
                      if (e.key is String && e.value is String)
                        e.key as String: e.value as String,
                  }
                : const {},
          );
  }

  ChatRuntimeAnswer? beginQuestionAnswer(ChatQuestions? expected) {
    if (_closed || (expected != null && !identical(expected, _questions))) {
      throw StateError(
        'This question has changed. Review the current question.',
      );
    }
    if (_questions?.pending == null) return null;
    return ChatRuntimeAnswer._(
      this,
      _runtimeId,
      _questions!.correlation,
      _turn,
      _events,
    );
  }

  void finishQuestionAnswer(
    ChatRuntimeAnswer capture, {
    required String answer,
    required List<String>? remaining,
  }) {
    if (!_answerCurrent(capture) ||
        !identical(_questions?.correlation, capture._request)) {
      return;
    }
    final questions = _questions!;
    if (remaining == null || remaining.isEmpty) {
      _questions = null;
    } else {
      _questions = ChatQuestions(
        correlation: Object(),
        questions: questions.questions,
        answeredIds: questions.questions
            .map((q) => q.questionId)
            .whereType<String>()
            .where((id) => !remaining.contains(id)),
        lockedAnswers: {
          ...questions.lockedAnswers,
          ?questions.pending?.questionId: answer,
        },
      );
    }
  }

  void reportQuestionExpiry(ChatRuntimeAnswer capture) {
    if (!_answerCurrent(capture) ||
        capture._turn != _turn ||
        capture._events != _events ||
        (!capture.current && observation.needsInput)) {
      return;
    }
    _error = 'This input request expired. Your answer was not submitted again.';
  }

  void receiveSecure(GatewaySensitivePromptRequest request) {
    if (_closed) return;
    _revokeCommandPrompt();
    _secure = GatewaySensitivePromptRequest(
      kind: request.kind,
      requestId: request.requestId,
      title: request.title,
      description: request.description,
      fieldLabel: request.fieldLabel,
    );
    _secureResponding = false;
    _commandPreflight = _commandDispatchPending ? _secure : null;
  }

  ChatRuntimeAnswer beginSecureAnswer(GatewaySensitivePromptRequest expected) {
    if (_closed || !identical(expected, _secure)) {
      throw StateError('This request has changed. Review the current request.');
    }
    if (_secureResponding) {
      throw StateError('A response is already being submitted.');
    }
    _secureResponding = true;
    return ChatRuntimeAnswer._(this, _runtimeId, expected, _turn, _events);
  }

  void finishSecureAnswer(ChatRuntimeAnswer capture, {required bool accepted}) {
    if (!_answerCurrent(capture)) return;
    final continuation = _commandPrompt;
    if (continuation != null &&
        identical(continuation._preflight, capture._request)) {
      if (accepted) {
        continuation._accepted = true;
      } else {
        continuation._revoked = true;
      }
    }
    if (!identical(_secure, capture._request)) return;
    _secureResponding = false;
    if (accepted) {
      if (_recovery == ChatRecovery.reconnecting) {
        _recovery = ChatRecovery.ready;
      }
      _secure = null;
      _commandPreflight = null;
    }
  }

  void cancelRequest(Map<String, dynamic> data) {
    if (_closed) return;
    final id = data['id'];
    final method = data['method'];
    if (id is! String) return;
    if (method == 'approval') {
      for (final raw
          in _approvals.requests
              .where((r) => r['server_request_id'] == id)
              .toList()) {
        final rid = raw['request_id'] as String;
        _approvals.remove(rid);
        _approvalCorrelations.remove(rid);
      }
      if (data['reason'] == 'timeout') {
        _error = 'An approval expired before you responded.';
      }
    }
    if (method == 'clarify' && _questions?.pending?.requestId == id) {
      _questions = null;
    }
    if (_secure?.requestId == id &&
        GatewaySensitivePromptRequest.kindForMethod(
              method is String ? method : null,
            ) ==
            _secure?.kind) {
      _secure = null;
      _secureResponding = false;
      _commandPreflight = null;
      if (data['reason'] == 'timeout') {
        _error =
            'This secure input request expired. Ask Hermes to request it again.';
      }
    }
  }

  void reconcileOpenRequests(Object? value) {
    if (_closed || value is! List) return;
    final frames = value
        .whereType<Map>()
        .where(
          (r) => r['params'] is Map && r['params']['session_id'] == _runtimeId,
        )
        .toList();
    GatewaySensitivePromptRequest? next;
    for (final frame in frames) {
      next = GatewaySensitivePromptRequest.fromServerRequest(frame);
      if (next != null) break;
    }
    final sameSecure =
        next?.requestId == _secure?.requestId && next?.kind == _secure?.kind;
    if (!sameSecure && next != null) _revokeCommandPrompt();
    if (!sameSecure || !_secureResponding) _secure = next;
    if (!sameSecure) {
      _secureResponding = false;
      _commandPreflight = null;
    }
    final questionFrame = frames
        .where((r) => r['method'] == 'clarify')
        .firstOrNull;
    if (questionFrame == null) {
      _questions = null;
    } else {
      receiveQuestions({
        ...Map<String, dynamic>.from(questionFrame['params'] as Map),
        'request_id': questionFrame['id'],
      });
    }
  }

  /// Called only after the coordinator accepts a captured current resume read.
  bool installResume(Map<String, dynamic> result) {
    if (_closed) return false;
    final runtime = result['session_id'] as String;
    final changed = runtime != _runtimeId;
    final wasActive = observation.executionActive;
    if (changed) replaceRuntime(runtime);
    if (result['running'] == false) _compacting = false;
    _resume++;
    _main = ChatMainActivity.working;
    _mainTool = null;
    final inflight = result['inflight'] is Map
        ? result['inflight'] as Map
        : null;
    final failed = inflight?['status'] == 'error';
    _execution = failed
        ? ChatExecution.failed
        : result['running'] == true
        ? ChatExecution.running
        : wasActive
        ? ChatExecution.completed
        : _execution == ChatExecution.submitting
        ? ChatExecution.idle
        : _execution;
    _error = failed ? (inflight?['error']?.toString() ?? 'Turn failed') : null;
    final pending = result['pending_approval'];
    if (pending is Map) receiveApproval(Map<String, dynamic>.from(pending));
    if (result['open_requests'] is List) {
      for (final raw in (result['open_requests'] as List).whereType<Map>()) {
        if (raw['method'] != 'approval' ||
            raw['params'] is! Map ||
            raw['params']['session_id'] != runtime) {
          continue;
        }
        final params = Map<String, dynamic>.from(raw['params'] as Map);
        final id = params['request_id'];
        if (id is! String || id.isEmpty) continue;
        receiveApproval({
          ...params,
          'request_id': id,
          'server_request_id': raw['id'],
        });
      }
    }
    reconcileOpenRequests(result['open_requests']);
    return changed;
  }

  void dispose() {
    _closed = true;
    _revokeCommandPrompt();
    _read++;
    _approvalRead++;
  }
}
