import 'composer_reference.dart';
import 'attachment_draft.dart';

class QueuedPromptDraft {
  final String text;
  final List<ComposerReference> references;
  final List<AttachmentDraft> attachments;
  final bool submissionUncertain;

  QueuedPromptDraft({
    required this.text,
    Iterable<ComposerReference> references = const [],
    Iterable<AttachmentDraft> attachments = const [],
    this.submissionUncertain = false,
  }) : references = List.unmodifiable(references),
       attachments = List.unmodifiable(attachments);
}
