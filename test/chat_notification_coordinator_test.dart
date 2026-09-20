import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/chat_notification_content.dart';
import 'package:wing/core/models/notification_focus.dart';
import 'package:wing/core/services/chat_notification_coordinator.dart';
import 'package:wing/core/services/turn_notification_service.dart';
import 'support/recording_turn_notification_sink.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late RecordingTurnNotificationSink sink;
  late ChatNotificationCoordinator notices;
  const chat =
      '{"connection":"home","connection_identity":"owner","profile":"default","session":"chat"}';
  Future<void> reply(String id, {bool alert = true}) => notices.result(
    chat: chat,
    title: 'Build site',
    scope: 'Home / default',
    focus: NotificationFocus('answer', id),
    content: ChatNotificationContent.reply('Answer $id'),
    alert: alert,
  );
  NotificationInput approval(String id, {bool submitting = false}) =>
      NotificationInput(
        focus: NotificationFocus('approval', id),
        content: ChatNotificationContent.approval(
          'npm run build $id',
          'Run build',
        ),
        choices: const ['once', 'session', 'always', 'deny'],
        submitting: submitting,
      );
  Future<void> inputs(List<NotificationInput> values, {bool alert = true}) =>
      notices.inputs(
        chat: chat,
        title: 'Build site',
        scope: 'Home / default',
        inputs: values,
        alert: alert,
      );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sink = RecordingTurnNotificationSink();
    notices = ChatNotificationCoordinator(prefs, sink);
  });
  test(
    'latest answer replaces the same chat slot; an old read cannot clear it',
    () async {
      await reply('a');
      expect(sink.shown.last.body, 'Answer a');
      await reply('b');
      expect(sink.shown.last.body, 'Answer b');
      expect(sink.shown.last.expandedBody, 'Answer b');
      expect(sink.shown.map((n) => n.id).toSet(), hasLength(1));
      await notices.read(chat, 'answer:a');
      expect(sink.cancelled, isEmpty);
      await notices.read(chat, 'answer:b');
      expect(sink.cancelled, [sink.shown.last.id]);
    },
  );
  test(
    'input wins over a newer answer and exposes it after resolution',
    () async {
      await inputs([approval('a')]);
      final id = sink.shown.last.id;
      await reply('r');
      expect(sink.shown.last.focus!.kind, 'approval');
      await inputs([]);
      expect(sink.shown.last.focus!.identity, 'answer:r');
      expect(sink.shown.every((n) => n.id == id), isTrue);
    },
  );
  test(
    'mixed inputs keep first-seen FIFO and count questions, not envelopes',
    () async {
      final q = NotificationInput(
        focus: const NotificationFocus('question', 'q'),
        content: ChatNotificationContent.input('Which environment?'),
        count: 3,
      );
      await inputs([q]);
      await inputs([approval('a'), approval('b'), q]);
      expect(sink.shown.last.focus!.identity, 'question:q');
      expect(sink.shown.last.pending, '3 questions · 2 approvals');
      await inputs([approval('a'), approval('b')]);
      expect(sink.shown.last.focus!.identity, 'approval:a');
      expect(sink.shown.last.alert, isTrue);
    },
  );
  test(
    'dismissal survives restart and refresh; a new request restores notice',
    () async {
      await inputs([approval('a')]);
      await notices.dismissed(chat, sink.shown.last.revision!);
      notices = ChatNotificationCoordinator(prefs, sink);
      final count = sink.shown.length;
      await inputs([approval('a')]);
      expect(sink.shown, hasLength(count));
      await inputs([approval('a'), approval('b')]);
      expect(sink.shown, hasLength(count + 1));
      expect(sink.shown.last.focus!.identity, 'approval:a');
    },
  );
  test(
    'pending submission stays visible, disables controls, and updates quietly',
    () async {
      await inputs([approval('a')]);
      await inputs([approval('a', submitting: true)]);
      expect(sink.cancelled, isEmpty);
      expect(sink.shown.last.submitting, isTrue);
      expect(sink.shown.last.alert, isFalse);
      await inputs([approval('b')]);
      expect(sink.shown.last.alert, isTrue);
    },
  );
  test('preview-off hides approval details and permission controls', () async {
    await prefs.setBool(notificationPreviewsKey, false);
    await inputs([approval('a')]);
    expect(sink.shown.last.choices, isEmpty);
    expect(sink.shown.last.expandedBody, 'Approval needed');
    expect(sink.shown.last.pending, '1 approval');
  });
  test('silent startup baseline cannot resurrect an old request', () async {
    await inputs([approval('a')], alert: false);
    expect(sink.shown, isEmpty);
    await inputs([approval('a'), approval('b')]);
    expect(sink.shown, hasLength(1));
  });
  test(
    'read state persists; another connection has an independent slot',
    () async {
      await reply('a');
      await notices.read(chat, 'answer:a');
      notices = ChatNotificationCoordinator(prefs, sink);
      expect(notices.resultFor(chat), isNull);
      final other = jsonEncode({
        ...jsonDecode(chat) as Map<String, dynamic>,
        'connection': 'other',
      });
      await notices.result(
        chat: other,
        title: 'Build site',
        scope: 'Other / default',
        focus: const NotificationFocus('answer', 'b'),
        content: ChatNotificationContent.reply('Different'),
      );
      expect(sink.shown.first.id, isNot(sink.shown.last.id));
    },
  );
  test('reading a hidden answer never resolves the pending input', () async {
    await reply('a');
    await inputs([approval('b')]);
    await notices.read(chat, 'answer:a');
    expect(sink.cancelled, isEmpty);
    expect(sink.shown.last.focus!.kind, 'approval');
    await inputs([]);
    expect(sink.cancelled, hasLength(1));
  });
}
