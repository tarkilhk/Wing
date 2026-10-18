import 'package:wing/core/models/hermes_question.dart';
import 'package:wing/core/models/transcript_position.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/transcript_presentation.dart';
import 'package:wing/core/models/transcript_reader.dart';
import 'package:wing/core/models/transcript_timeline.dart';

class _Reading implements TranscriptReader {
  @override
  Iterable<PositionedHermesQuestion> get requestActivities => const [];
  @override
  List<Map<String, dynamic>> messages = [];
  @override
  String? historySessionId;
  @override
  int? nextHistoryOffset;
  @override
  bool historyLoading = true;
  @override
  bool historyAvailable = false;
  @override
  bool historyPaging = false;
  @override
  String? historyError;
  @override
  bool historyUnavailable = false;
  @override
  TranscriptPosition readingPosition = const TranscriptPosition();
  @override
  String streaming = '';
  @override
  Object messagePresentationId(Map<String, dynamic> row) => row['id']!;
  @override
  void recordReading(TranscriptBookmark? resume, {int? readThrough}) =>
      readingPosition = TranscriptPosition(
        resume: resume,
        readThrough: readThrough,
      );

  TranscriptPresentation capture() => TranscriptPresentation.capture(
    identity: 'conversation',
    reader: this,
    timeline: TranscriptTimeline.project(
      messages,
      presentationId: messagePresentationId,
    ),
    needsInput: false,
    turnAdmissionBlocked: false,
  );
}

void main() {
  test(
    'a retained frame cannot observe a later loading or history mutation',
    () {
      final reader = _Reading();
      final opening = reader.capture();
      expect(opening.blocksReading, isTrue);
      reader
        ..messages = [
          {'id': 1, 'role': 'assistant', 'content': 'Saved answer'},
        ]
        ..historySessionId = 'saved'
        ..historyAvailable = true
        ..historyLoading = false;
      final ready = reader.capture();
      expect(opening.isEmpty, isTrue);
      expect(opening.history.available, isFalse);
      expect(opening.segment, isNull);
      expect(opening.blocksReading, isTrue);
      expect(ready.isEmpty, isFalse);
      expect(ready.blocksReading, isFalse);
      reader
        ..historyLoading = true
        ..historyError = 'Refresh failed'
        ..nextHistoryOffset = 20;
      final refresh = reader.capture();
      expect(ready.history.loading, isFalse);
      expect(ready.history.error, isNull);
      expect(ready.history.hasOlder, isFalse);
      expect(refresh.blocksReading, isFalse);
      expect(refresh.history.hasOlder, isTrue);
      expect(refresh.timeline.entries.single.message.text, 'Saved answer');
    },
  );

  test('reading position writes stay with the captured conversation', () {
    final first = _Reading()
      ..recordReading(const TranscriptBookmark(messageId: 80));
    final second = _Reading()
      ..recordReading(const TranscriptBookmark(messageId: 20));
    final captured = first.capture();
    captured.recordReading(const TranscriptBookmark(messageId: 120));
    expect(first.readingPosition.resume?.messageId, 120);
    expect(second.readingPosition.resume?.messageId, 20);
    expect(captured.readingPosition.resume?.messageId, 80);
    expect(first.capture().readingPosition.resume?.messageId, 120);
  });
}
