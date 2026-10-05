import 'attachment_draft.dart';

class QueuedPromptDraft {
  final String text;
  final List<AttachmentDraft> attachments;
  final bool submissionUncertain;

  QueuedPromptDraft({
    required this.text,
    Iterable<AttachmentDraft> attachments = const [],
    this.submissionUncertain = false,
  }) : attachments = List.unmodifiable(attachments);
}
