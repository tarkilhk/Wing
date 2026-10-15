import 'chat_transcript_events.dart';
import 'dart:async';
import '../models/chat_runtime.dart';
import '../models/gateway_insight.dart';
import '../models/gateway_todo.dart';
import '../models/hermes_profile.dart';
import '../models/profile_session_key.dart';
import '../models/profile_supervision.dart';
import 'chat_runtime.dart';
import 'profile_supervision_session.dart';
import 'transcript_reading.dart';
import 'package:flutter/foundation.dart';
import '../models/bots.dart';
import '../models/transcript_reader.dart';
import '../models/transcript_timeline.dart';
import 'bots_repository.dart';
import 'profile_gateway.dart';

/// One passive inspection route. Polls stock observations; never admits commands.
class BotGroupHistorySession extends ChangeNotifier
    implements SubagentInspectionSession {
  BotGroupHistorySession(this.repository, this.group) {
    repository.retain();
    _reading = _newReading(null);
  }

  final BotsRepository repository;
  final BotGroup group;
  BotGroupMember? _member;
  BotGroupMember? get member => _member;
  late _BotGroupHistoryReading _reading;
  TranscriptReader get reader => _reading;
  bool get historyAvailable => _reading._available;
  final _savedReadings = <(String, String), _BotGroupHistoryReading>{};
  bool _closed = false;
  int _generation = 0;

  Timer? _poll;
  bool _visible = false;
  int _liveGeneration = 0;
  ChatRuntimeObservation get runtime => _reading._runtime.observation;
  Map<String, dynamic>? get streamingMessage =>
      _reading._reading.streamingMessage;
  List<GatewayTodo> get todos => _reading._todos;
  List<GatewaySubagentActivity> get subagents =>
      List.unmodifiable(_reading._agents.values);
  String? get liveError => _reading._liveError;
  ProfileSessionKey? get key => _reading._session == null
      ? null
      : ProfileSessionKey(_reading._reading.scope, _reading._session!);
  bool get liveAnswering => runtime.executionActive || runtime.needsInput;

  _BotGroupHistoryReading _newReading(BotGroupMember? member) =>
      _BotGroupHistoryReading(
        WorkspaceScope(
          connectionId: repository.scope.connectionId,
          connectionIdentity: repository.scope.connectionIdentity,
          profileName: member?.profile ?? repository.scope.profileName,
        ),
      );

  void setVisible(bool value) {
    _visible = value;
    _schedulePoll();
  }

  void _schedulePoll() {
    _poll?.cancel();
    _poll = null;
    if (_closed || !_visible) return;
    final working =
        liveAnswering ||
        liveError == null && subagents.any((agent) => !agent.isTerminal);
    _poll = Timer(Duration(milliseconds: working ? 500 : 3000), () async {
      await refreshLive(discover: true);
      _schedulePoll();
    });
  }

  /// Coalesced read-only replay, scoped to the selected durable worker identity.
  Future<void> refreshLive({bool discover = false}) async {
    final member = _member;
    final reading = _reading;
    if (_closed || member == null || reading._loading && !reading._available) {
      return;
    }
    if (reading._session == null) {
      if (!discover) return;
      await _load(refresh: true, quiet: true);
      if (_closed ||
          !identical(reading, _reading) ||
          reading._session == null) {
        return;
      }
    }
    if (reading._livePending case final pending?) return pending;
    final generation = _liveGeneration;
    bool current() =>
        !_closed &&
        generation == _liveGeneration &&
        identical(reading, _reading);
    final done = Completer<void>();
    reading._livePending = done.future;
    repository.retain();
    try {
      final response = await repository.groupMemberObservation(
        group,
        member,
        'session.active_list',
        {},
      );
      if (!current()) return;
      final rows = response['sessions'];
      if (rows is! List) {
        throw const FormatException('Missing active worker list');
      }
      final matches = rows
          .whereType<Map>()
          .where(
            (row) =>
                row['session_key'] == reading._session &&
                row['title'] == 'Group: ${group.id}',
          )
          .toList();
      if (matches.length > 1) {
        throw const FormatException('Ambiguous worker runtime');
      }
      final live = matches.firstOrNull;
      if (live == null) {
        if (discover ||
            runtime.executionActive ||
            reading._reading.streaming.isNotEmpty) {
          await _load(refresh: true, quiet: true);
          if (!current()) return;
          reading._runtime.observeExecutionSnapshot({'running': false});
          reading._reading.updateStreaming('');
          reading._partialLive = false;
          reading._runtime.reconcileHistoricalActivity();
        }
        reading._liveError = null;
        return;
      }
      final id = live['id'];
      final status = live['status'];
      if (id is! String ||
          id.isEmpty ||
          !const {'working', 'starting', 'waiting', 'idle'}.contains(status)) {
        throw const FormatException('Invalid worker runtime');
      }
      if (id != reading._runtimeId) {
        reading._runtimeId = id;
        reading._sequence = 0;
        reading._epoch = null;
        reading._partialLive = false;
        reading._runtime.replaceRuntime(id);
        reading._reading.updateStreaming('');
      }
      var replay = await repository.groupMemberObservation(
        group,
        member,
        'session.events.since',
        {'session_id': id, 'last_seen': reading._sequence},
      );
      if (!current()) return;
      final epoch = replay['epoch'];
      if (epoch is! String || epoch.isEmpty) {
        throw const FormatException('Missing worker replay epoch');
      }
      if (reading._epoch != null && reading._epoch != epoch) {
        reading._sequence = 0;
        reading._runtime.replaceRuntime(id);
        reading._reading.updateStreaming('');
        replay = await repository.groupMemberObservation(
          group,
          member,
          'session.events.since',
          {'session_id': id, 'last_seen': 0},
        );
        if (!current()) return;
      }
      final events = replay['events'];
      final latest = replay['latest_seq'];
      if (events is! List ||
          latest is! int ||
          latest < 0 ||
          replay['truncated'] is! bool) {
        throw const FormatException('Invalid worker replay');
      }
      final received = <Map<String, dynamic>>[];
      var last = reading._sequence;
      for (final event in events) {
        if (event is! Map<String, dynamic> ||
            event['session_id'] != id ||
            event['type'] is! String ||
            (event['payload'] != null &&
                event['payload'] is! Map<String, dynamic>) ||
            event['seq'] is! int) {
          throw const FormatException('Invalid worker event');
        }
        final seq = event['seq'] as int;
        if (seq <= reading._sequence) continue;
        if (seq <= last || seq > latest) {
          throw const FormatException('Unordered worker replay');
        }
        received.add(event);
        last = seq;
      }
      final cold = reading._sequence == 0;
      final start = received.lastIndexWhere(
        (e) => e['type'] == 'message.start',
      );
      if (replay['truncated'] == true && (!cold || start < 0)) {
        reading._partialLive = true;
      }
      final wasActive = runtime.executionActive;
      var terminal = false;
      for (var index = 0; index < received.length; index++) {
        final event = received[index];
        final type = event['type'] as String;
        final data = event['payload'] as Map<String, dynamic>? ?? const {};
        reading.observeWork(type, data);
        if (cold && (status == 'idle' || index < start)) continue;
        if (type == 'message.start') {
          reading._partialLive = false;
          terminal = false;
        }
        terminal |= reading.observeExecution(type, data);
      }
      reading._epoch = replay['epoch'] as String;
      reading._sequence = latest;
      reading._runtime.reconcileOpenRequests(replay['open_requests']);
      if (!terminal) {
        reading._runtime.observeExecutionSnapshot({
          'running': status != 'idle',
        });
      }
      if (terminal ||
          status == 'idle' &&
              (wasActive || reading._reading.streaming.isNotEmpty)) {
        await _load(refresh: true, quiet: true);
        if (!current()) return;
        if (reading._error == null) {
          reading._reading.updateStreaming('');
          reading._partialLive = false;
          reading._runtime.reconcileHistoricalActivity();
        }
      }
      reading._liveError = reading._partialLive
          ? 'Earlier live activity is unavailable. Showing saved history and received updates.'
          : null;
    } catch (_) {
      if (current()) {
        reading._liveError =
            'Live activity could not refresh. Refresh to try again.';
      }
    } finally {
      repository.release();
      reading._livePending = null;
      done.complete();
      if (current()) notifyListeners();
    }
  }

  @override
  Future<void> refreshSubagents() => refreshLive();

  @override
  ProfileSupervisionObservation get state => ProfileSupervisionObservation(
    key: key ?? ProfileSessionKey(repository.scope, ''),
    subagents: subagents,
    unconfirmedSubagentIds: liveError == null
        ? const {}
        : subagents.map((a) => a.id),
    subagentsLoading: _reading._livePending != null,
    subagentsAvailable: _reading._epoch != null,
    subagentsError: liveError,
    sessionControl: null,
    sessionControlLoading: false,
    sessionControlWorking: false,
    sessionControlError: null,
    sessionControlNotice: null,
    processes: const [],
    processesLoading: false,
    processesError: null,
    actionBusy: false,
    actionError: null,
    stopping: const {},
    processErrors: const {},
  );

  @override
  SubagentInspectionDetail openSubagent(String id) => _WorkerSubagentDetail(
    this,
    subagents.firstWhere((agent) => agent.id == id),
  );

  Future<void> select(BotGroupMember member) async {
    if (_closed) return;
    ++_generation;
    ++_liveGeneration;
    _member = member;
    _reading =
        _savedReadings[(member.id, member.profile)] ?? _newReading(member);
    final reading = _reading;
    reading._explicitRead = true;
    notifyListeners();
    try {
      if (!reading._available) await _load(refresh: true);
      // The screen admits initial live enrichment after its first readable
      // frame; selecting saved history must never await that independent read.
    } finally {
      reading._explicitRead = false;
      if (!_closed && identical(reading, _reading)) {
        notifyListeners();
        _schedulePoll();
      }
    }
  }

  Future<void> refresh() async {
    if (_closed || _reading.historyLoading || _member == null) return;
    final reading = _reading;
    reading._explicitRead = true;
    notifyListeners();
    try {
      await _load(refresh: true);
      if (!_closed && identical(reading, _reading)) await refreshLive();
    } finally {
      reading._explicitRead = false;
      if (!_closed && identical(reading, _reading)) {
        notifyListeners();
        _schedulePoll();
      }
    }
  }

  Future<void> loadOlder() async {
    if (_closed || _reading._loading || _reading._older == null) return;
    await _load(refresh: false);
  }

  Future<void> _load({required bool refresh, bool quiet = false}) async {
    final member = _member!;
    final reading = _reading;
    final generation = ++_generation;
    final initial = refresh && !reading._available;
    // Only settled successful readings can be borrowed by another selection.
    _savedReadings.remove((member.id, member.profile));
    reading._loading = !quiet;
    reading._paging = !refresh;
    reading._error = null;
    notifyListeners();
    repository.retain();
    try {
      final session = refresh
          ? await repository.groupMemberSession(group, member)
          : reading._session;
      if (_closed || generation != _generation) return;
      if (session == null) {
        reading._session = null;
        reading._older = null;
        reading._reading.installSavedHistory(const []);
        reading._available = true;
        return;
      }
      // Raw pages can contain only invisible assistant calls and folded tools.
      // Stage the full read before replacing a previously readable snapshot.
      final rows = <int, Map<String, dynamic>>{};
      var offset = refresh ? 0 : reading._older!;
      int? older;
      do {
        final page = await repository.groupMemberHistory(
          group,
          member,
          session,
          offset,
        );
        if (_closed || generation != _generation) return;
        final pageIds = <int>{};
        for (final row in page.rows) {
          final id = row['id'];
          if (id is! int || !pageIds.add(id)) {
            throw const FormatException('Invalid worker history row');
          }
          rows[id] = Map.unmodifiable(row);
        }
        older = page.nextOffset;
        if (initial) {
          // Publish each received page before waiting on older messages. The
          // transcript renders their Activity lazily while backfill continues.
          reading.installNewestPage(session, rows, older);
          notifyListeners();
        }
        if (older == null ||
            !refresh ||
            quiet ||
            _conversationCount(rows) >= 20) {
          break;
        }
        if (older <= offset) {
          throw const FormatException('Invalid worker history cursor');
        }
        offset = older;
      } while (true);
      if (refresh) {
        reading.installNewestPage(session, rows, older);
      } else {
        final merged = <int, Map<String, dynamic>>{
          for (final row in reading.messages)
            if (row['id'] is int) row['id'] as int: row,
          ...rows,
        };
        reading._reading.installSavedHistory([
          for (final id in merged.keys.toList()..sort()) merged[id]!,
        ]);
      }
      reading.restoreWork();
      reading._session = session;
      reading._older = older;
      reading._available = true;
    } catch (_) {
      if (!_closed && generation == _generation) {
        reading._error =
            'Working history could not load. Refresh to try again.';
      }
    } finally {
      repository.release();
      if (!_closed && generation == _generation) {
        reading._loading = false;
        reading._paging = false;
        if (reading._available && reading._error == null) {
          _savedReadings[(member.id, member.profile)] = reading;
        }
        notifyListeners();
      }
    }
  }

  static int _conversationCount(Map<int, Map<String, dynamic>> rows) {
    final timeline = TranscriptTimeline.project([
      for (final id in rows.keys.toList()..sort()) rows[id]!,
    ], presentationId: (row) => row['id'] as int);
    return timeline.sections
        .where((section) => !section.isActivity)
        .expand((section) => section.messages)
        .where((entry) => entry.role == 'user' || entry.role == 'assistant')
        .length;
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    ++_liveGeneration;
    ++_generation;
    for (final reading in {..._savedReadings.values, _reading}) {
      reading._runtime.dispose();
      reading._reading.dispose();
    }
    _savedReadings.clear();
    repository.release();
    super.dispose();
  }
}

/// Each member keeps its saved rows and scroll memory for this inspection visit.
/// It holds saved facts only; all I/O remains in BotGroupHistorySession.
final class _BotGroupHistoryReading implements TranscriptReader {
  _BotGroupHistoryReading(WorkspaceScope scope)
    : _reading = TranscriptReading.passive(scope: scope),
      _runtime = ChatRuntime(runtimeId: '');
  final TranscriptReading _reading;
  final ChatRuntime _runtime;
  Future<void>? _livePending;
  String? _runtimeId, _epoch, _liveError;
  int _sequence = 0;
  bool _partialLive = false;
  int? _todoRevision;
  bool _receivedLiveTodos = false;
  List<GatewayTodo> _todos = const [];
  final _agents = <String, GatewaySubagentActivity>{};

  void observeWork(String type, Map<String, dynamic> data) {
    if (type == 'todo.updated') {
      final next = GatewayTodoSnapshot.parse(data);
      if (next != null &&
          (next.revision == null ||
              _todoRevision == null ||
              next.revision! >= _todoRevision!)) {
        _todos = List.unmodifiable(next.todos);
        _todoRevision = next.revision;
        _receivedLiveTodos = true;
      }
    }
    final agent = GatewaySubagentActivity.fromGatewayEvent(type, data);
    if (agent != null) {
      _agents[agent.id] = _agents[agent.id]?.merge(agent) ?? agent;
    }
  }

  void installNewestPage(
    String session,
    Map<int, Map<String, dynamic>> rows,
    int? older,
  ) {
    _reading.installSavedPage(
      ProfileHistoryPage(
        session,
        [for (final id in rows.keys.toList()..sort()) rows[id]!],
        0,
        rows.length,
        isComplete: older == null,
      ),
    );
    _session = session;
    _older = older;
    _available = true;
  }

  void restoreWork() {
    // History backfill can finish after a newer live snapshot. These older
    // receipts must not replace that snapshot, including an empty live list.
    if (_receivedLiveTodos) return;
    final todoCalls = <String>{};
    for (final row in messages) {
      if (row['tool_calls'] case final List calls) {
        for (final call in calls.whereType<Map>()) {
          if (call['function'] is Map &&
              call['function']['name'] == 'todo_list' &&
              call['id'] is String) {
            todoCalls.add(call['id'] as String);
          }
        }
      }
      if (row['role'] == 'tool' &&
          (todoCalls.contains(row['tool_call_id']) ||
              row['tool_name'] == 'todo_list')) {
        final snapshot = GatewayTodoSnapshot.parse(row['content']);
        if (snapshot != null &&
            (_todoRevision == null ||
                snapshot.revision == null ||
                snapshot.revision! >= _todoRevision!)) {
          _todos = List.unmodifiable(snapshot.todos);
          _todoRevision = snapshot.revision;
        }
      }
    }
  }

  bool observeExecution(String type, Map<String, dynamic> data) {
    _runtime.observeEvent(type, data);
    applyChatTranscriptEvent(
      runtime: _runtime,
      reading: _reading,
      type: type,
      data: data,
    );
    switch (type) {
      case 'session.info':
        _runtime.observeExecutionSnapshot(data);
      case 'status.update':
        break;
      case 'message.complete':
      case 'turn.end':
        if (!_runtime.observation.executionActive) return true;
        final failed = data['status'] == 'error';
        final cancelled = data['status'] == 'interrupted';
        final text = data['text']?.toString() ?? _reading.streaming;
        if (text.isNotEmpty) {
          _reading.appendAssistant(
            text,
            turnGeneration: _runtime.turnRevision,
            reasoning: data['reasoning'] is String
                ? data['reasoning'] as String
                : '',
            responseReused:
                !failed && !cancelled && data['response_reused'] == true,
            responsePreviewed: data['response_previewed'] == true,
            persistedTurn: data['persisted_turn'],
          );
        }
        _runtime.completeTurn(
          failed: failed,
          cancelled: cancelled,
          error: failed ? data['error']?.toString() ?? 'Turn failed' : null,
        );
        return true;
      case 'error':
      case 'turn.error':
        _runtime.failTurn(data['message']?.toString() ?? 'Turn failed');
        return true;
    }
    return false;
  }

  String? _session;
  int? _older;
  bool _explicitRead = false;
  bool _loading = false;
  bool _paging = false;
  bool _available = false;
  String? _error;
  double _scrollOffset = 0;
  @override
  bool get historyLoading => _loading || _explicitRead;
  @override
  bool get historyPaging => _loading && _paging;
  @override
  int? get nextHistoryOffset => _older;
  @override
  String? get historyError => _error;
  @override
  String? get historySessionId => _session;
  @override
  bool get historyUnavailable => false;
  @override
  bool get historyAvailable => _available;
  @override
  String get streaming => _reading.streaming;
  @override
  double get historyScrollOffset => _scrollOffset;
  @override
  void recordScrollOffset(double offset) => _scrollOffset = offset;
  @override
  Object messagePresentationId(Map<String, dynamic> row) =>
      _reading.messagePresentationId(row);
  @override
  List<Map<String, dynamic>> get messages => _reading.messages;
}

final class _WorkerSubagentDetail extends ChangeNotifier
    implements SubagentInspectionDetail {
  _WorkerSubagentDetail(this.owner, this.initial) {
    owner.addListener(_changed);
  }
  final BotGroupHistorySession owner;
  final GatewaySubagentActivity initial;
  void _changed() => notifyListeners();
  @override
  bool get supportsTail => false;
  @override
  SubagentSupervisionObservation get state => SubagentSupervisionObservation(
    activity:
        owner.subagents.where((a) => a.id == initial.id).firstOrNull ?? initial,
    unconfirmed: owner.liveError != null,
    canControl: false,
    acceptsSteer: false,
    tail: null,
    lastAvailableTail: null,
    tailError: null,
    tailFailures: 0,
    loadingTail: false,
    steering: false,
    interrupting: false,
    controlMessage: null,
    controlFailed: false,
  );
  @override
  void setActive(bool value) {}
  @override
  Future<void> refreshTail() async {
    await owner.refreshLive();
  }

  @override
  void retryTail() => unawaited(refreshTail());
  @override
  Future<bool> steer(String text) async => false;
  @override
  Future<void> interrupt() async {}
  @override
  void dispose() {
    owner.removeListener(_changed);
    super.dispose();
  }
}
