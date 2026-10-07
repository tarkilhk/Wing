import 'answer_versions.dart';
import 'review_notice.dart';
import 'transcript_message.dart';
import 'transcript_notice.dart';

/// A transient, pure projection of the existing owner's immutable reading rows.
/// Ordinals identify presentation inputs, never runtime or command authority.
final class TranscriptTimeline {
  TranscriptTimeline._values(this.entries, this.sections, this.hasLiveMessage);

  factory TranscriptTimeline._(
    Iterable<TranscriptTimelineEntry> source, {
    required bool hasLiveMessage,
  }) {
    final entries = List<TranscriptTimelineEntry>.unmodifiable(source);
    final groups = _groupRows(entries);
    return TranscriptTimeline._values(
      entries,
      _groupSections(groups),
      hasLiveMessage,
    );
  }

  final List<TranscriptTimelineEntry> entries;
  final List<TranscriptTimelineSection> sections;
  final bool hasLiveMessage;

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
      final message = TranscriptMessage.fromRow(readingRow);
      final branchAnswer =
          row['role'] == 'assistant' &&
          savedId != null &&
          isBranchMessage(row) &&
          sender == null;
      entries.add(
        TranscriptTimelineEntry._(
          sourceIndex: index,
          presentationId: presentationId(row),
          message: message,
          tool: row['role'] == 'tool'
              ? message.tool ?? TranscriptToolResult.fromRow(readingRow)
              : null,
          reviewText: reviewMessageText(row),
          suppressed: hidden,
          emptyAssistant:
              row['role'] == 'assistant' &&
              (row['display_content'] ?? row['content'] ?? '')
                  .toString()
                  .isEmpty,
          streaming: streaming,
          reasoning: _reasoning(row),
          interAgentSender: sender,
          savedMessageId: savedId,
          editablePrompt: isHumanAnswerPrompt(row) && savedId != null,
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
      !hasLiveMessage && sections.isNotEmpty && sections.last.isTool;

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
    final index = entries.indexWhere((entry) => entry.message.id == messageId);
    if (index < 0) return null;
    final start = (index - 4).clamp(0, entries.length).toInt();
    final end = (index + 5).clamp(0, entries.length).toInt();
    final result = TranscriptTimeline._(
      entries.sublist(start, end),
      hasLiveMessage: false,
    );
    return result.sections.any((section) => section.containsMessage(messageId))
        ? result
        : null;
  }
}

final class TranscriptTimelineEntry {
  const TranscriptTimelineEntry._({
    required this.sourceIndex,
    required this.presentationId,
    required this.message,
    required this.tool,
    required this.reviewText,
    required this.suppressed,
    required this.emptyAssistant,
    required this.streaming,
    required this.reasoning,
    required this.interAgentSender,
    required this.savedMessageId,
    required this.editablePrompt,
    required this.branchAnswer,
    required this.sharedAnswerMessageId,
    required this.followedByResultNotice,
  });

  final int sourceIndex;
  final Object presentationId;
  final TranscriptMessage message;
  final TranscriptToolResult? tool;
  final String? reviewText;
  final bool suppressed;
  final bool emptyAssistant;
  final bool streaming;
  final String reasoning;
  final String? interAgentSender;
  final int? savedMessageId;
  final bool editablePrompt;
  final bool branchAnswer;
  final int? sharedAnswerMessageId;
  final bool followedByResultNotice;
}

final class TranscriptTimelineGroup {
  TranscriptTimelineGroup._(Iterable<TranscriptTimelineEntry> messages)
    : messages = List.unmodifiable(messages);
  final List<TranscriptTimelineEntry> messages;
  bool get isTool => messages.last.message.role == 'tool';
  String? get reviewText => messages.last.reviewText;
  bool get isActivity => isTool || reviewText != null;
  List<TranscriptToolResult> get toolResults =>
      List.unmodifiable([for (final message in messages) ?message.tool]);
  bool containsMessage(int id) =>
      messages.any((entry) => entry.message.id == id);
}

final class TranscriptTimelineSection {
  TranscriptTimelineSection._(Iterable<TranscriptTimelineGroup> groups)
    : groups = List.unmodifiable(groups);
  final List<TranscriptTimelineGroup> groups;
  Iterable<TranscriptTimelineEntry> get messages =>
      groups.expand((group) => group.messages);
  bool get isTool => groups.last.isTool;
  bool get isActivity => groups.last.isActivity;
  int get toolCount =>
      messages.where((entry) => entry.message.role == 'tool').length;
  int get reviewCount =>
      messages.where((entry) => entry.reviewText != null).length;
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
  final groups = <List<TranscriptTimelineEntry>>[];
  for (final entry in entries) {
    if (entry.suppressed) continue;
    if (entry.message.role == 'tool' &&
        groups.isNotEmpty &&
        groups.last.last.message.role == 'tool') {
      groups.last.add(entry);
    } else {
      groups.add([entry]);
    }
  }
  return List.unmodifiable(groups.map(TranscriptTimelineGroup._));
}

List<TranscriptTimelineSection> _groupSections(
  List<TranscriptTimelineGroup> groups,
) {
  final sections = <List<TranscriptTimelineGroup>>[];
  for (final group in groups) {
    if (group.messages.last.emptyAssistant) continue;
    if (group.isActivity &&
        sections.isNotEmpty &&
        sections.last.last.isActivity) {
      sections.last.add(group);
    } else {
      sections.add([group]);
    }
  }
  return List.unmodifiable(sections.map(TranscriptTimelineSection._));
}

bool _branchAnswer(List<Map<String, dynamic>> rows, int index) =>
    rows[index]['role'] == 'assistant' &&
    answerMessageId(rows[index]) != null &&
    isBranchMessage(rows[index]) &&
    interAgentReplySender(rows, index) == null;

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
  return '';
}
