import 'transcript_reader.dart';
import 'transcript_timeline.dart';

/// One captured frame of a conversation. The viewport never reads mutable
/// session facts while comparing its previous and next frames.
///
/// Transport, refresh and command admission remain with the session. The only
/// retained write is local reading-position memory for this exact reader.
final class TranscriptPresentation {
  TranscriptPresentation.capture({
    required this.identity,
    required TranscriptReader reader,
    required this.timeline,
    required this.needsInput,
    required this.turnAdmissionBlocked,
  }) : readingIdentity = reader,
       history = TranscriptHistoryPresentation._(
         loading: reader.historyLoading,
         available: reader.historyAvailable,
         paging: reader.historyPaging,
         unavailable: reader.historyUnavailable,
         error: reader.historyError,
         hasOlder: reader.nextHistoryOffset != null,
       ),
       segment = reader.historySessionId,
       streaming = reader.streaming,
       hasMessages = reader.messages.isNotEmpty,
       scrollOffset = reader.historyScrollOffset,
       _recordScrollOffset = reader.recordScrollOffset;

  final Object identity;
  final Object readingIdentity;
  final TranscriptTimeline timeline;
  final TranscriptHistoryPresentation history;
  final String? segment;
  final String streaming;
  final bool hasMessages;
  final bool needsInput;
  final bool turnAdmissionBlocked;
  final double scrollOffset;
  final void Function(double) _recordScrollOffset;

  bool get isEmpty => !hasMessages && streaming.isEmpty;
  bool get blocksReading =>
      history.loading && (history.paging || !history.available && isEmpty);

  void recordScrollOffset(double offset) => _recordScrollOffset(offset);
}

/// Availability is an observation of the transcript, never inferred from
/// runtime metadata or from whether a refresh command is available.
final class TranscriptHistoryPresentation {
  const TranscriptHistoryPresentation._({
    required this.loading,
    required this.available,
    required this.paging,
    required this.unavailable,
    required this.error,
    required this.hasOlder,
  });

  final bool loading, available, paging, unavailable, hasOlder;
  final String? error;
}
