part of 'profile_workspace_controller.dart';

class ProfileInputNotification {
  final ProfileSessionKey key;
  final String title;
  final String connectionLabel;
  final List<NotificationInput> inputs;
  final bool alert;
  const ProfileInputNotification(
    this.key,
    this.title,
    this.connectionLabel,
    this.inputs,
    this.alert,
  );
}

extension ProfileNotificationState on ProfileWorkspaceController {
  Map<String, int> get notificationMonitoringCounts {
    final counts = <String, int>{};
    for (final chat in notificationChats) {
      final String? state;
      if (chat.status == ProfileTurnStatus.reconnecting && chat.busy) {
        state = 'reconnecting';
      } else if (chat.approval != null) {
        state = 'need approval';
      } else if (chat.pendingQuestion != null || chat.sensitivePrompt != null) {
        state = 'need input';
      } else if (chat.busy ||
          chat.commandRunning ||
          chat.queueDraining ||
          chat.subagents.any((s) => !s.isTerminal)) {
        state = 'working';
      } else {
        state = null;
      }
      if (state != null) counts.update(state, (v) => v + 1, ifAbsent: () => 1);
    }
    final background = _backgroundChats.entries
        .where((e) => !_hasLoadedNotificationChat(e.key, e.value.sessionId))
        .length;
    if (background > 0) {
      counts.update(
        'working',
        (v) => v + background,
        ifAbsent: () => background,
      );
    }
    return counts;
  }

  Iterable<ProfileChat> get notificationChats =>
      _resources.values.expand((r) => r.chats.values);
  ProfileChat? findNotificationChat(ProfileSessionKey key) =>
      _resources[key.workspace]?.chats[key.sessionId];

  List<NotificationInput> _notificationInputs(ProfileChat chat) {
    final result = <NotificationInput>[];
    for (final raw in chat.approvals.requests) {
      final request = GatewayApprovalRequest.fromEventData(raw);
      result.add(
        NotificationInput(
          focus: NotificationFocus('approval', raw['request_id'] as String),
          content: ChatNotificationContent.approval(
            request.command,
            request.description,
          ),
          choices: request.choices.map((v) => v.wireValue).toList(),
          submitting: chat.approvalResponding && identical(raw, chat.approval),
          error: chat.notificationActionErrorRequestId == raw['request_id']
              ? chat.notificationActionError
              : null,
        ),
      );
    }
    final question = chat.pendingQuestion;
    if (question != null && question['request_id'] is String) {
      final request = chat.clarification!;
      final answers = request['answers'] is Map
          ? request['answers'] as Map
          : const {};
      final count = request['questions'] is List
          ? ProfileGateway.records(
              request['questions'],
            ).where((q) => !answers.containsKey(q['qid'])).length
          : 1;
      final choices = question['choices'] is List
          ? (question['choices'] as List).whereType<String>().join(' · ')
          : '';
      result.add(
        NotificationInput(
          focus: NotificationFocus(
            'question',
            question['request_id'] as String,
          ),
          content: ChatNotificationContent.input(
            '${question['question'] ?? ''}${choices.isEmpty ? '' : '\n$choices'}',
          ),
          count: count,
        ),
      );
    }
    final secure = chat.sensitivePrompt;
    if (secure != null) {
      result.add(
        NotificationInput(
          focus: NotificationFocus('secure', secure.requestId),
          content: ChatNotificationContent.secureInput,
          submitting: chat.sensitivePromptResponding,
        ),
      );
    }
    return result;
  }

  void _publishNotificationInputs(ProfileChat chat, {bool? alert}) {
    final inputs = _notificationInputs(chat);
    final fingerprint = jsonEncode(inputs.map((v) => v.toJson()).toList());
    if (fingerprint == chat._notificationInputFingerprint) return;
    final established = chat._notificationInputFingerprint != null;
    chat._notificationInputFingerprint = fingerprint;
    if (!established && inputs.isEmpty) return;
    final quiet = chat._notificationInputsQuiet;
    chat._notificationInputsQuiet = false;
    final callback = onNotificationInputs;
    if (callback != null) {
      _trackNotificationWork(
        () => callback(
          ProfileInputNotification(
            chat.key,
            chat.title,
            connection.label,
            inputs,
            alert ?? (established && !quiet),
          ),
        ),
      );
    }
  }

  void _trackNotificationWork(Future<void> Function() callback) {
    _pendingNotifications++;
    unawaited(
      Future<void>.sync(callback).catchError((Object _) {}).whenComplete(() {
        _pendingNotifications--;
        if (!_closed) _changed();
      }),
    );
  }

  void notificationAnswerVisible(ProfileChat chat, NotificationFocus target) {
    if (_closed ||
        !visible ||
        current?.chat != chat ||
        chat.opening ||
        chat.offlineSnapshot ||
        chat.historyLoading ||
        chat.historyError != null ||
        chat.notificationReadTarget?.identity != target.identity) {
      return;
    }
    chat.notificationReadTarget = null;
    final callback = onNotificationRead;
    if (callback != null) {
      _trackNotificationWork(() => callback(chat.key, target.identity));
    }
  }

  /// Reconcile only notification-bearing chats. Caller owns watcher cadence.
  Future<void> reconcileNotificationRequests(
    Set<ProfileSessionKey> keys,
  ) async {
    Future<Map<String, dynamic>>? activeSnapshot;
    for (final key in keys) {
      if (_closed) return;
      final chat = findNotificationChat(key);
      if (chat == null ||
          chat.offlineSnapshot ||
          chat.opening ||
          chat.status == ProfileTurnStatus.reconnecting ||
          chat.approvalResponding ||
          chat.sensitivePromptResponding) {
        continue;
      }
      if (chat.approval == null &&
          chat.clarification == null &&
          chat.sensitivePrompt == null) {
        continue;
      }
      final resource = _owned(chat);
      final runtime = chat.runtimeId;
      final before = jsonEncode(
        _notificationInputs(chat).map((v) => v.toJson()).toList(),
      );
      try {
        // The active-list mapping corroborates the runtime; an unknown runtime's
        // empty replay alone must never be interpreted as successful resolution.
        activeSnapshot ??= resource.gateway.call('session.active_list', {});
        final active = await activeSnapshot;
        final sessions = ProfileGateway.records(active['sessions']);
        if (!sessions.any(
          (row) => row['id'] == runtime && row['session_key'] == key.sessionId,
        )) {
          continue;
        }
        final snapshot = await resource.gateway.call('session.events.since', {
          'session_id': runtime,
          'last_seen': _notificationReplayCursors[runtime] ?? 0,
        });
        if (_closed ||
            chat.runtimeId != runtime ||
            snapshot['open_requests'] is! List ||
            before !=
                jsonEncode(
                  _notificationInputs(chat).map((v) => v.toJson()).toList(),
                )) {
          continue;
        }
        final sequence = snapshot['latest_seq'];
        if (sequence is int && sequence >= 0) {
          _notificationReplayCursors[runtime] = sequence;
        }
        final open = ProfileGateway.records(snapshot['open_requests']);
        Map<String, dynamic>? find(String method, String id) => open
            .where(
              (r) =>
                  r['method'] == method &&
                  r['id'] == id &&
                  (r['params'] as Map?)?['session_id'] == runtime,
            )
            .firstOrNull;
        final clarification = chat.clarification;
        if (clarification != null) {
          final found = find('clarify', clarification['request_id'] as String);
          chat.clarification = found == null
              ? null
              : {
                  ...Map<String, dynamic>.from(found['params'] as Map),
                  'request_id': found['id'],
                };
        }
        final secure = chat.sensitivePrompt;
        if (secure != null &&
            !open.any(
              (r) =>
                  r['id'] == secure.requestId &&
                  (r['params'] as Map?)?['session_id'] == runtime,
            )) {
          chat.sensitivePrompt = null;
        }
        await _refreshApprovals(chat, notifyNew: true);
        _updateApprovalStatus(chat);
        _changed();
      } catch (_) {
        // Failure/absence of a valid snapshot leaves the notice and request intact.
      }
    }
  }
}
