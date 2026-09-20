import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_notification_content.dart';
import '../models/notification_focus.dart';
import 'turn_notification_service.dart';

/// An immutable input snapshot. Secret values never belong here.
class NotificationInput {
  final NotificationFocus focus;
  final ChatNotificationContent content;
  final List<String> choices;
  final int count;
  final bool submitting;
  final String? error;
  const NotificationInput({
    required this.focus,
    required this.content,
    this.choices = const [],
    this.count = 1,
    this.submitting = false,
    this.error,
  });
  Map<String, dynamic> toJson() => {
    'focus': focus.toJson(),
    'content': content.toJson(),
    'choices': choices,
    'count': count,
    'submitting': submitting,
    'error': error,
  };
  factory NotificationInput.fromJson(
    Map<String, dynamic> data,
  ) => NotificationInput(
    focus: NotificationFocus.fromJson(Map<String, dynamic>.from(data['focus'])),
    content: ChatNotificationContent.fromJson(
      Map<String, dynamic>.from(data['content']),
    ),
    choices: List<String>.from(data['choices']),
    count: data['count'] as int,
    // A process restart cannot leave the UI stuck in an in-flight submission.
    error: data['error'] as String?,
  );
}

class _ChatNotice {
  String title;
  String scope;
  Map<String, dynamic>? result;
  List<NotificationInput> inputs = [];
  String? dismissed;
  String? posted;
  String? rendered;
  _ChatNotice(this.title, this.scope);
  Map<String, dynamic> toJson() => {
    'title': title,
    'scope': scope,
    'result': result,
    'inputs': inputs.map((v) => v.toJson()).toList(),
    'dismissed': dismissed,
    'posted': posted,
    'rendered': rendered,
  };
}

/// One durable state per scoped chat. Rendering and writes are serialized so a
/// delayed permission check or stale read callback cannot replace a newer state.
class ChatNotificationCoordinator {
  static const storageKey = 'chat_notification_state';
  final SharedPreferences preferences;
  final TurnNotificationSink sink;
  final Map<String, _ChatNotice> _chats = {};
  Future<void> _tail = Future.value();
  ChatNotificationCoordinator(this.preferences, this.sink) {
    final stored = preferences.getString(storageKey);
    if (stored == null) return;
    try {
      for (final entry
          in (jsonDecode(stored) as Map<String, dynamic>).entries) {
        final data = Map<String, dynamic>.from(entry.value);
        final state = _ChatNotice(
          data['title'] as String,
          data['scope'] as String,
        );
        state.result = data['result'] == null
            ? null
            : Map<String, dynamic>.from(data['result']);
        state.inputs = (data['inputs'] as List)
            .map(
              (v) => NotificationInput.fromJson(Map<String, dynamic>.from(v)),
            )
            .toList();
        state.dismissed = data['dismissed'] as String?;
        state.posted = data['posted'] as String?;
        state.rendered = data['rendered'] as String?;
        _chats[entry.key] = state;
      }
    } on Object {
      // Invalid local state cannot be used to target a request.
      _chats.clear();
    }
  }

  Future<void> _write() => preferences.setString(
    storageKey,
    jsonEncode(_chats.map((key, value) => MapEntry(key, value.toJson()))),
  );
  Future<void> _serialize(Future<void> Function() work) {
    final next = _tail.then((_) => work());
    _tail = next.catchError((Object _) {});
    return next;
  }

  Map<String, dynamic>? resultFor(String chat) => _chats[chat]?.result;
  NotificationInput? inputFor(String chat) => _chats[chat]?.inputs.firstOrNull;
  bool hasNotice(String chat) => _chats[chat]?.posted != null;
  Iterable<String> get chatsWithNotices => _chats.entries
      .where((entry) => entry.value.posted != null)
      .map((entry) => entry.key);

  Future<void> result({
    required String chat,
    required String title,
    required String scope,
    required NotificationFocus focus,
    required ChatNotificationContent content,
    bool alert = true,
  }) => _serialize(() async {
    final state = _chats.putIfAbsent(chat, () => _ChatNotice(title, scope));
    state.title = title;
    state.scope = scope;
    if (state.result?['identity'] == focus.identity) return;
    state.result = {
      'identity': focus.identity,
      'focus': focus.toJson(),
      'content': content.toJson(),
    };
    await _render(chat, state, alert: alert);
    await _write();
  });

  Future<void> inputs({
    required String chat,
    required String title,
    required String scope,
    required List<NotificationInput> inputs,
    bool alert = true,
  }) => _serialize(() async {
    final state = _chats.putIfAbsent(chat, () => _ChatNotice(title, scope));
    state.title = title;
    state.scope = scope;
    // Preserve first-seen order across request kinds, refreshes and restarts.
    final remaining = {for (final input in inputs) input.focus.identity: input};
    final ordered = <NotificationInput>[];
    for (final previous in state.inputs) {
      final fresh = remaining.remove(previous.focus.identity);
      if (fresh != null) ordered.add(fresh);
    }
    ordered.addAll(remaining.values);
    state.inputs = ordered;
    await _render(chat, state, alert: alert);
    await _write();
  });

  Future<void> read(String chat, String identity) => _serialize(() async {
    final state = _chats[chat];
    if (state == null || state.result?['identity'] != identity) return;
    state.result = null;
    await _render(chat, state, alert: false);
    await _write();
  });

  Future<void> dismissed(String chat, String revision) => _serialize(() async {
    final state = _chats[chat];
    if (state == null || state.posted != revision) return;
    state.dismissed = revision;
    state.posted = null;
    state.rendered = null;
    await _write();
  });

  Future<void> refreshPreferences() => _serialize(() async {
    for (final entry in _chats.entries) {
      entry.value.rendered = null;
      await _render(entry.key, entry.value, alert: false);
    }
    await _write();
  });

  Future<void> _render(
    String chat,
    _ChatNotice state, {
    required bool alert,
  }) async {
    final first = state.inputs.firstOrNull;
    final result = state.result;
    if (first == null && result == null) {
      if (state.posted != null) {
        await sink.cancel(TurnNotificationService.notificationIdFor(chat));
      }
      state.posted = null;
      state.rendered = null;
      return;
    }
    final content =
        first?.content ??
        ChatNotificationContent.fromJson(
          Map<String, dynamic>.from(result!['content']),
        );
    final enabled =
        preferences.getBool(
          content.needsAttention
              ? attentionNotificationsKey
              : completionNotificationsKey,
        ) ??
        true;
    if (!enabled) {
      if (state.posted != null) {
        await sink.cancel(TurnNotificationService.notificationIdFor(chat));
      }
      state.posted = null;
      state.rendered = null;
      return;
    }
    final focus =
        first?.focus ??
        NotificationFocus.fromJson(Map<String, dynamic>.from(result!['focus']));
    final revision = first == null
        ? focus.identity
        : jsonEncode(
            state.inputs
                .map((v) => [v.focus.identity, v.count, v.content.preview])
                .toList(),
          );
    // Silent baselines may reconcile existing alerts but never post history.
    if (state.dismissed == revision || (!alert && state.posted == null)) return;
    final preview = preferences.getBool(notificationPreviewsKey) ?? true;
    final counts = <String, int>{};
    for (final input in state.inputs) {
      counts.update(
        input.focus.kind,
        (n) => n + input.count,
        ifAbsent: () => input.count,
      );
    }
    final pending = counts.entries
        .map(
          (e) => switch (e.key) {
            'approval' => '${e.value} approval${e.value == 1 ? '' : 's'}',
            'question' => '${e.value} question${e.value == 1 ? '' : 's'}',
            _ => '${e.value} secure input${e.value == 1 ? '' : 's'}',
          },
        )
        .join(' · ');
    final payload = jsonEncode({
      ...jsonDecode(chat) as Map<String, dynamic>,
      'focus': focus.toJson(),
      'revision': revision,
    });
    final notification = TurnNotification.chat(
      payload: payload,
      chatIdentity: chat,
      title: state.title,
      scopeLabel: state.scope,
      content: content,
      showPreview: preview,
      focus: focus,
      revision: revision,
      choices: preview ? first?.choices ?? const [] : const [],
      pending: pending,
      submitting: first?.submitting ?? false,
      actionError: first?.error,
      alert: alert && state.posted != revision,
    );
    final rendered = jsonEncode(notification.toJson());
    if (state.rendered == rendered) return;
    if (await sink.notificationsEnabled() == false) return;
    await sink.show(notification);
    state.posted = revision;
    state.rendered = rendered;
  }
}
