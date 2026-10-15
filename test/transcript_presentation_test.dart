import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/transcript_presentation.dart';
import 'package:wing/core/models/transcript_reader.dart';
import 'package:wing/core/models/transcript_timeline.dart';

class _Reading implements TranscriptReader {
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
  double historyScrollOffset = 0;
  @override
  String streaming = '';
  @override
  Object messagePresentationId(Map<String, dynamic> row) => row['id']!;
  @override
  void recordScrollOffset(double offset) => historyScrollOffset = offset;

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
    final first = _Reading()..historyScrollOffset = 80;
    final second = _Reading()..historyScrollOffset = 20;
    final captured = first.capture();
    captured.recordScrollOffset(120);
    expect(first.historyScrollOffset, 120);
    expect(second.historyScrollOffset, 20);
    expect(captured.scrollOffset, 80);
    expect(first.capture().scrollOffset, 120);
  });
}
