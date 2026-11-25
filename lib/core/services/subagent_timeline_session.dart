import '../models/hermes_question.dart';
import '../models/operational_error.dart';
import '../models/canonical_session.dart';
import 'dart:async';
import 'dart:convert';
import '../models/transcript_notice.dart';
import '../models/turn_failure.dart';
import '../models/transcript_position.dart';

import 'package:flutter/foundation.dart';

import '../models/chat_runtime.dart';
import '../models/gateway_insight.dart';
import '../models/gateway_todo.dart';
import '../models/hermes_profile.dart';
import '../models/profile_session_key.dart';
import '../models/profile_supervision.dart';
import 'chat_runtime.dart';
import 'chat_transcript_events.dart';
import 'profile_gateway.dart';
import 'transcript_reading.dart';

/// A child-only reading visit. Canonical resume mounts a read-only subscription; it
/// never submits a prompt, changes the selected chat or claims child controls.
final class SubagentTimelineSession extends ChangeNotifier
    implements SubagentTimelineReader {
  SubagentTimelineSession({
    required this.scope,
    required this.parentSessionId,
    required this.subagentId,
    String? initialChildSessionId,
    required this._read,
    required this._isCurrent,
    this.onOperationalError,
  }) : _reading = TranscriptReading.passive(scope: scope),
       _liveChild = initialChildSessionId,
       _runtime = ChatRuntime(
         runtimeId: initialChildSessionId ?? parentSessionId,
       );

  final WorkspaceScope scope;
  final String parentSessionId, subagentId;
  final OperationalErrorReporter? onOperationalError;
  final ScopedRpc _read;
  final bool Function() _isCurrent;
  final TranscriptReading _reading;
  final ChatRuntime _runtime;
  List<Map<String, dynamic>> _rows = const [];
  final _agents = <String, GatewaySubagentActivity>{};
  GatewayTodoState _taskState = GatewayTodoState();
  String? _watch,
      _epoch,
      _liveError,
      _durableError,
      _cursor,
      _child,
      _liveChild;
  int _sequence = 0, _watchGeneration = 0, _depth = 0;
  int _completionRevision = 0;
  bool _closed = false,
      _active = false,
      _available = false,
      _unavailable = false;
  bool _loading = false, _paging = false, _partial = false, _running = false;
  bool _reconcile = false, _deferred = false, _latestShown = false;
  bool _refusalAwaitingHistory = false;
  bool _explicit = false, _durableReading = false;
  int _failures = 0, _liveFailures = 0;
  Timer? _timer, _liveTimer;
  Future<void>? _pending,
      _livePending,
      _queuedRefresh,
      _queuedOlder,
      _promotedLive;

  // Reading identity is the visit's captured authorization, not a rotating
  // physical segment. Only resourceKey grants resource reads.
  String get _readingId => '$parentSessionId/subagent/$subagentId';
  bool get _current => !_closed && _isCurrent();
  @override
  ProfileSessionKey? get resourceKey =>
      _child == null ? null : ProfileSessionKey(scope, _child!);
  @override
  ChatRuntimeObservation get runtime => _runtime.observation;
  @override
  Map<String, dynamic>? get streamingMessage => _reading.streamingMessage;
  @override
  List<GatewayTodo> get todos => _taskState.current(
    active: runtime.executionActive,
    turn: _runtime.turnRevision,
  );
  @override
  bool get liveAnswering =>
      runtime.executionActive || runtime.needsInput || _reconcile;
  @override
  String? get liveError => _liveError;
  @override
  String? get qualification {
    final notes = <String>[
      if (_deferred) 'Newer activity is available. Refresh to show it.',
      if (_latestShown) 'Showing the latest activity.',
      if (_rows.any((row) => row['truncated'] == true))
        'Some saved activity was shortened by Hermes.',
      if (_partial)
        'Earlier live activity is unavailable. Showing saved history and received updates.',
    ];
    return notes.isEmpty ? null : notes.join('\n');
  }

  @override
  void setActive(bool value) {
    _active = value;
    _timer?.cancel();
    _liveTimer?.cancel();
    if (value && _current) unawaited(_update());
  }

  @override
  Future<void> refresh() => _update(explicit: true);
  @override
  Future<void> loadOlder() => _update(older: true, explicit: true);

  Future<void> _update({bool older = false, bool explicit = false}) async {
    if (!_current || older && _cursor == null) return;
    if (_pending case final pending?) {
      if (explicit) {
        _explicit = true;
        _loading = true;
        _deferred = false;
        if (_liveFailures >= 3) {
          _promotedLive ??= _updateLive(explicit: true);
        }
        notifyListeners();
      }
      if (explicit && !older && !(_durableReading && !_paging)) {
        await (_queuedRefresh ??= _refreshAfterOlder(pending));
      } else if (older && !(_durableReading && _paging)) {
        await (_queuedOlder ??= _olderAfterRead(pending));
      } else {
        await pending;
      }
      return;
    }
    final done = Completer<void>();
    _pending = done.future;
    _explicit = explicit;
    if (explicit) _deferred = false;
    _loading = explicit || !_available && !_unavailable;
    _paging = older;
    _durableReading = !_deferred;
    if (_loading) notifyListeners();
    try {
      // Live polling has its own coalesced request/timer. A held multi-page
      // reconstruction cannot prevent received successor text/tools/tasks.
      await Future.wait([
        _updateLive(explicit: explicit),
        if (!_deferred) _readWindow(older: older),
      ]);
      if (_promotedLive case final live?) await live;
    } finally {
      _pending = null;
      _promotedLive = null;
      _loading = false;
      _paging = false;
      done.complete();
      if (_current) {
        notifyListeners();
        if (!(_running ||
            liveAnswering ||
            _refusalAwaitingHistory ||
            !_available && !_unavailable)) {
          _liveTimer?.cancel();
        }
        _timer?.cancel();
        if (_active &&
            _failures < 3 &&
            !_deferred &&
            (_running ||
                liveAnswering ||
                _refusalAwaitingHistory ||
                !_available)) {
          _timer = Timer(const Duration(seconds: 1), _update);
        }
      }
    }
  }

  Future<void> _refreshAfterOlder(Future<void> pending) async {
    await pending;
    // Transfer intent before dispatch: another queued kind may start first,
    // and reentering must never await this helper's own future.
    _queuedRefresh = null;
    if (_current) await _update(explicit: true);
  }

  Future<void> _olderAfterRead(Future<void> pending) async {
    await pending;
    _queuedOlder = null;
    if (_current) await _update(older: true, explicit: true);
  }

  Future<void> _updateLive({bool explicit = false}) async {
    if (!_current || _liveChild == null || !explicit && _liveFailures >= 3) {
      return;
    }
    if (_livePending case final pending?) return pending;
    final generation = _watchGeneration;
    final done = Completer<void>();
    _livePending = done.future;
    try {
      if (_watch == null) await _mount();
      if (!_current || generation != _watchGeneration) return;
      if (_watch != null) await _replay();
      if (!_current || generation != _watchGeneration) return;
      _liveError = null;
      _liveFailures = 0;
      _reportReadOutcome('subagent-timeline', true);
    } catch (_) {
      if (!_current || generation != _watchGeneration) return;
      _liveFailures++;
      _liveError =
          'Live subagent activity could not refresh. Retry to continue.';
      _reportReadOutcome('subagent-timeline', false);
    } finally {
      _livePending = null;
      done.complete();
      if (_current) {
        notifyListeners();
        _liveTimer?.cancel();
        if (generation != _watchGeneration && _liveChild != null) {
          // Rotation retires the old response, then starts the current watch.
          unawaited(_updateLive());
        } else if (_active &&
            _liveFailures < 3 &&
            (_running || liveAnswering || !_available && !_unavailable)) {
          _liveTimer = Timer(const Duration(seconds: 1), _updateLive);
        }
      }
    }
  }

  void _reportReadOutcome(String source, bool? succeeded) {
    if (succeeded == null) return;
    onOperationalError?.call(
      OperationalErrorObservation(
        connectionIdentity: scope.connectionIdentity,
        profileName: scope.profileName,
        operation: '$source:${scope.profileName}:$subagentId',
        title: 'Subagent activity unavailable',
        error: succeeded ? null : 'Open the subagent and refresh its activity.',
      ),
    );
  }

  Future<void> _mount({String? expectedEpoch, bool skipMissing = false}) async {
    final target = _liveChild;
    if (target == null) return;
    final generation = _watchGeneration;
    final response = await _read('session.resume', {
      'session_id': target,
      'display_projection': true,
    });
    if (!_current || generation != _watchGeneration) return;
    final cursor = CanonicalReplayCursor.fromSnapshot(
      response,
      expectedSessionId: target,
      expectedEpoch: expectedEpoch,
    );
    _watch = cursor.sessionId;
    _epoch = cursor.epoch;
    _sequence = skipMissing ? cursor.sequence : 0;
    _runtime.replaceRuntime(cursor.sessionId);
    _runtime.observeExecutionSnapshot(response);
  }

  Future<void> _readWindow({required bool older}) async {
    final completion = _completionRevision;
    final pages = older ? 1 : (_depth == 0 ? 1 : _depth);
    var cursor = older ? _cursor : null;
    String? child = older ? _child : null;
    var staged = <Map<String, dynamic>>[];
    var loaded = 0;
    var running = false;
    try {
      for (var page = 0; page < pages; page++) {
        final response = await _read('session.transcript', {
          'session_id': parentSessionId,
          'subagent_id': subagentId,
          'order': 'latest',
          'limit': 100,
          'cursor': ?cursor,
        });
        if (!_current) return;
        final parsed = _TranscriptPage.parse(
          response,
          parent: parentSessionId,
          subagent: subagentId,
        );
        if (!parsed.available) {
          // Unavailability is authority, not an empty successful transcript.
          _commitUnavailable(parsed.running);
          _durableError = null;
          _failures = 0;
          _reportReadOutcome('subagent-history', true);
          return;
        }
        if (cursor != null && parsed.reset ||
            child != null && child != parsed.child) {
          throw const _HistoryChanged();
        }
        child = parsed.child;
        running = parsed.running;
        if (parsed.cursor != null && parsed.cursor == cursor) {
          throw const FormatException('Repeated transcript cursor');
        }
        staged = [...parsed.rows, ...staged];
        _checkRowIdentities([...staged, if (older) ..._rows]);
        cursor = parsed.cursor;
        loaded++;
        if (cursor == null) break;
      }
      // A refusal can rewrite already saved rows. A read dispatched before
      // that completion cannot replace its live projection with stale storage.
      if (_refusalAwaitingHistory && completion != _completionRevision) return;
      final next = [...staged, if (older) ..._rows];
      final keepsBookmark = _reading.windowContainsReadingBookmark(next);
      if (!older && !_explicit && !keepsBookmark) {
        _deferred = true;
        return;
      }
      _latestShown = !older && !keepsBookmark;
      if (_latestShown) _reading.recordReading(null);
      _rows = List.unmodifiable(next);
      _cursor = cursor;
      _depth = older ? _depth + loaded : loaded;
      _running = running;
      _available = true;
      _unavailable = false;
      _deferred = false;
      _reading.replaceSavedWindow(
        ProfileHistoryPage(
          _readingId,
          _rows,
          0,
          _rows.length,
          isComplete: cursor == null,
        ),
      );
      _child = child;
      _bindLiveChild(child);
      // Reconcile only a completion that preceded this read. A successor or
      // completion arriving during staging must retain its independent stream.
      if (_reconcile &&
          completion == _completionRevision &&
          (_refusalAwaitingHistory ||
              streaming.isEmpty ||
              _rows.any(
                (row) =>
                    row['role'] == 'assistant' && row['content'] == streaming,
              ))) {
        _reading.updateStreaming('');
        _runtime.reconcileHistoricalActivity();
        _reconcile = false;
      }
      if (completion == _completionRevision) _refusalAwaitingHistory = false;
      _durableError = null;
      _failures = 0;
      _reportReadOutcome('subagent-history', true);
    } catch (error) {
      if (!_current) return;
      _failures++;
      _durableError = error is _HistoryChanged
          ? 'Saved activity changed during the read. Refresh to show it.'
          : 'Saved subagent activity could not refresh. Retry to continue.';
      _reportReadOutcome('subagent-history', false);
    } finally {
      _durableReading = false;
      if (_current) notifyListeners();
    }
  }

  void _bindLiveChild(String? child) {
    if (_liveChild == child) return;
    final replacing = _liveChild != null;
    _liveChild = child;
    if (replacing && child != null) {
      // A physical continuation is a new replay authority. Old live facts stay
      // readable while staging, then retire together at this durable commit.
      _runtime.replaceRuntime(child);
      _reading.retireLiveObservation();
      _agents.clear();
      _taskState = GatewayTodoState();
      _reconcile = false;
      _refusalAwaitingHistory = false;
      _completionRevision++;
      _partial = true;
    }
    _watchGeneration++;
    _watch = null;
    _epoch = null;
    _sequence = 0;
    _liveFailures = 0;
    _liveError = null;
    _liveTimer?.cancel();
    if (child != null && _livePending == null) unawaited(_updateLive());
  }

  void _commitUnavailable(bool running) {
    _rows = const [];
    _cursor = null;
    _depth = 0;
    _child = null;
    _available = false;
    _unavailable = true;
    _running = running;
    _deferred = false;
    _latestShown = false;
    _reading.replaceSavedWindow(
      ProfileHistoryPage(_readingId, const [], 0, 0, isComplete: true),
    );
    // Already received live data and its independent watch remain usable.
  }

  static void _checkRowIdentities(Iterable<Map<String, dynamic>> rows) {
    final seen = <Object>{};
    for (final row in rows) {
      final id = row['id'];
      if (id != null && !seen.add(id)) {
        throw const FormatException('Repeated transcript row');
      }
    }
  }

  Future<void> _replay() async {
    final generation = _watchGeneration;
    bool current() => _current && generation == _watchGeneration;
    Future<Map<String, dynamic>> readReplay() => _read('session.events.since', {
      'session_id': _watch,
      'replay_epoch': _epoch,
      'last_sequence': _sequence,
    });
    var replay = await readReplay();
    if (!current()) return;
    final epoch = replay['replay_epoch'];
    if (epoch is! String || epoch.isEmpty) {
      throw const FormatException('Missing child replay epoch');
    }
    if (epoch != _epoch) {
      _partial = true;
      _reconcile = false;
      _refusalAwaitingHistory = false;
      _agents.clear();
      _taskState = GatewayTodoState();
      await _mount(expectedEpoch: epoch);
      if (!current()) return;
      _reading.updateStreaming('');
      replay = await readReplay();
      if (!current()) return;
    }
    if (replay['replay_epoch'] != _epoch) {
      throw const FormatException('Child replay changed during refresh');
    }
    if (replay['snapshot_required'] is! bool || replay['truncated'] is! bool) {
      throw const FormatException('Missing canonical replay continuity');
    }
    if (replay['snapshot_required'] == true || replay['truncated'] == true) {
      _partial = true;
      _reconcile = false;
      _refusalAwaitingHistory = false;
      _agents.clear();
      _taskState = GatewayTodoState();
      await _mount(expectedEpoch: _epoch, skipMissing: true);
      if (!current()) return;
      _reading.updateStreaming('');
      return;
    }
    final events = replay['events'];
    final latest = replay['latest_seq'];
    if (events is! List ||
        latest is! int ||
        latest < _sequence ||
        replay['replay_epoch'] is! String ||
        replay['truncated'] is! bool) {
      throw const FormatException('Invalid child replay');
    }
    final received = <Map<String, dynamic>>[];
    var last = _sequence;
    for (final event in events) {
      if (event is! Map<String, dynamic> ||
          event['session_id'] != _watch ||
          event['seq'] is! int ||
          event['type'] is! String ||
          event['payload'] != null &&
              event['payload'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid child event');
      }
      final seq = event['seq'] as int;
      if (seq <= _sequence) continue;
      if (seq <= last || seq > latest) {
        throw const FormatException('Unordered child replay');
      }
      received.add(event);
      last = seq;
    }
    _partial |= replay['truncated'] == true;
    for (final event in received) {
      final type = event['type'] as String;
      final generation = event['execution_generation'];
      final data = event['payload'] as Map<String, dynamic>? ?? const {};
      if (type == 'message.start') {
        _completionRevision++;
        // A successor still needs the post-refusal history refresh, but that
        // read must not retire its live stream or activity.
        _reconcile = false;
      }
      if (data['turn_id'] is String &&
          type != 'message.complete' &&
          type != 'turn.end') {
        _reading.observeReplyAdmission(
          event['admission_id'],
          turn: data['turn_id'],
        );
      }
      _observeWork(type, data);
      // Mirrored tools have synthetic IDs and preview-only payloads. Do not
      // start a stopwatch from a replayed or inferred lifecycle boundary.
      if (type == 'tool.start' || type == 'tool.complete') {
        final mirrored =
            data['tool_id'] is String &&
            (data['tool_id'] as String).startsWith('submirror:');
        final tool = _runtime.observeTool(
          type,
          mirrored
              ? {
                  for (final entry in data.entries)
                    if (entry.key != 'args' && entry.key != 'duration_s')
                      entry.key: entry.value,
                  if (data['preview'] is String) 'context': data['preview'],
                }
              : data,
          live: false,
        );
        if (tool != null) _reading.observeTool(tool);
      } else {
        applyChatTranscriptEvent(
          runtime: _runtime,
          reading: _reading,
          type: type,
          data: data,
          live: false,
        );
      }
      if (type == 'message.complete' || type == 'turn.end') {
        final refused = isContentRefusedCompletion(data);
        if (refused &&
            _reading.isSupersededReplyCompletion(data, event['admission_id'])) {
          continue;
        }
        _completionRevision++;
        final refusalFailure = refused
            ? TurnFailure.fromCompletion(data)
            : null;
        _runtime.completeTurn(
          failed: data['status'] == 'error',
          cancelled: data['status'] == 'interrupted',
          error: refusalFailure?.message ?? data['error']?.toString(),
          failure: refusalFailure,
          executionGeneration: generation is int ? generation : null,
        );
        // Keep the received reply until its saved replacement is available.
        final text = data['text']?.toString();
        if (refused) {
          _reading.refuseReply(data, admission: event['admission_id']);
          _reading.updateStreaming('');
          _runtime.finishActivity();
        } else if (text != null && text.isNotEmpty) {
          _reading.updateStreaming(text);
        }
        _refusalAwaitingHistory = refused;
        _reconcile = true;
      } else if (type == 'error' || type == 'turn.error') {
        _runtime.failTurn(
          data['message']?.toString() ?? 'Subagent failed',
          executionGeneration: generation is int ? generation : null,
        );
      } else if (type == 'session.info') {
        _runtime.observeExecutionSnapshot(data);
      }
    }
    _epoch = replay['replay_epoch'] as String;
    _sequence = latest;
  }

  void _observeWork(String type, Map<String, dynamic> data) {
    final agent = GatewaySubagentActivity.fromGatewayEvent(type, data);
    if (agent != null) {
      _agents[agent.id] = _agents[agent.id]?.merge(agent) ?? agent;
    }
    if (type == 'todo.updated') {
      final next = GatewayTodoSnapshot.parse(data);
      if (next != null) {
        _taskState.observe(
          next,
          liveTurn: runtime.executionActive ? _runtime.turnRevision : null,
        );
      }
    }
  }

  @override
  ProfileSupervisionObservation get state => ProfileSupervisionObservation(
    key: ProfileSessionKey(scope, _readingId),
    subagents: _agents.values,
    unconfirmedSubagentIds: const {},
    subagentsLoading: false,
    subagentsAvailable: _available,
    subagentsError: null,
    sessionControl: null,
    sessionControlLoading: false,
    sessionControlWorking: false,
    sessionControlError: null,
    sessionControlNotice: null,
    processes: const [],
    processesLoading: false,
    processesError: null,
    inlineProcessesError: null,
    actionBusy: false,
    actionError: null,
    stopping: const {},
    processErrors: const {},
  );
  @override
  Future<void> refreshSubagents() => refresh();
  @override
  SubagentInspectionDetail openSubagent(String id) {
    final initial = _agents[id];
    if (initial == null) throw StateError('Subagent is no longer available');
    return ReadOnlySubagentDetail(
      owner: this,
      activity: () => _agents[id] ?? initial,
      unconfirmed: () =>
          !_agents.containsKey(id) ||
          _liveError != null ||
          _durableError != null,
      createTimeline: (child) => SubagentTimelineSession(
        onOperationalError: onOperationalError,
        scope: scope,
        parentSessionId: parentSessionId,
        subagentId: child.id,
        initialChildSessionId: child.childSessionId,
        read: _read,
        isCurrent: () => _current,
      ),
    );
  }

  @override
  Iterable<PositionedHermesQuestion> get requestActivities =>
      _reading.requestActivities;
  @override
  List<Map<String, dynamic>> get messages => _reading.messages;
  @override
  String get streaming => _reading.streaming;
  @override
  String? get historySessionId => _readingId;
  @override
  int? get nextHistoryOffset => _cursor == null ? null : _rows.length;
  @override
  bool get historyLoading => _loading;
  @override
  bool get historyAvailable => _available;
  @override
  bool get historyPaging => _paging;
  @override
  String? get historyError => _durableError;
  @override
  bool get historyUnavailable => _unavailable;
  @override
  TranscriptPosition get readingPosition => _reading.readingPosition;
  @override
  Object messagePresentationId(Map<String, dynamic> row) =>
      _reading.messagePresentationId(row);
  @override
  void recordReading(TranscriptBookmark? resume, {int? readThrough}) {
    _reading.recordReading(resume, readThrough: readThrough);
    if (resume == null && _deferred && _current) {
      _deferred = false;
      scheduleMicrotask(() {
        if (_current) unawaited(refresh());
      });
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _liveTimer?.cancel();
    _reading.dispose();
    _runtime.dispose();
    super.dispose();
  }
}

/// Read-only detail used by worker history and nested child timelines.
final class ReadOnlySubagentDetail extends ChangeNotifier
    implements SubagentInspectionDetail {
  ReadOnlySubagentDetail({
    required this._owner,
    required this._activity,
    required this._unconfirmed,
    required SubagentTimelineSession Function(GatewaySubagentActivity)
    createTimeline,
  }) : timeline = createTimeline(_activity()) {
    _owner.addListener(_changed);
  }
  final Listenable _owner;
  final GatewaySubagentActivity Function() _activity;
  final bool Function() _unconfirmed;
  void _changed() => notifyListeners();
  @override
  final SubagentTimelineSession timeline;
  @override
  SubagentSupervisionObservation get state => SubagentSupervisionObservation(
    activity: _activity(),
    unconfirmed: _unconfirmed(),
    canControl: false,
    acceptsSteer: false,
    steering: false,
    interrupting: false,
    controlMessage: null,
    controlFailed: false,
  );
  @override
  void setActive(bool value) => timeline.setActive(value);
  @override
  Future<bool> steer(String text) async => false;
  @override
  Future<void> interrupt() async {}
  @override
  void dispose() {
    _owner.removeListener(_changed);
    timeline.dispose();
    super.dispose();
  }
}

final class _HistoryChanged implements Exception {
  const _HistoryChanged();
}

/// Stock session.transcript's child response, decoded inside the visit owner.
/// Row kind namespaces presentation IDs; wire row_id remains available unchanged.
final class _TranscriptPage {
  const _TranscriptPage(
    this.rows,
    this.cursor,
    this.child,
    this.available,
    this.running,
    this.reset,
  );
  final List<Map<String, dynamic>> rows;
  final String? cursor, child;
  final bool available, running, reset;

  factory _TranscriptPage.parse(
    Map<String, dynamic> value, {
    required String parent,
    required String subagent,
  }) {
    final raw = value['rows'];
    final cursor = value['next_cursor'];
    final child = value['child_session_id'];
    final available = value['available'];
    final running = value['running'];
    final reset = value['reset'];
    if (value['session_id'] != parent ||
        value['subagent_id'] != subagent ||
        available is! bool ||
        running is! bool ||
        reset is! bool ||
        raw is! List ||
        raw.length > 164 ||
        !value.containsKey('next_cursor') ||
        cursor != null && (cursor is! String || cursor.isEmpty) ||
        (available
            ? child is! String || child.isEmpty
            : child != null || raw.isNotEmpty || cursor != null || !reset) ||
        utf8.encode(jsonEncode(raw)).length > 2 * 1024 * 1024) {
      throw const FormatException('Invalid child transcript page');
    }
    final rows = <Map<String, dynamic>>[];
    for (final row in raw) {
      if (row is! Map<String, dynamic> ||
          !const ['message', 'compaction'].contains(row['row_kind']) ||
          row['role'] is! String ||
          (row['role'] as String).isEmpty ||
          row['row_id'] != null && row['row_id'] is! int ||
          row['text'] != null && row['text'] is! String ||
          row['truncated'] != null && row['truncated'] is! bool ||
          row['compacted_messages'] != null &&
              (row['compacted_messages'] is! int ||
                  (row['compacted_messages'] as int) < 0) ||
          row['row_kind'] == 'compaction' && row['role'] != 'system') {
        throw const FormatException('Invalid child transcript row');
      }
      final id = row['row_id'];
      final compaction = row['row_kind'] == 'compaction';
      final text = row['text'] as String? ?? '';
      final count = row['compacted_messages'];
      rows.add({
        ...row,
        if (id != null) 'id': compaction ? 'compaction:$id' : id,
        'content': row['role'] == 'tool' ? row['content'] ?? text : text,
        'display_content': compaction && count != null
            ? '$count messages summarized\n\n$text'
            : text,
      });
    }
    SubagentTimelineSession._checkRowIdentities(rows);
    return _TranscriptPage(
      List.unmodifiable(rows),
      cursor as String?,
      child as String?,
      available,
      running,
      reset,
    );
  }
}
