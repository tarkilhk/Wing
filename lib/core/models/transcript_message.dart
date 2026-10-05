import 'answer_versions.dart';
import 'review_notice.dart';
import 'transcript_notice.dart';
import 'user_message_content.dart';

enum TranscriptMessageKind {
  hidden,
  notice,
  review,
  steering,
  system,
  tool,
  dialogue,
}

/// Passive reading facts. This projection cannot hydrate or execute a runtime,
/// acknowledge delivery, or change the authoritative history row.
final class TranscriptMessage {
  TranscriptMessage._({
    required this.kind,
    required this.role,
    required this.id,
    this.text = '',
    this.copyText = '',
    this.noticeResult,
    this.noticeDisclosure = 'View result',
    this.noticePlainText = false,
    this.noticeMonospace = false,
    this.systemMultiline = false,
    this.timestamp,
    this.tool,
    Iterable<UserMessageAttachment> attachments = const [],
  }) : attachments = List.unmodifiable([
         for (final attachment in attachments)
           UserMessageAttachment(
             name: attachment.name,
             target: attachment.target,
             isImage: attachment.isImage,
           ),
       ]);

  final TranscriptMessageKind kind;
  final String role;
  final Object? id;
  final String text;
  final String copyText;
  final String? noticeResult;
  final String noticeDisclosure;
  final bool noticePlainText;
  final bool noticeMonospace;
  final bool systemMultiline;
  final DateTime? timestamp;
  final TranscriptToolResult? tool;
  final List<UserMessageAttachment> attachments;

  factory TranscriptMessage.fromRow(Map<String, dynamic> row) {
    final role = row['role']?.toString() ?? '';
    final rawId = row['id'];
    final id = rawId is int || rawId is String ? rawId : null;
    if (isHiddenAnswerMessage(row)) {
      return TranscriptMessage._(
        kind: TranscriptMessageKind.hidden,
        role: role,
        id: id,
      );
    }
    final notice = transcriptNoticeText(row);
    if (notice != null) {
      final delivery = transcriptUserDelivery(row);
      return TranscriptMessage._(
        kind: TranscriptMessageKind.notice,
        role: role,
        id: id,
        text: notice,
        noticeResult: transcriptNoticeResult(row),
        noticeDisclosure: delivery?.disclosure ?? 'View result',
        noticePlainText: delivery != null,
        noticeMonospace: delivery?.kind == 'process_notification',
      );
    }
    final review = reviewMessageText(row);
    if (review != null) {
      return TranscriptMessage._(
        kind: TranscriptMessageKind.review,
        role: role,
        id: id,
        text: review,
      );
    }
    final steering = steeringMessageText(row);
    if (steering != null) {
      return TranscriptMessage._(
        kind: TranscriptMessageKind.steering,
        role: role,
        id: id,
        text: steering,
      );
    }
    final user = role == 'user' ? UserMessageContent.fromMessage(row) : null;
    final content =
        user?.text ??
        (row['display_content'] ?? row['content'] ?? '').toString();
    if (content.isEmpty && (user?.attachments.isEmpty ?? true)) {
      return TranscriptMessage._(
        kind: TranscriptMessageKind.hidden,
        role: role,
        id: id,
      );
    }
    if (role == 'system') {
      final slash = _slashOutput.firstMatch(content);
      final command = row['_command'] as String? ?? slash?.group(1)?.trim();
      final output = slash == null ? content : slash.group(2)!.trim();
      final multiline = output.contains('\n');
      return TranscriptMessage._(
        kind: TranscriptMessageKind.system,
        role: role,
        id: id,
        text: command == null
            ? output
            : '$command${multiline ? '\n' : ' · '}$output',
        systemMultiline: multiline,
      );
    }
    if (role == 'tool') {
      return TranscriptMessage._(
        kind: TranscriptMessageKind.tool,
        role: role,
        id: id,
        tool: TranscriptToolResult.fromRow(row),
      );
    }
    return TranscriptMessage._(
      kind: TranscriptMessageKind.dialogue,
      role: role,
      id: id,
      text: content,
      copyText: role == 'user' ? answerMessageDisplayText(row) : content,
      attachments: user?.attachments ?? const [],
      timestamp: _timestamp(row['timestamp']),
    );
  }
}

final _slashOutput = RegExp(r'^slash:(/[^\n]+)\n([\s\S]*)$');

DateTime? _timestamp(Object? seconds) {
  // The existing transcript contract uses Unix seconds; unknown stays absent.
  if (seconds is! num || !seconds.isFinite || seconds.abs() > 8640000000000) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

/// Saved tool output copied independently of its mutable gateway/history row.
final class TranscriptToolResult {
  const TranscriptToolResult._({
    required this.id,
    required this.name,
    required this.text,
  });

  final Object? id;
  final String name;
  final String text;

  factory TranscriptToolResult.fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    return TranscriptToolResult._(
      id: id is int || id is String ? id : null,
      name: row['tool_name']?.toString() ?? 'Tool result',
      text: (row['display_content'] ?? row['content'] ?? '').toString(),
    );
  }
}
