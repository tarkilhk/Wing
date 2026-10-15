/// A stable saved message and the point within it at the viewport's top.
/// Fractions survive changes to typography and viewport size.
final class TranscriptBookmark {
  const TranscriptBookmark({
    required this.messageId,
    this.fraction = 0,
    this.alignment = 0,
  });
  final int messageId;
  final double fraction;
  final double alignment;
}

/// Resume may move backwards; readThrough can only move forwards.
final class TranscriptPosition {
  const TranscriptPosition({this.resume, this.readThrough});
  final TranscriptBookmark? resume;
  final int? readThrough;
}
