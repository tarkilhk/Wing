import 'answer_versions.dart';
import 'review_notice.dart';
import 'transcript_message.dart';
import 'transcript_notice.dart';

/// A transient, pure projection of the existing owner's immutable reading rows.
/// Ordinals identify presentation inputs, never runtime or command authority.
final class TranscriptTimeline {
  TranscriptTimeline._values(
    this.entries,
    this.sections,
    this.hasLiveMessage,
    this._replyDurations,
  );

  factory TranscriptTimeline._(
    Iterable<TranscriptTimelineEntry> source, {
    required bool hasLiveMessage,
    Map<Object, Duration>? replyDurations,
  }) {
    final entries = List<TranscriptTimelineEntry>.unmodifiable(source);
    final groups = _groupRows(entries);
    final durations = replyDurations ?? _savedReplyDurations(entries);
    return TranscriptTimeline._values(
      entries,
      _groupSections(groups, durations),
      hasLiveMessage,
      durations,
    );
  }

  final List<TranscriptTimelineEntry> entries;
  final List<TranscriptTimelineSection> sections;
  final bool hasLiveMessage;
  final Map<Object, Duration> _replyDurations;

  factory TranscriptTimeline.project(
    List<Map<String, dynamic>> rows, {
    required Object Function(Map<String, dynamic>) presentationId,
    int? liveMessageIndex,
  }) {
    final entries = <TranscriptTimelineEntry>[];
    // Saved outputs refer to assistant calls by their backend identity. Calls
    // with no assistant prose must still contribute their inputs.
    final calls = <String, Map>{};
    final callLabels = <String, Object?>{};
    for (final row in rows) {
      if (row['role'] != 'assistant' || row['tool_calls'] is! List) continue;
      for (final call in row['tool_calls'] as List) {
        if (call is Map && call['id'] is String && call['function'] is Map) {
          calls[call['id'] as String] = call['function'] as Map;
          final labels = row['tool_call_labels'];
          if (labels is Map) {
            callLabels[call['id'] as String] = labels[call['id']];
          }
        }
      }
    }
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final call = row['role'] == 'tool' ? calls[row['tool_call_id']] : null;
      final readingRow = call == null
          ? row
          : <String, dynamic>{
              ...row,
              if (row['tool_name'] == null) 'tool_name': call['name'],
              if (row['args'] == null) 'args': call['arguments'],
              if (row['labels'] == null &&
                  callLabels[row['tool_call_id']] != null)
                'labels': callLabels[row['tool_call_id']],
            };
      final hidden = isHiddenAnswerMessage(row);
      final streaming = index == liveMessageIndex;
      final sender = streaming ? null : interAgentReplySender(rows, index);
      final savedId = answerMessageId(row);
      final display = row['display_content'] ?? row['content'] ?? '';
      final branchAnswer =
          row['role'] == 'assistant' &&
          savedId != null &&
          isBranchMessage(row) &&
          sender == null;
      entries.add(
        TranscriptTimelineEntry._(
          sourceIndex: index,
          presentationId: presentationId(row),
          row: readingRow,
          review:
              row['role'] == 'system' &&
              answerMessageText(row).startsWith('review:'),
          suppressed: hidden,
          emptyAssistant:
              row['role'] == 'assistant' &&
              display is String &&
              display.isEmpty,
          streaming: streaming,
          hasReasoning: _hasReasoning(row),
          interAgentSender: sender,
          savedMessageId: savedId,
          branchAnswer: branchAnswer,
          sharedAnswerMessageId:
              index > 0 &&
                  transcriptNoticeKind(row) == 'async_delegation_complete' &&
                  _branchAnswer(rows, index - 1)
              ? answerMessageId(rows[index - 1])
              : null,
          followedByResultNotice:
              index + 1 < rows.length &&
              transcriptNoticeKind(rows[index + 1]) ==
                  'async_delegation_complete',
        ),
      );
    }
    return TranscriptTimeline._(
      entries,
      hasLiveMessage: liveMessageIndex != null,
    );
  }

  bool get joinsCurrentActivity =>
      !hasLiveMessage &&
      sections.isNotEmpty &&
      sections.last.isActivity &&
      !sections.last.hasLatestReview;

  /// Post-frame visibility targets consult the current owner's rows, not a
  /// preceding frame's timeline. This returns identity only, never raw content.
  static Object? notificationAnswerPresentation(
    List<Map<String, dynamic>> rows, {
    required Object Function(Map<String, dynamic>) presentationId,
    int? messageId,
  }) {
    for (final row in rows.reversed) {
      if (row['role'] == 'assistant' &&
          !isHiddenAnswerMessage(row) &&
          row['content'] is String &&
          (row['content'] as String).trim().isNotEmpty &&
          (messageId == null || row['id'] == messageId)) {
        return presentationId(row);
      }
    }
    return null;
  }

  /// Choose the original nine-row neighborhood before hiding or grouping rows.
  /// Full-source ordinals and delivery context remain captured by the entries.
  TranscriptTimeline? nearby(int messageId) {
    final index = entries.indexWhere((entry) => entry.id == messageId);
    if (index < 0) return null;
    final start = (index - 4).clamp(0, entries.length).toInt();
    final end = (index + 5).clamp(0, entries.length).toInt();
    final result = TranscriptTimeline._(
      entries.sublist(start, end),
      hasLiveMessage: false,
      replyDurations: _replyDurations,
    );
    return result.sections.any((section) => section.containsMessage(messageId))
        ? result
        : null;
  }
}

final class TranscriptTimelineEntry {
  TranscriptTimelineEntry._({
    required this.sourceIndex,
    required this.presentationId,
    required Map<String, dynamic> row,
    required bool review,
    required this.suppressed,
    required this.emptyAssistant,
    required this.streaming,
    required this.hasReasoning,
    required this.interAgentSender,
    required this.savedMessageId,
    required this.branchAnswer,
    required this.sharedAnswerMessageId,
    required this.followedByResultNotice,
  }) : _row = row,
       isReview = review,
       role = row['role']?.toString() ?? '',
       id = row['id'] is int || row['id'] is String ? row['id'] : null;

  final int sourceIndex;
  final Object presentationId;
  // Borrow the existing immutable reading row. Bodies are prepared only when a
  // viewport row or an opened disclosure asks for them; no rendered tree lives
  // in this transient index. Identity/grouping must never force these getters.
  final Map<String, dynamic> _row;
  final String role;
  final Object? id;
  final bool isReview;
  late final TranscriptMessage message = TranscriptMessage.fromRow(_row);
  late final TranscriptToolResult? tool = role == 'tool'
      ? message.tool ?? TranscriptToolResult.fromRow(_row)
      : null;
  late final String? reviewText = isReview ? reviewMessageText(_row) : null;
  final bool suppressed;
  final bool emptyAssistant;
  final bool streaming;
  final bool hasReasoning;
  late final String reasoning = _reasoning(_row);
  final String? interAgentSender;
  final int? savedMessageId;
  late final bool editablePrompt =
      savedMessageId != null && isHumanAnswerPrompt(_row);
  final bool branchAnswer;
  final int? sharedAnswerMessageId;
  final bool followedByResultNotice;
}

final class TranscriptTimelineGroup {
  TranscriptTimelineGroup._(
    Iterable<TranscriptTimelineEntry> messages, {
    this.isReasoning = false,
  }) : messages = List.unmodifiable(messages);
  final List<TranscriptTimelineEntry> messages;
  final bool isReasoning;
  Iterable<Object> get presentationIds => messages.map(
    (entry) => isReasoning
        ? ('reasoning', entry.presentationId)
        : entry.presentationId,
  );
  bool get isTool => !isReasoning && messages.last.role == 'tool';
  String? get reviewText => messages.last.reviewText;
  bool get isActivity => isReasoning || isTool || messages.last.isReview;
  List<TranscriptToolResult> get toolResults =>
      List.unmodifiable([for (final message in messages) ?message.tool]);
  bool containsMessage(int id) => messages.any((entry) => entry.id == id);
}

final class TranscriptTimelineSection {
  TranscriptTimelineSection._(
    Iterable<TranscriptTimelineGroup> groups, {
    this.replyDuration,
  }) : groups = List.unmodifiable(groups);
  final List<TranscriptTimelineGroup> groups;

  /// Approximate interval from the saved human prompt to its final saved reply.
  /// Both timestamps belong to Hermes; receipt time and tool durations do not.
  final Duration? replyDuration;
  Iterable<TranscriptTimelineEntry> get messages =>
      groups.expand((group) => group.messages);
  Iterable<Object> get presentationIds =>
      groups.expand((group) => group.presentationIds);
  bool get isTool => groups.last.isTool;
  bool get isActivity => groups.last.isActivity;
  int get toolCount => groups
      .where((group) => group.isTool)
      .fold(0, (count, group) => count + group.messages.length);
  int get reviewCount => messages.where((entry) => entry.isReview).length;
  bool get hasLatestReview => groups.last.messages.last.isReview;
  String? get latestReview => groups.last.reviewText;
  TranscriptTimelineSection? get precedingLatestReview => groups.length <= 1
      ? null
      : TranscriptTimelineSection._(groups.take(groups.length - 1));
  bool containsMessage(int id) =>
      groups.any((group) => group.containsMessage(id));
}

List<TranscriptTimelineGroup> _groupRows(
  Iterable<TranscriptTimelineEntry> entries,
) {
  final groups = <TranscriptTimelineGroup>[];
  final tools = <TranscriptTimelineEntry>[];
  void flushTools() {
    if (tools.isEmpty) return;
    groups.add(TranscriptTimelineGroup._(tools));
    tools.clear();
  }

  for (final entry in entries) {
    if (entry.suppressed) continue;
    if (entry.hasReasoning && entry.interAgentSender == null) {
      flushTools();
      groups.add(TranscriptTimelineGroup._([entry], isReasoning: true));
    }
    if (entry.emptyAssistant) {
      // Invisible assistant rows still separate neighboring tool runs.
      flushTools();
      continue;
    }
    if (entry.role == 'tool') {
      tools.add(entry);
    } else {
      flushTools();
      groups.add(TranscriptTimelineGroup._([entry]));
    }
  }
  flushTools();
  return List.unmodifiable(groups);
}

List<TranscriptTimelineSection> _groupSections(
  List<TranscriptTimelineGroup> groups,
  Map<Object, Duration> replyDurations,
) {
  final sections = <List<TranscriptTimelineGroup>>[];
  for (final group in groups) {
    if (group.isActivity &&
        sections.isNotEmpty &&
        sections.last.last.isActivity) {
      sections.last.add(group);
    } else {
      sections.add([group]);
    }
  }
  return List.unmodifiable([
    for (var index = 0; index < sections.length; index++)
      TranscriptTimelineSection._(
        sections[index],
        replyDuration:
            sections[index].last.isActivity && index + 1 < sections.length
            ? replyDurations[sections[index + 1]
                  .last
                  .messages
                  .last
                  .presentationId]
            : null,
      ),
  ]);
}

Map<Object, Duration> _savedReplyDurations(
  List<TranscriptTimelineEntry> entries,
) {
  final durations = <Object, Duration>{};
  TranscriptTimelineEntry? prompt;
  TranscriptTimelineEntry? reply;

  void record() {
    final sent = prompt;
    final answer = reply;
    if (sent == null ||
        answer == null ||
        sent.savedMessageId == null ||
        answer.savedMessageId == null ||
        answer.streaming) {
      return;
    }
    final start = _savedTimestamp(sent._row['timestamp']);
    final end = _savedTimestamp(answer._row['timestamp']);
    if (start == null || end == null || end < start) return;
    durations[answer.presentationId] = Duration(
      microseconds: ((end - start) * Duration.microsecondsPerSecond).round(),
    );
  }

  for (final entry in entries) {
    if (entry.suppressed) continue;
    if (entry.role == 'user' && isHumanAnswerPrompt(entry._row)) {
      record();
      prompt = entry;
      reply = null;
    } else if (entry.role == 'tool' || entry.emptyAssistant) {
      reply = null;
    } else if (entry.role == 'assistant' && entry.interAgentSender == null) {
      final calls = entry._row['tool_calls'];
      reply =
          calls is List && calls.isNotEmpty ||
              transcriptNoticeKind(entry._row) != null
          ? null
          : entry;
    }
  }
  record();
  return Map.unmodifiable(durations);
}

double? _savedTimestamp(Object? value) =>
    value is num && value.isFinite && value > 0 && value <= 8640000000000
    ? value.toDouble()
    : null;

bool _branchAnswer(List<Map<String, dynamic>> rows, int index) =>
    rows[index]['role'] == 'assistant' &&
    answerMessageId(rows[index]) != null &&
    isBranchMessage(rows[index]) &&
    interAgentReplySender(rows, index) == null;

bool _hasReasoning(Map<String, dynamic> row) {
  for (final key in const [
    '_gateway_reasoning',
    'reasoning',
    'reasoning_content',
    'reasoning_details',
  ]) {
    final value = row[key];
    if (value is String && value.trim().isNotEmpty) return true;
  }
  final details = row['reasoning_details'];
  if (details is List &&
      details.any(
        (detail) =>
            detail is Map &&
            ((detail['type'] == 'reasoning.text' &&
                    detail['text'] is String &&
                    (detail['text'] as String).trim().isNotEmpty) ||
                (detail['type'] == 'reasoning.summary' &&
                    detail['summary'] is String &&
                    (detail['summary'] as String).trim().isNotEmpty)),
      )) {
    return true;
  }
  final items = row['codex_reasoning_items'];
  return items is List &&
      items.any(
        (item) =>
            item is Map &&
            item['type'] == 'reasoning' &&
            item['summary'] is List &&
            (item['summary'] as List).any(
              (part) =>
                  part is Map &&
                  part['type'] == 'summary_text' &&
                  part['text'] is String &&
                  (part['text'] as String).trim().isNotEmpty,
            ),
      );
}

String _reasoning(Map<String, dynamic> row) {
  for (final key in const [
    '_gateway_reasoning',
    'reasoning',
    'reasoning_content',
    'reasoning_details',
  ]) {
    final value = row[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  final details = row['reasoning_details'];
  if (details is List) {
    final text = [
      for (final detail in details)
        if (detail is Map)
          if (detail['type'] == 'reasoning.text' && detail['text'] is String)
            detail['text'] as String
          else if (detail['type'] == 'reasoning.summary' &&
              detail['summary'] is String)
            detail['summary'] as String,
    ].where((text) => text.trim().isNotEmpty).join('\n\n');
    if (text.isNotEmpty) return text;
  }
  final items = row['codex_reasoning_items'];
  if (items is List) {
    return [
      for (final item in items)
        if (item is Map && item['type'] == 'reasoning')
          if (item['summary'] is List)
            for (final part in item['summary'] as List)
              if (part is Map &&
                  part['type'] == 'summary_text' &&
                  part['text'] is String)
                part['text'] as String,
    ].where((text) => text.trim().isNotEmpty).join('\n\n');
  }
  return '';
}
