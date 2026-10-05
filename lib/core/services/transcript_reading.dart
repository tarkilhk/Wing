import '../models/notification_focus.dart';
import '../models/answer_versions.dart';
import '../models/hermes_profile.dart';
import '../models/local_transcript_message.dart';
import '../models/reading_snapshot_message.dart';
import '../models/review_notice.dart';
import '../models/transcript_reading.dart';
import '../models/user_message_content.dart';
import 'completion_diagnostics.dart';
import 'profile_gateway.dart';
import 'workspace_connection_failure.dart';

/// Sole writer of a chat's transcript rows, read revisions and presentation IDs.
/// It borrows transport; the coordinator supplies captured publication authority.
final class TranscriptReading {
  TranscriptReading({required this._gateway});

  final ProfileGateway _gateway;
  WorkspaceScope get scope => _gateway.scope;
  List<Map<String, dynamic>> _messages = const [];
  String? _historySessionId;
  int? _nextHistoryOffset;
  int _historyGeneration = 0;
  bool _historyLoading = false;
  String? _historyError;
  bool _historyUnavailable = false;
  double _historyScrollOffset = 0;
  bool _closed = false;
  String _streaming = '';
  Map<String, dynamic>? _streamingMessage;
  Map<String, dynamic>? _lastInterimMessage;
  int _lastInterimTurn = -1;
  final _messagePresentations = Expando<Object>();
  final _ownedRows = Expando<bool>();
  final _confirmedPresentations = <int, Object>{};
  int _commandNoticeSequence = 0;
  NotificationFocus? _notificationFocus;
  NotificationFocus? _notificationReadTarget;
  int _notificationFocusGeneration = 0;

  NotificationFocus? get notificationFocus => _notificationFocus;
  NotificationFocus? get notificationReadTarget => _notificationReadTarget;
  int get notificationFocusGeneration => _notificationFocusGeneration;

  void revealNotification(NotificationFocus? focus) {
    if (_closed) return;
    _notificationFocus = focus;
    _notificationFocusGeneration++;
  }

  bool releaseNotificationFocus(NotificationFocus focus, int generation) {
    if (_closed ||
        generation != _notificationFocusGeneration ||
        _notificationFocus != focus) {
      return false;
    }
    _notificationFocus = null;
    return true;
  }

  void restoreNotificationReadTarget(NotificationFocus? focus) {
    if (!_closed) _notificationReadTarget ??= focus;
  }

  void recordNotificationResult(NotificationFocus? focus) {
    if (!_closed) _notificationReadTarget = focus;
  }

  bool acknowledgeNotificationRead(NotificationFocus focus) {
    if (_closed || _notificationReadTarget?.identity != focus.identity) {
      return false;
    }
    _notificationReadTarget = null;
    return true;
  }

  List<Map<String, dynamic>> get messages => _messages;
  String? get historySessionId => _historySessionId;
  int? get nextHistoryOffset => _nextHistoryOffset;
  int get historyGeneration => _historyGeneration;
  bool get historyLoading => _historyLoading;
  String? get historyError => _historyError;
  bool get historyUnavailable => _historyUnavailable;
  double get historyScrollOffset => _historyScrollOffset;
  String get streaming => _streaming;
  Map<String, dynamic>? get streamingMessage => _streamingMessage;

  Object messagePresentationId(Map<String, dynamic> row) =>
      _messagePresentations[row] ??= Object();

  void recordScrollOffset(double offset) {
    if (!_closed) _historyScrollOffset = offset;
  }

  void cancelReads() {
    _historyGeneration++;
    _historyLoading = false;
  }

  void dispose() {
    _closed = true;
    cancelReads();
  }

  /// A replacement runtime keeps visible work but cannot retain old paging.
  void resetHistorySegment() {
    if (_closed) return;
    cancelReads();
    _historySessionId = null;
    _nextHistoryOffset = null;
    _historyError = null;
  }

  void updateStreaming(String text) {
    if (_closed) return;
    _streaming = text;
    final previous = _streamingMessage;
    if (text.isEmpty) {
      _streamingMessage = null;
    } else {
      final row = _freezeRow({'role': 'assistant', 'content': text});
      if (previous != null) {
        _messagePresentations[row] = messagePresentationId(previous);
      }
      _streamingMessage = row;
    }
  }

  void appendStreaming(String text) => updateStreaming('$_streaming$text');

  void appendPrompt({
    required String text,
    String? displayText,
    Iterable<UserMessageAttachment> attachments = const [],
    bool steering = false,
  }) {
    _append({
      'role': 'user',
      'content': text,
      'display_content': ?displayText,
      if (attachments.isNotEmpty) 'submitted_attachments': attachments.toList(),
      if (steering) 'display_kind': 'steer',
      if (!steering) 'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
    });
  }

  void appendCommandNotice(String text, {String? command}) {
    _append({
      'id':
          'command-${DateTime.now().microsecondsSinceEpoch}-${++_commandNoticeSequence}',
      'role': 'system',
      'content': text,
      '_command': ?command,
      '_command_notice': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
    });
  }

  void appendReviewNotice({
    required String identity,
    required String text,
    num? timestamp,
  }) {
    _append({
      'id': 'review-$identity',
      'role': 'system',
      'content': text,
      '_review_notice': identity,
      'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch / 1000,
    });
  }

  void retireReviewNotice(String identity) {
    if (_closed) return;
    _messages = List.unmodifiable(
      _messages.where((row) => row['_review_notice'] != identity),
    );
  }

  void retireRuntimeNotices() {
    if (_closed) return;
    _messages = List.unmodifiable(
      _messages.where((row) => !isLocalReviewMessage(row)),
    );
  }

  void _append(Map<String, dynamic> row) {
    if (_closed) return;
    _messages = List.unmodifiable([..._messages, _freezeRow(row)]);
  }

  /// Used by real saved-history adoption, branch creation and passive restore.
  /// Input containers never remain writable aliases of the owned transcript.
  void installSavedHistory(Iterable<Map<String, dynamic>> rows) {
    if (_closed) return;
    _messages = List.unmodifiable(rows.map(_freezeRow));
  }

  void installSnapshot(TranscriptReadingSnapshot snapshot) {
    if (_closed) return;
    cancelReads();
    installSavedHistory(snapshot.messages);
    _historySessionId = snapshot.historySessionId;
    _nextHistoryOffset = null;
  }

  /// Adopts a saved page through the same paging and presentation policy used
  /// by a latest read. Local feedback remains in the resolved history segment.
  void installSavedPage(ProfileHistoryPage page) {
    if (_closed) return;
    final anchor = page.rows.isEmpty || _historySessionId != page.sessionId
        ? -1
        : _messages.indexWhere((row) => row['id'] == page.rows.first['id']);
    final prefix = anchor > 0
        ? _messages.take(anchor)
        : const <Map<String, dynamic>>[];
    final refreshed = [
      ...prefix.where((row) => !isLocalTranscriptMessage(row)),
      ...page.rows.map(_freezeRow),
    ];
    _retainMessagePresentations(refreshed, page.sessionId);
    _messages = List.unmodifiable(
      _historySessionId == page.sessionId
          ? retainLocalTranscriptMessages(_messages, refreshed)
          : refreshed,
    );
    _historySessionId = page.sessionId;
    _nextHistoryOffset = page.nextOffset == null ? null : refreshed.length;
  }

  /// Issues fixed-field passive rows without recopying owned content. Large
  /// content is already immutable; the snapshot encoder validates its bounds.
  /// Newly projected metadata and attachment containers are frozen here.
  ({String? historySessionId, List<Map<String, dynamic>> messages})
  captureSnapshot() => (
    historySessionId: _historySessionId,
    messages: List<Map<String, dynamic>>.unmodifiable(
      _messages
          .skip(_messages.length > 60 ? _messages.length - 60 : 0)
          .map(_captureSnapshotRow),
    ),
  );

  Map<String, dynamic> _captureSnapshotRow(Map<String, dynamic> row) {
    final projected = captureReadingSnapshotMessage(row);
    final metadata = projected['display_metadata'];
    if (metadata is Map) {
      projected['display_metadata'] = Map<Object?, Object?>.unmodifiable(
        metadata,
      );
    }
    final attachments = projected['submitted_attachments'];
    if (attachments is List) {
      projected['submitted_attachments'] =
          List<Map<String, dynamic>>.unmodifiable([
            for (final attachment in attachments)
              Map<String, dynamic>.unmodifiable(
                attachment as Map<String, dynamic>,
              ),
          ]);
    }
    return Map<String, dynamic>.unmodifiable(projected);
  }

  /// Captures only reading facts; status and dispatch remain coordinator-owned.
  TranscriptBranchCapture captureBranch() =>
      TranscriptBranchCapture._(this, _messages, _streaming, _streamingMessage);

  void stageRegeneration(List<Map<String, dynamic>> history, int promptIndex) {
    cancelReads();
    installSavedHistory(
      answerHistoryRows(history.take(promptIndex + 1).toList()),
    );
    updateStreaming('');
  }

  void stageSavedPromptEdit(
    List<Map<String, dynamic>> history,
    int promptIndex,
    String text,
  ) {
    cancelReads();
    installSavedHistory(answerHistoryRows(history.take(promptIndex).toList()));
    appendPrompt(text: text);
    updateStreaming('');
  }

  void restoreBranch(
    TranscriptBranchCapture capture, {
    required bool restoreStreaming,
  }) {
    if (_closed || !identical(capture._owner, this)) return;
    _messages = capture._messages;
    if (restoreStreaming) {
      _streaming = capture._streaming;
      _streamingMessage = capture._streamingMessage;
    }
  }

  void appendAssistant(
    String text, {
    required int turnGeneration,
    required String reasoning,
    required bool responseReused,
    Object? persistedTurn,
    bool interim = false,
    bool responsePreviewed = false,
  }) {
    if (_closed) return;
    final preview = responsePreviewed ? _lastInterimMessage : null;
    final reusePreview =
        preview != null &&
        _lastInterimTurn == turnGeneration &&
        _streaming.isEmpty &&
        _messages.contains(preview) &&
        preview['content'] == text;
    // Stock reuse names text already delivered in this turn. Keep the complete
    // visible buffer across tool rounds; a reconnect with missing text still
    // needs the authoritative final body.
    final content =
        responseReused && _streaming.isNotEmpty && _streaming.contains(text)
        ? _streaming
        : text;
    final previous = reusePreview ? preview : _streamingMessage;
    final row = _freezeRow({
      ...?previous,
      'role': 'assistant',
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
      if (reasoning.isNotEmpty) '_gateway_reasoning': reasoning,
    });
    if (previous != null) {
      _messagePresentations[row] = messagePresentationId(previous);
    }
    if (reusePreview) {
      _messages = List.unmodifiable(
        _messages.map((item) => identical(item, preview) ? row : item),
      );
    } else {
      _messages = List.unmodifiable([..._messages, row]);
    }
    _lastInterimMessage = interim ? row : null;
    _lastInterimTurn = interim ? turnGeneration : -1;
    // Stock receipt proves final-row persistence, independently of whole-turn ACK.
    if (persistedTurn is Map) {
      final id = persistedTurn['final_assistant_row_id'];
      final ids = persistedTurn['row_ids'];
      if (id is int &&
          id > 0 &&
          ids is List &&
          ids.whereType<int>().contains(id)) {
        _confirmedPresentations
          ..clear()
          ..[id] = messagePresentationId(row);
      }
    }
    updateStreaming('');
  }

  void _retainMessagePresentations(
    List<Map<String, dynamic>> refreshed,
    String segment,
  ) {
    if (_historySessionId != null && _historySessionId != segment) {
      _confirmedPresentations.clear();
      _lastInterimMessage = null;
      return;
    }
    final previousById = {
      for (final row in _messages)
        if (row['id'] != null) row['id']: row,
    };
    for (final row in refreshed) {
      final previous = previousById[row['id']];
      final previousToken = previous == null
          ? null
          : _messagePresentations[previous];
      final confirmed = row['role'] == 'assistant'
          ? _confirmedPresentations.remove(row['id'])
          : null;
      if (confirmed != null && row['role'] == 'assistant') {
        _messagePresentations[row] = confirmed;
      } else if (previousToken != null) {
        _messagePresentations[row] = previousToken;
      }
    }
    // Some current-stock completions have no persistence receipt. Only bind
    // provisional rows when the entire visible suffix after a known durable
    // boundary agrees in order and content. Never match repeated text globally.
    final boundary = _messages.lastIndexWhere((row) => row['id'] != null);
    if (boundary >= 0) {
      final nextBoundary = refreshed.indexWhere(
        (row) => row['id'] == _messages[boundary]['id'],
      );
      if (nextBoundary >= 0) {
        bool visible(Map<String, dynamic> row) =>
            isBranchMessage(row) && !isHiddenAnswerMessage(row);
        final pending = _messages.skip(boundary + 1).where(visible).toList();
        final saved = refreshed.skip(nextBoundary + 1).where(visible).toList();
        if (pending.isNotEmpty &&
            pending.length == saved.length &&
            pending.indexed.every(
              (entry) =>
                  entry.$2['role'] == saved[entry.$1]['role'] &&
                  entry.$2['display_kind'] == saved[entry.$1]['display_kind'] &&
                  answerMessageDisplayText(entry.$2) ==
                      answerMessageDisplayText(saved[entry.$1]),
            )) {
          for (var i = 0; i < pending.length; i++) {
            final token = _messagePresentations[pending[i]];
            if (token != null) _messagePresentations[saved[i]] = token;
          }
        }
      }
    }
    final interim = _lastInterimMessage;
    if (interim != null) {
      final token = messagePresentationId(interim);
      _lastInterimMessage = refreshed
          .where((row) => identical(_messagePresentations[row], token))
          .firstOrNull;
    }
  }

  /// Captured read-only routes own selection/publication; this read cannot
  /// install rows or revive execution from a saved transcript.
  Future<ProfileHistoryPage> savedPage(
    String sessionId, {
    int offset = 0,
  }) async {
    if (_closed) throw StateError('This chat reading owner is closed.');
    final page = await _gateway.history(sessionId, offset: offset, limit: 500);
    if (_closed) throw StateError('This chat reading owner is closed.');
    if (page.sessionId != sessionId) {
      throw const FormatException(
        'The server returned a different chat history.',
      );
    }
    return ProfileHistoryPage(
      page.sessionId,
      List.unmodifiable(page.rows.map(_freezeRow)),
      page.offset,
      page.limit,
      isComplete: page.isComplete,
    );
  }

  Future<bool> refresh({
    required String sessionId,
    required String runtimeId,
    required bool Function() canPublish,
    required void Function() onChanged,
    bool propagateFailure = false,
  }) async {
    final historySetupStarted = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final generation = ++_historyGeneration;
    _historyLoading = true;
    _historyError = null;
    _historyUnavailable = false;
    onChanged();
    bool valid() =>
        !_closed && _historyGeneration == generation && canPublish();
    if (!valid()) {
      if (!_closed && _historyGeneration == generation) _historyLoading = false;
      return false;
    }
    try {
      final historyRead = _gateway.history(sessionId, runtimeId: runtimeId);
      if (CompletionDiagnostics.enabled) {
        CompletionDiagnostics.finish(
          'controller.history_setup_sync',
          historySetupStarted,
        );
      }
      final page = await historyRead;
      if (!valid()) return false;
      final historyApplyStarted = CompletionDiagnostics.enabled
          ? CompletionDiagnostics.start()
          : 0;
      installSavedPage(page);
      // The page limit counts raw rows. A running turn can fill it with tool
      // calls and empty assistant rows, hiding the conversation on reopen.
      // Backfill such a page to its prompt; ordinary dialogue stays paginated.
      final needsConversationContext = _messages.any(
        (row) => row['role'] == 'tool',
      );
      if (CompletionDiagnostics.enabled) {
        CompletionDiagnostics.finish(
          'controller.history_apply_initial_sync',
          historyApplyStarted,
          values: {'rows': _messages.length},
        );
      }
      while (needsConversationContext &&
          _nextHistoryOffset != null &&
          !_messages.any(
            (row) => isAnswerPrompt(row) && !isHiddenAnswerMessage(row),
          )) {
        onChanged();
        if (!valid()) return false;
        final olderPage = await _gateway.history(
          _historySessionId!,
          offset: _nextHistoryOffset!,
        );
        if (!valid()) return false;
        if (olderPage.sessionId != _historySessionId) {
          throw StateError('History moved to a new segment');
        }
        final ids = _messages.map((row) => row['id']).toSet();
        final oldest =
            _messages.where((row) => row['id'] is int).firstOrNull?['id']
                as int?;
        final older = olderPage.rows
            .where(
              (row) =>
                  !ids.contains(row['id']) &&
                  (oldest == null || (row['id'] as int) < oldest),
            )
            .toList();
        if (older.isEmpty && olderPage.nextOffset != null) {
          throw StateError('History did not advance');
        }
        _messages = List.unmodifiable([...older.map(_freezeRow), ..._messages]);
        _nextHistoryOffset = olderPage.nextOffset;
      }
      return true;
    } catch (failure) {
      if (valid()) {
        _historyUnavailable = isTemporaryWorkspaceFailure(failure);
        _historyError = 'History could not be loaded. Retry to reload.';
      }
      if (propagateFailure) rethrow;
      return false;
    } finally {
      if (!_closed && _historyGeneration == generation) {
        _historyLoading = false;
        if (canPublish()) onChanged();
      }
    }
  }

  Future<void> loadOlder({
    required bool Function() canPublish,
    required void Function() onChanged,
  }) async {
    if (_closed ||
        _historyLoading ||
        _nextHistoryOffset == null ||
        !canPublish()) {
      return;
    }
    final generation = _historyGeneration;
    final offset = _nextHistoryOffset!;
    _historyLoading = true;
    _historyError = null;
    onChanged();
    bool valid() =>
        !_closed && _historyGeneration == generation && canPublish();
    if (!valid()) {
      if (!_closed && _historyGeneration == generation) _historyLoading = false;
      return;
    }
    try {
      final page = await _gateway.history(_historySessionId!, offset: offset);
      if (!valid()) return;
      if (page.sessionId != _historySessionId) {
        throw StateError('History moved to a new segment');
      }
      final ids = _messages.map((r) => r['id']).toSet();
      final oldest =
          _messages.where((r) => r['id'] is int).firstOrNull?['id'] as int?;
      final older = page.rows
          .where(
            (r) =>
                !ids.contains(r['id']) &&
                (oldest == null || (r['id'] as int) < oldest),
          )
          .toList();
      _messages = List.unmodifiable([...older.map(_freezeRow), ..._messages]);
      _nextHistoryOffset = page.nextOffset;
    } catch (_) {
      if (valid()) {
        _historyError =
            'Older messages could not be loaded. Retry or refresh history.';
      }
    } finally {
      if (!_closed && _historyGeneration == generation) {
        _historyLoading = false;
        if (canPublish()) onChanged();
      }
    }
  }

  Map<String, dynamic> _freezeRow(Map<String, dynamic> source) {
    // Reuse already-owned immutable rows and their in-memory presentation token.
    if (_ownedRows[source] == true) return source;
    final row = Map<String, dynamic>.unmodifiable({
      for (final entry in source.entries) entry.key: _freezeValue(entry.value),
    });
    _ownedRows[row] = true;
    final token = _messagePresentations[source];
    if (token != null) _messagePresentations[row] = token;
    return row;
  }

  Object? _freezeValue(Object? value) {
    if (value is Map) {
      return Map<Object?, Object?>.unmodifiable({
        for (final entry in value.entries) entry.key: _freezeValue(entry.value),
      });
    }
    if (value is List<UserMessageAttachment>) {
      return List<UserMessageAttachment>.unmodifiable([
        for (final attachment in value)
          UserMessageAttachment(
            name: attachment.name,
            target: attachment.target,
            isImage: attachment.isImage,
          ),
      ]);
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_freezeValue));
    }
    if (value is UserMessageAttachment) {
      return UserMessageAttachment(
        name: value.name,
        target: value.target,
        isImage: value.isImage,
      );
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw const FormatException('Unsupported transcript value.');
  }
}

/// Opaque owner-issued rollback facts, never an execution/resume capability.
final class TranscriptBranchCapture {
  const TranscriptBranchCapture._(
    this._owner,
    this._messages,
    this._streaming,
    this._streamingMessage,
  );
  final TranscriptReading _owner;
  final List<Map<String, dynamic>> _messages;
  final String _streaming;
  final Map<String, dynamic>? _streamingMessage;
}
