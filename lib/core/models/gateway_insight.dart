enum GatewayReasoningEventMode { append, replace }

class GatewayReasoningUpdate {
  static const _maxTextLength = 20000;

  final String text;
  final GatewayReasoningEventMode mode;
  final bool verbose;

  const GatewayReasoningUpdate({
    required this.text,
    required this.mode,
    required this.verbose,
  });

  static GatewayReasoningUpdate? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (eventType != 'reasoning.delta' && eventType != 'reasoning.available') {
      return null;
    }
    final text = _safeText(data['text']?.toString(), _maxTextLength);
    if (text == null) return null;
    return GatewayReasoningUpdate(
      text: text,
      mode: eventType == 'reasoning.available'
          ? GatewayReasoningEventMode.replace
          : GatewayReasoningEventMode.append,
      verbose: data['verbose'] == true,
    );
  }

  String applyTo(String current) {
    final combined = mode == GatewayReasoningEventMode.replace
        ? text
        : '$current$text';
    if (combined.length <= _maxTextLength) return combined;
    return '${combined.substring(0, _maxTextLength - 1)}…';
  }

  static String? _safeText(String? value, int maxLength) {
    if (value == null) return null;
    final safe = value.replaceAll('\u0000', '');
    if (safe.trim().isEmpty) return null;
    return safe.length <= maxLength
        ? safe
        : '${safe.substring(0, maxLength - 1)}…';
  }
}

class GatewayInterimTransition {
  final String sealedText;
  final bool startsNewMessage;

  const GatewayInterimTransition({
    required this.sealedText,
    required this.startsNewMessage,
  });

  factory GatewayInterimTransition.resolve({
    required String currentText,
    required String interimText,
    required bool alreadyStreamed,
  }) {
    final safeInterim = interimText.replaceAll('\u0000', '');
    var sealed = currentText;
    if (safeInterim.isNotEmpty &&
        currentText != safeInterim &&
        !currentText.endsWith(safeInterim)) {
      if (!alreadyStreamed) {
        sealed = '$currentText$safeInterim';
      } else if (currentText.isEmpty || safeInterim.startsWith(currentText)) {
        sealed = safeInterim;
      }
    }
    return GatewayInterimTransition(
      sealedText: sealed,
      startsNewMessage: sealed.trim().isNotEmpty,
    );
  }
}

enum GatewayNoticeKind { background, review }

class GatewayNotice {
  static const _maxTextLength = 4000;
  static const _maxTaskIdLength = 120;

  final GatewayNoticeKind kind;
  final String text;
  final String? taskId;

  const GatewayNotice({required this.kind, required this.text, this.taskId});

  String get identity => '${kind.name}|${taskId ?? ''}|$text';

  String get title => switch (kind) {
    GatewayNoticeKind.background =>
      taskId == null
          ? 'Background task completed'
          : 'Background task $taskId completed',
    GatewayNoticeKind.review => 'Hermes review',
  };

  static GatewayNotice? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (eventType != 'background.complete' && eventType != 'review.summary') {
      return null;
    }
    final text = safeLine(data['text']?.toString(), _maxTextLength);
    if (text == null) return null;
    return GatewayNotice(
      kind: eventType == 'background.complete'
          ? GatewayNoticeKind.background
          : GatewayNoticeKind.review,
      text: text,
      taskId: eventType == 'background.complete'
          ? safeLine(data['task_id']?.toString(), _maxTaskIdLength)
          : null,
    );
  }

  static String? safeLine(String? value, int maxLength) {
    if (value == null) return null;
    final safe = value.replaceAll('\u0000', '').trim();
    if (safe.isEmpty) return null;
    return safe.length <= maxLength
        ? safe
        : '${safe.substring(0, maxLength - 1)}…';
  }
}

enum GatewayNotificationLevel { info, success, warning, error }

class GatewayNotification {
  final String key;
  final String text;
  final GatewayNotificationLevel level;
  final Duration? ttl;

  const GatewayNotification({
    required this.key,
    required this.text,
    required this.level,
    this.ttl,
  });

  static GatewayNotification? fromEventData(Map<String, dynamic> data) {
    final text = GatewayNotice.safeLine(data['text']?.toString(), 1000);
    if (text == null) return null;
    final key =
        GatewayNotice.safeLine((data['key'] ?? data['id'])?.toString(), 120) ??
        'latest';
    final ttlMs = switch (data['ttl_ms']) {
      int value when value > 0 => value,
      num value when value > 0 => value.toInt(),
      _ => null,
    };
    return GatewayNotification(
      key: key,
      text: text,
      level: switch (data['level']?.toString()) {
        'success' => GatewayNotificationLevel.success,
        'warn' => GatewayNotificationLevel.warning,
        'error' => GatewayNotificationLevel.error,
        _ => GatewayNotificationLevel.info,
      },
      ttl: ttlMs == null ? null : Duration(milliseconds: ttlMs),
    );
  }
}

enum GatewaySubagentPhase { requested, running, thinking, tool, completed }

enum GatewaySubagentStatus { queued, running, completed, failed, interrupted }

class GatewaySubagentActivity {
  static const maxRecentActivity = 40;
  final String id;
  final String? parentId;
  final int? depth;
  final String goal;
  final String? delegationId;
  final String? model;
  final String? detail;
  final GatewaySubagentPhase phase;
  final GatewaySubagentStatus? _status;
  final bool? _acceptingSteer;
  final int? taskIndex;
  final int? taskCount;
  final double? startedAt;
  final int? toolCount;
  final String? lastTool;
  final List<String> recentActivity;

  const GatewaySubagentActivity({
    required this.id,
    required this.goal,
    required this.phase,
    this.parentId,
    this.depth,
    this.delegationId,
    this.model,
    this.detail,
    this._status,
    this._acceptingSteer,
    this.taskIndex,
    this.taskCount,
    this.startedAt,
    this.toolCount,
    this.lastTool,
    this.recentActivity = const [],
  });

  GatewaySubagentStatus get status =>
      _status ??
      switch (phase) {
        GatewaySubagentPhase.requested => GatewaySubagentStatus.queued,
        GatewaySubagentPhase.completed => GatewaySubagentStatus.completed,
        _ => GatewaySubagentStatus.running,
      };

  bool get acceptingSteer => !isTerminal && (_acceptingSteer ?? false);
  bool get isComplete => isTerminal;
  bool get isTerminal => const {
    GatewaySubagentStatus.completed,
    GatewaySubagentStatus.failed,
    GatewaySubagentStatus.interrupted,
  }.contains(status);

  GatewaySubagentActivity merge(
    GatewaySubagentActivity next, {
    bool snapshot = false,
  }) {
    if (isTerminal) return this;
    return GatewaySubagentActivity(
      id: id,
      goal: next.goal.isEmpty ? goal : next.goal,
      phase: next.phase,
      status: next.status,
      acceptingSteer: next._acceptingSteer ?? _acceptingSteer,
      parentId: next.parentId ?? parentId,
      depth: next.depth ?? depth,
      delegationId: next.delegationId ?? delegationId,
      model: next.model ?? model,
      detail: next.detail ?? detail,
      taskIndex: next.taskIndex ?? taskIndex,
      taskCount: next.taskCount ?? taskCount,
      startedAt: next.startedAt ?? startedAt,
      toolCount: next.toolCount ?? toolCount,
      lastTool: next.lastTool ?? lastTool,
      recentActivity: snapshot && recentActivity.isNotEmpty
          ? recentActivity
          : _mergeActivity(recentActivity, next.recentActivity),
    );
  }

  static GatewaySubagentActivity? fromSnapshot(Map<String, dynamic> data) {
    final id = _opaqueId(data['subagent_id']);
    if (id == null) return null;
    final lastTool = GatewayNotice.safeLine(data['last_tool']?.toString(), 160);
    final status = _normalizeStatus(data['status']);
    return GatewaySubagentActivity(
      id: id,
      parentId: GatewayNotice.safeLine(data['parent_id']?.toString(), 120),
      depth: _integer(data['depth']),
      goal: GatewayNotice.safeLine(data['goal']?.toString(), 500) ?? '',
      delegationId: GatewayNotice.safeLine(
        data['delegation_id']?.toString(),
        120,
      ),
      model: GatewayNotice.safeLine(data['model']?.toString(), 120),
      phase: status == GatewaySubagentStatus.queued
          ? GatewaySubagentPhase.requested
          : status == GatewaySubagentStatus.running && lastTool != null
          ? GatewaySubagentPhase.tool
          : status == GatewaySubagentStatus.running
          ? GatewaySubagentPhase.running
          : GatewaySubagentPhase.completed,
      status: status,
      acceptingSteer: data['accepting_steer'] == true,
      startedAt: _number(data['started_at']),
      toolCount: _integer(data['tool_count']),
      lastTool: lastTool,
      recentActivity: lastTool == null ? const [] : ['Tool: $lastTool'],
    );
  }

  static GatewaySubagentActivity? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (!eventType.startsWith('subagent.')) return null;
    final id = _opaqueId(data['subagent_id']);
    if (id == null) return null;
    final goal = GatewayNotice.safeLine(data['goal']?.toString(), 500) ?? '';
    final detail = GatewayNotice.safeLine(
      (data['summary'] ??
              data['text'] ??
              data['tool_preview'] ??
              data['tool_name'])
          ?.toString(),
      1000,
    );
    final status = eventType == 'subagent.complete'
        ? _normalizeStatus(data['status'], terminalEvent: true)
        : eventType == 'subagent.spawn_requested'
        ? GatewaySubagentStatus.queued
        : _normalizeStatus(data['status']);
    return GatewaySubagentActivity(
      id: id,
      parentId: GatewayNotice.safeLine(data['parent_id']?.toString(), 120),
      depth: _integer(data['depth']),
      goal: goal,
      delegationId: GatewayNotice.safeLine(
        data['delegation_id']?.toString(),
        120,
      ),
      model: GatewayNotice.safeLine(data['model']?.toString(), 120),
      detail: detail,
      recentActivity: _eventActivity(eventType, data),
      status: status,
      acceptingSteer: data['accepting_steer'] is bool
          ? data['accepting_steer'] == true
          : null,
      taskIndex: _integer(data['task_index']),
      taskCount: _integer(data['task_count']),
      startedAt: _number(data['started_at']),
      toolCount: _integer(data['tool_count']),
      lastTool: GatewayNotice.safeLine(
        (data['tool_name'] ?? data['last_tool'])?.toString(),
        160,
      ),
      phase: switch (eventType) {
        'subagent.spawn_requested' => GatewaySubagentPhase.requested,
        'subagent.thinking' => GatewaySubagentPhase.thinking,
        'subagent.tool' => GatewaySubagentPhase.tool,
        'subagent.complete' => GatewaySubagentPhase.completed,
        _ => GatewaySubagentPhase.running,
      },
    );
  }

  static GatewaySubagentStatus _normalizeStatus(
    dynamic value, {
    bool terminalEvent = false,
  }) => switch (value?.toString().toLowerCase()) {
    'queued' when !terminalEvent => GatewaySubagentStatus.queued,
    'completed' => GatewaySubagentStatus.completed,
    'failed' || 'error' || 'timeout' => GatewaySubagentStatus.failed,
    'interrupted' ||
    'cancelled' ||
    'canceled' => GatewaySubagentStatus.interrupted,
    _ when terminalEvent => GatewaySubagentStatus.failed,
    _ => GatewaySubagentStatus.running,
  };

  static List<String> _mergeActivity(List<String> previous, List<String> next) {
    final result = [...previous];
    for (final line in next) {
      if (result.lastOrNull != line) result.add(line);
    }
    return List.unmodifiable(
      result.skip((result.length - maxRecentActivity).clamp(0, result.length)),
    );
  }

  static List<String> _eventActivity(
    String eventType,
    Map<String, dynamic> data,
  ) {
    final lines = <String>[];
    void add(Object? value, {Object? tool}) {
      final text = GatewayNotice.safeLine(value?.toString(), 1000);
      final name = GatewayNotice.safeLine(tool?.toString(), 160);
      if (name != null) {
        lines.add(
          'Tool: $name${text == null || text == name ? '' : ' · $text'}',
        );
      } else if (text != null) {
        lines.add(text);
      }
    }

    final tail = data['output_tail'];
    if (tail is List) {
      for (final entry in tail.whereType<Map>()) {
        add(entry['preview'], tool: entry['tool']);
      }
    }
    if (data['tool_name'] != null) {
      add(data['tool_preview'] ?? data['text'], tool: data['tool_name']);
    } else if (eventType == 'subagent.complete') {
      add(data['summary'] ?? data['text']);
    } else {
      add(data['text'] ?? data['tool_preview']);
    }
    return _mergeActivity(const [], lines);
  }

  static int? _integer(dynamic value) => value is num ? value.toInt() : null;
  static double? _number(dynamic value) =>
      value is num ? value.toDouble() : null;
  static String? _opaqueId(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}

class GatewaySubagentTail {
  static const maxTextLength = 16384;

  final String subagentId;
  final bool available;
  final String text;
  final bool truncated;

  const GatewaySubagentTail({
    required this.subagentId,
    required this.available,
    required this.text,
    required this.truncated,
  });

  static GatewaySubagentTail? fromJson(Map<String, dynamic> data) {
    final value = data['subagent_id'];
    final id = value is String && value.trim().isNotEmpty ? value : null;
    if (id == null || data['available'] is! bool) return null;
    final raw = data['text']?.toString().replaceAll('\u0000', '') ?? '';
    final clipped = raw.length > maxTextLength
        ? raw.substring(raw.length - maxTextLength)
        : raw;
    return GatewaySubagentTail(
      subagentId: id,
      available: data['available'] == true,
      text: clipped,
      truncated: data['truncated'] == true || clipped.length != raw.length,
    );
  }
}
