import 'transcript_position.dart';

/// Reading facts and local scroll memory shared by live and saved chat views.
/// The transcript widget has no runtime or transport authority through this seam.
abstract interface class TranscriptReader {
  List<Map<String, dynamic>> get messages;
  String? get historySessionId;
  int? get nextHistoryOffset;
  bool get historyLoading;

  /// Includes a successful observation that no conversation exists yet.
  bool get historyAvailable;

  /// Loading requested older rows, rather than refreshing retained history.
  bool get historyPaging;
  String? get historyError;
  bool get historyUnavailable;
  TranscriptPosition get readingPosition;
  String get streaming;
  Object messagePresentationId(Map<String, dynamic> row);
  void recordReading(TranscriptBookmark? resume, {int? readThrough});
}
