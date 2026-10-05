import 'attachment_draft.dart';
import 'composer_action.dart';

/// Identity belongs to the queue entry, not a particular uncertainty snapshot.
final class ComposerQueueId {
  ComposerQueueId();
}

final class ComposerAttachmentObservation {
  const ComposerAttachmentObservation({
    required this.id,
    required this.name,
    required this.mediaType,
    required this.kind,
    required this.status,
    required this.error,
    required this.refText,
  });

  final String id;
  final String name;
  final String mediaType;
  final AttachmentDraftKind kind;
  final AttachmentDraftStatus status;
  final String? error;
  final String? refText;
  bool get isImage => kind == AttachmentDraftKind.image;
}

final class ComposerQueueObservation {
  ComposerQueueObservation({
    required this.id,
    required this.text,
    required Iterable<ComposerAttachmentObservation> attachments,
    required this.submissionUncertain,
  }) : attachments = List.unmodifiable(attachments);

  final ComposerQueueId id;
  final String text;
  final List<ComposerAttachmentObservation> attachments;
  final bool submissionUncertain;
}

enum ComposerUnavailableReason {
  dictation,
  reconnect,
  saving,
  preparingAttachment,
  empty,
  disconnectedCommand,
  currentTurn,
  steering,
  needsRunningTurn,
  textOnly,
  textRequired,
  sending,
  queueDuringTurn,
  savedAnswerRequired,
}

/// Runtime facts are read-only input. They never transfer runtime ownership.
final class ComposerRuntimeObservation {
  const ComposerRuntimeObservation({
    required this.runtimeId,
    required this.working,
    required this.canSteer,
    required this.connected,
    required this.automaticDrainAvailable,
    required this.switching,
    required this.changingAnswer,
    required this.commandRunning,
    required this.changingIntelligence,
    required this.canForkSavedAnswer,
    required this.failedOrCancelled,
    required this.historyAvailable,
  });

  final String runtimeId;

  final bool working;
  final bool canSteer;
  final bool connected;

  /// Automatic sending requires positively observed access and live transport.
  /// Optimistic availability offered by the UI does not grant this authority.
  final bool automaticDrainAvailable;
  final bool switching;
  final bool changingAnswer;
  final bool commandRunning;
  final bool changingIntelligence;
  final bool canForkSavedAnswer;
  final bool failedOrCancelled;
  final bool historyAvailable;
}

final class ComposerObservation {
  ComposerObservation({
    required this.revision,
    required this.text,
    required this.submissionUncertain,
    required Iterable<ComposerAttachmentObservation> attachments,
    required Iterable<ComposerQueueObservation> queue,
    required this.editing,
    required this.editText,
    required this.paused,
    required this.saving,
    required this.draining,
    required this.preparing,
    required this.sending,
    required this.steering,
    required this.restored,
    required this.error,
  }) : attachments = List.unmodifiable(attachments),
       queue = List.unmodifiable(queue);

  final int revision;
  final String text;
  final bool submissionUncertain;
  final List<ComposerAttachmentObservation> attachments;
  final List<ComposerQueueObservation> queue;
  final ComposerQueueId? editing;
  final String editText;
  final bool paused;
  final bool saving;
  final bool draining;
  final bool preparing;
  final bool sending;
  final bool steering;
  final bool restored;
  final String? error;
  String get displayedText => editing == null ? text : editText;
  ComposerQueueObservation? get editingEntry =>
      queue.where((item) => identical(item.id, editing)).firstOrNull;
}

/// A captured claim on outgoing work; only its issuing owner can settle it.
final class ComposerSubmission {
  ComposerSubmission({
    required this.text,
    required Iterable<ComposerAttachmentObservation> attachments,
  }) : attachments = List.unmodifiable(attachments);

  final String text;
  final List<ComposerAttachmentObservation> attachments;
}

final class ComposerTransfer {
  ComposerTransfer();
}

final class ComposerSavedWork {
  ComposerSavedWork({
    required this.text,
    required Iterable<ComposerAttachmentObservation> attachments,
    required Iterable<ComposerQueueObservation> queuedPrompts,
    required this.queuePaused,
  }) : attachments = List.unmodifiable(attachments),
       queuedPrompts = List.unmodifiable(queuedPrompts);
  final String text;
  final List<ComposerAttachmentObservation> attachments;
  final List<ComposerQueueObservation> queuedPrompts;
  final bool queuePaused;
}

enum ComposerDelivery { definitelyUnsent, uncertain, accepted }

final class ComposerPauseCapture {
  const ComposerPauseCapture();
}

/// The adapter gets bytes/metadata, never the mutable owned attachment record.
final class ComposerUpload {
  const ComposerUpload({
    required this.name,
    required this.isImage,
    required this.dataUrl,
  });

  final String name;
  final bool isImage;
  final String dataUrl;
}

final class ComposerActions {
  ComposerActions(
    Map<ComposerAction, ComposerUnavailableReason?> reasons, {
    required this.canFork,
    required this.canEditQueue,
    required this.canSaveQueueEdit,
    required this.canSteerQueueEdit,
    required this.prefersRunningAction,
    required this.hasMessageActions,
    required Iterable<ComposerAction> offered,
    required this.canResumeQueue,
    required this.editingBusy,
    required this.canEditText,
  }) : unavailable = Map.unmodifiable(reasons),
       offered = Set.unmodifiable(offered);

  final Map<ComposerAction, ComposerUnavailableReason?> unavailable;
  final bool canFork;
  final bool canEditQueue;
  final bool canSaveQueueEdit;
  final bool canSteerQueueEdit;
  final bool prefersRunningAction;
  final bool hasMessageActions;
  final Set<ComposerAction> offered;
  final bool canResumeQueue;
  final bool editingBusy;
  final bool canEditText;
}
