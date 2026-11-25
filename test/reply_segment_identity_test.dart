import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/transcript_reading.dart';
import 'package:wing/core/models/reading_snapshot_message.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/transcript_reading.dart';
import 'package:wing/core/models/transcript_notice.dart';

TranscriptReading reader() => TranscriptReading.passive(
  scope: WorkspaceScope(connectionId: 'c', profileName: 'p'),
);
Map<String, dynamic> delta(
  String text,
  int segment,
  int offset, [
  String turn = 'turn-a',
]) => {'turn_id': turn, 'segment': segment, 'offset': offset, 'text': text};
void main() {
  test(
    'refusal targets its exact input and partial turn, preserving later text',
    () {
      final reading = reader();
      reading.installSavedHistory([
        {'id': 1, 'role': 'assistant', 'content': 'Prior answer'},
      ]);
      reading.appendSubmittedPrompt(inputId: 'a', text: 'Same words');
      final original = reading.messages.last;
      final identity = reading.messagePresentationId(original);
      reading.observePromptAdmission('a', 'admission-a');
      reading.observeReplyAdmission('admission-a', turn: 'turn-a');
      reading.startReply({'turn_id': 'turn-a'});
      reading.sealReply({
        'turn_id': 'turn-a',
        'segment': 0,
        'text': 'Partial answer',
      }, turnGeneration: 1);
      reading.appendPrompt(text: 'Later steering', steering: true);
      reading.appendSubmittedPrompt(inputId: 'b', text: 'Same words');
      reading.appendReplyDelta(delta('More partial', 1, 0));
      const completion = {
        'turn_id': 'turn-a',
        'status': 'error',
        'failure_reason': 'content_policy_blocked',
      };
      expect(
        reading.refuseReply(completion, admission: 'admission-other'),
        isFalse,
      );
      expect(reading.refuseReply(completion, admission: 'admission-a'), isTrue);
      expect(reading.messages.map((row) => row['content']), [
        'Prior answer',
        'Same words',
        'Later steering',
        'Same words',
      ]);
      final refused = reading.messages[1];
      expect(reading.messagePresentationId(refused), same(identity));
      expect(contentRefusedNotice(refused), liveContentRefusedNotice);
      expect(reading.messages.last['display_kind'], isNull);
      expect(reading.streaming, isEmpty);
      expect(reading.appendReplyDelta(delta('late tail', 1, 12)), isFalse);
      reading.observePromptAdmission('b', 'admission-b');
      reading.observeReplyAdmission('admission-b', turn: 'turn-b');
      reading.startReply({'turn_id': 'turn-b'});
      reading.appendReplyDelta(delta('New answer', 0, 0, 'turn-b'));
      expect(
        reading.isSupersededReplyCompletion(completion, 'admission-a'),
        isTrue,
      );
      expect(
        reading.refuseReply(completion, admission: 'admission-a'),
        isFalse,
      );
      expect(reading.streaming, 'New answer');
    },
  );

  test('refusal without an input match waits for saved history', () {
    final reading = reader();
    reading.installSavedHistory([
      {'id': 1, 'role': 'user', 'content': 'Do not guess this prompt'},
    ]);
    reading.observeReplyAdmission('unknown-admission', turn: 'turn-a');
    reading.startReply({'turn_id': 'turn-a'});
    reading.sealReply({
      'turn_id': 'turn-a',
      'segment': 0,
      'text': 'Known refused partial',
    }, turnGeneration: 1);
    reading.appendReplyDelta(delta('Known refused tail', 1, 0));
    expect(
      reading.refuseReply({
        'failure_reason': 'content_policy_blocked',
      }, admission: 'unknown-admission'),
      isFalse,
    );
    expect(reading.messages.single['display_kind'], isNull);
    expect(reading.messages.single['content'], 'Do not guess this prompt');
    expect(reading.streaming, isEmpty);
  });
  test('active reply journal keeps notices between equal-text segments', () {
    final reading = reader();
    const prompt = {'id': 1, 'role': 'user', 'content': 'Prompt'};
    const page = ProfileHistoryPage('saved', [prompt], 0, 50);
    reading.installSavedPage(page);
    reading.observeReplyAdmission('admission-a');
    reading.observePendingReplyAdmissions(['admission-a']);
    reading.startReply({'turn_id': 'turn-a'});
    for (var segment = 0; segment < 3; segment++) {
      reading.sealReply({
        'turn_id': 'turn-a',
        'segment': segment,
        'text': segment < 2 ? 'Repeated text' : 'Last segment',
      }, turnGeneration: 1);
      if (segment < 2) reading.appendCommandNotice('Notice $segment');
    }
    final before = reading.messages.toList();
    reading.installSavedPage(page);
    expect(reading.messages.map((row) => row['content']), [
      'Prompt',
      'Repeated text',
      'Notice 0',
      'Repeated text',
      'Notice 1',
      'Last segment',
    ]);
    expect(reading.messages.skip(1), orderedEquals(before.skip(1)));
    reading.observePendingReplyAdmissions(['successor-admission']);
    reading.installSavedPage(
      const ProfileHistoryPage(
        'saved',
        [
          prompt,
          {'id': 2, 'role': 'assistant', 'content': 'Final saved answer'},
        ],
        0,
        50,
      ),
    );
    expect(reading.messages.map((row) => row['content']), [
      'Prompt',
      'Notice 0',
      'Notice 1',
      'Final saved answer',
    ]);
    expect(
      reading.messages.where((row) => row.containsKey('_reply_turn')),
      isEmpty,
    );
  });

  test(
    'steering preserves wire offsets without repeating its displayed prefix',
    () {
      final reading = reader()..startReply({'turn_id': 'turn-a'});
      reading.appendReplyDelta(delta('Before ', 0, 0));
      reading.splitReplyForSteering(turnGeneration: 1);
      reading.appendPrompt(text: 'Focus here', steering: true);
      reading.appendReplyDelta(delta('Before ', 0, 0));
      reading.appendReplyDelta(delta('after', 0, 7));
      expect(reading.streaming, 'after');
      reading.sealReply({
        'turn_id': 'turn-a',
        'segment': 0,
        'text': 'Before after',
      }, turnGeneration: 1);
      expect(reading.messages.map((row) => row['content']), [
        'Before ',
        'Focus here',
        'after',
      ]);
    },
  );
  test('completion after steering appends only the undisplayed suffix', () {
    final reading = reader()..startReply({'turn_id': 'turn-a'});
    reading.appendReplyDelta(delta('Before ', 0, 0));
    reading.splitReplyForSteering(turnGeneration: 1);
    reading.appendPrompt(text: 'Focus here', steering: true);
    reading.appendReplyDelta(delta('after', 0, 7));
    reading.appendAssistant(
      'Before after',
      turnGeneration: 1,
      reasoning: '',
      responseReused: false,
    );
    expect(reading.messages.map((row) => row['content']), [
      'Before ',
      'Focus here',
      'after',
    ]);
  });
  test('steering snapshot restores the wire prefix without duplicating it', () {
    final original = reader()..startReply({'turn_id': 'turn-a'});
    original.appendReplyDelta(delta('Before ', 0, 0));
    original.splitReplyForSteering(turnGeneration: 1);
    original.appendPrompt(text: 'Focus here', steering: true);
    original.appendReplyDelta(delta('after', 0, 7));
    final saved = original.captureSnapshot();
    final restored = reader()
      ..installSnapshot(
        TranscriptReadingSnapshot(
          messages: saved.messages.map(projectReadingSnapshotMessage),
          historySessionId: 'saved',
        ),
      );
    restored.applyReplySnapshot('Before after more');
    expect(restored.streaming, 'after more');
    restored.appendReplyDelta(delta('Before after more', 0, 0));
    restored.sealReply({
      'turn_id': 'turn-a',
      'segment': 0,
      'text': 'Before after more',
    }, turnGeneration: 1);
    expect(restored.messages.map((row) => row['content']), [
      'Before ',
      'Focus here',
      'after more',
    ]);
  });
  test(
    'a transformed final reply replaces raw streamed text even when reused',
    () {
      final reading = reader()..startReply({'turn_id': 'turn-a'});
      reading.appendReplyDelta(delta('raw output', 0, 0));
      reading.appendAssistant(
        'Authoritative final',
        turnGeneration: 1,
        reasoning: '',
        responseReused: true,
        responseTransformed: true,
      );
      expect(reading.messages.single['content'], 'Authoritative final');
    },
  );
  test('empty terminal reply retires its replay identity', () {
    final reading = reader()..startReply({'turn_id': 'turn-a'});
    reading.retireReply();
    expect(reading.appendReplyDelta(delta('late reply', 0, 0)), isFalse);
  });
  test(
    'restamped retired turn cannot replace the active execution admission',
    () {
      final reading = reader();
      reading.observeReplyAdmission('old-admission', turn: 'old');
      reading.startReply({'turn_id': 'old'});
      reading.appendReplyDelta(delta('old reply', 0, 0, 'old'));
      reading.observeReplyAdmission('active-admission', turn: 'active');
      reading.startReply({'turn_id': 'active'});
      reading.appendReplyDelta(delta('current reply', 0, 0, 'active'));
      reading.observeReplyAdmission('old-admission', turn: 'old');
      expect(reading.startReply({'turn_id': 'old'}), isFalse);
      reading.appendReplyDelta(delta(' more', 0, 13, 'active'));
      expect(
        reading.captureSnapshot().messages.last['_reply_admission'],
        'active-admission',
      );
    },
  );
  test(
    'UTF16 overlap, reordered fragments and replay seals have one display identity',
    () {
      final reading = reader();
      reading.startReply({'turn_id': 'turn-a'});
      reading.appendReplyDelta(delta('world', 0, 4));
      expect(reading.streaming, isEmpty);
      reading.appendReplyDelta(delta('A😀 ', 0, 0));
      expect(reading.streaming, 'A😀 world');
      reading.appendReplyDelta(delta(' world!', 0, 3));
      expect(reading.streaming, 'A😀 world!');
      reading.sealReply({
        'turn_id': 'turn-a',
        'segment': 0,
        'text': 'A😀 world!',
      }, turnGeneration: 1);
      final identity = reading.messagePresentationId(reading.messages.single);
      reading.startReply({'turn_id': 'turn-a'});
      reading.appendReplyDelta(delta('A😀 world!', 0, 0));
      reading.sealReply({
        'turn_id': 'turn-a',
        'segment': 0,
        'text': 'A😀 world!',
      }, turnGeneration: 1);
      expect(reading.messages, hasLength(1));
      expect(reading.messagePresentationId(reading.messages.single), identity);
      expect(reading.streaming, isEmpty);
      reading.appendReplyDelta(delta('A😀 world!', 1, 0));
      reading.sealReply({
        'turn_id': 'turn-a',
        'segment': 1,
        'text': 'A😀 world!',
      }, turnGeneration: 1);
      expect(reading.messages, hasLength(2));
      reading.appendAssistant(
        'final',
        turnGeneration: 1,
        reasoning: '',
        responseReused: false,
      );
      reading.startReply({'turn_id': 'turn-b'});
      reading.appendReplyDelta(delta('A😀 world!', 0, 0, 'turn-b'));
      expect(reading.streaming, 'A😀 world!');
      expect(reading.startReply({'turn_id': 'turn-a'}), isFalse);
    },
  );
  test(
    'preview completion replaces structurally selected interim without text matching',
    () {
      final reading = reader();
      reading.startReply({'turn_id': 'turn-a'});
      reading.sealReply({
        'turn_id': 'turn-a',
        'segment': 0,
        'text': 'preview',
      }, turnGeneration: 1);
      reading.appendAssistant(
        'canonical final',
        turnGeneration: 1,
        reasoning: '',
        responseReused: false,
        responsePreviewed: true,
      );
      expect(reading.messages.single['content'], 'canonical final');
    },
  );
  test(
    'cold journal is scoped to active admission, not a queued successor',
    () {
      final original = reader();
      original.observeReplyAdmission('admission-a');
      original.startReply({'turn_id': 'turn-a'});
      original.sealReply({
        'turn_id': 'turn-a',
        'segment': 0,
        'text': 'interim',
      }, turnGeneration: 1);
      original.appendReplyDelta(delta('partial', 1, 0));
      final saved = original.captureSnapshot();
      final restored = reader()
        ..installSnapshot(
          TranscriptReadingSnapshot(
            messages: saved.messages.map(projectReadingSnapshotMessage),
            historySessionId: 'saved',
          ),
        );
      restored.observePendingReplyAdmissions(['admission-a']);
      restored.applyReplySnapshot(null);
      restored.installSavedPage(
        const ProfileHistoryPage(
          'saved',
          [
            {'id': 1, 'role': 'user', 'content': 'prompt'},
          ],
          0,
          50,
        ),
      );
      expect(restored.streaming, 'partial');
      expect(restored.messages.map((r) => r['content']), ['prompt', 'interim']);
      restored.appendReplyDelta(delta('partial plus', 1, 0));
      expect(restored.streaming, 'partial plus');
      restored.observePendingReplyAdmissions(['admission-b']);
      restored.installSavedPage(
        const ProfileHistoryPage(
          'saved',
          [
            {'id': 1, 'role': 'user', 'content': 'prompt'},
            {'id': 2, 'role': 'assistant', 'content': 'saved answer'},
          ],
          0,
          50,
        ),
      );
      expect(restored.streaming, isEmpty);
      expect(restored.messages.map((r) => r['content']), [
        'prompt',
        'saved answer',
      ]);
    },
  );
}
