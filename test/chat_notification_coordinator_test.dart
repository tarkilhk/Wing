import 'package:wing/core/models/recent_conversation.dart';
import 'package:wing/core/models/notification_input.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/chat_notification_content.dart';
import 'package:wing/core/models/notification_focus.dart';
import 'package:wing/core/services/chat_notification_coordinator.dart';
import 'support/recording_turn_notification_sink.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late AppPreferences appPreferences;
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
    appPreferences = AppPreferences(prefs);
    sink = RecordingTurnNotificationSink();
    notices = ChatNotificationCoordinator(
      prefs,
      sink,
      appPreferences: appPreferences,
    );
  });
  tearDown(() => appPreferences.dispose());
  test(
    'read-only activity projects fresh journal facts without native permission',
    () async {
      sink.permissionResult = false;
      final events = <ChatNoticeActivity>[];
      notices.activity.addListener(() {
        if (notices.activity.value case final event?) events.add(event);
      });
      await reply('quiet', alert: false);
      await inputs([approval('baseline')], alert: false);
      expect(events, isEmpty);
      await reply('fresh');
      await reply('fresh');
      expect(events.single.kind, ConversationActivityKind.reply);
      expect(events.single.key.workspace.connectionIdentity, 'owner');
      await inputs([approval('baseline'), approval('new')]);
      await inputs([approval('baseline'), approval('new', submitting: true)]);
      expect(events, hasLength(2));
      expect(events.last.kind, ConversationActivityKind.inputNeeded);
      expect(events.last.identity, 'approval:new');
    },
  );

  test(
    'input observations detach retained choices before queued delivery',
    () async {
      final choices = ['once', 'deny'];
      final captured = NotificationInput(
        focus: const NotificationFocus('approval', 'captured'),
        content: ChatNotificationContent.approval('run', 'Run'),
        choices: choices,
      );
      final source = [captured];
      final delivery = inputs(source);
      choices.add('always');
      source.clear();
      await delivery;
      expect(sink.shown.single.focus?.identity, 'approval:captured');
      expect(sink.shown.single.choices, ['once', 'deny']);
      expect(notices.inputFor(chat)?.choices, ['once', 'deny']);
      expect(() => captured.choices.add('always'), throwsUnsupportedError);
    },
  );

  test(
    'restoration silently redraws only the current unread revision',
    () async {
      await reply('old');
      await reply('latest');
      final posted = sink.shown.last;
      sink = RecordingTurnNotificationSink();
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
      await notices.restore(owns: (_) => true);
      expect(sink.shown, hasLength(1));
      expect(sink.shown.single.id, posted.id);
      expect(sink.shown.single.revision, posted.revision);
      expect(sink.shown.single.body, 'Answer latest');
      expect(sink.shown.single.alert, isFalse);
      await notices.read(chat, 'answer:old');
      expect(sink.cancelled, isEmpty);
      await notices.read(chat, 'answer:latest');
      expect(sink.cancelled, [posted.id]);
    },
  );
  for (final disposition in ['read', 'dismissed', 'silent baseline']) {
    test('restoration does not revive $disposition', () async {
      await reply('a', alert: disposition != 'silent baseline');
      if (disposition == 'read') await notices.read(chat, 'answer:a');
      if (disposition == 'dismissed') {
        await notices.dismissed(chat, sink.shown.single.revision!);
      }
      sink = RecordingTurnNotificationSink();
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
      await notices.restore(owns: (_) => true);
      expect(sink.shown, isEmpty);
    });
  }
  test(
    'restoration respects current preview and category preferences',
    () async {
      await inputs([approval('a')]);
      await appPreferences.setNotificationPreviews(false);
      sink = RecordingTurnNotificationSink();
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
      await notices.restore(owns: (_) => true);
      expect(sink.shown.single.choices, isEmpty);
      expect(sink.shown.single.body, 'Approval needed');
      expect(sink.shown.single.pending, '1 approval');
      expect(sink.shown.single.alert, isFalse);
      await appPreferences.setAttentionNotifications(false);
      sink = RecordingTurnNotificationSink();
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
      await notices.restore(owns: (_) => true);
      expect(sink.shown, isEmpty);
      expect(sink.cancelled, hasLength(1));
    },
  );
  test(
    'restoration discards notices whose saved owner is no longer current',
    () async {
      await reply('a');
      sink = RecordingTurnNotificationSink();
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
      await notices.restore(owns: (_) => false);
      expect(sink.shown, isEmpty);
      expect(sink.cancelled, hasLength(1));
      expect(notices.resultFor(chat), isNull);
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
      await notices.restore(owns: (_) => true);
      expect(sink.shown, isEmpty);
    },
  );

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
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
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
    await appPreferences.setNotificationPreviews(false);
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
      notices = ChatNotificationCoordinator(
        prefs,
        sink,
        appPreferences: appPreferences,
      );
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
