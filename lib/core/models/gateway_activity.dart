import 'dart:convert';

enum GatewayToolActivityPhase { running, generating, completed }

class GatewayToolActivity {
  static const _maxNameLength = 120;
  static const _maxDetailLength = 500;
  static const _maxPayloadLength = 12000;

  final String? toolId;
  final String name;
  final GatewayToolActivityPhase phase;
  final String? detail;
  final double? durationSeconds;
  final String? arguments;
  final String? result;

  const GatewayToolActivity({
    required this.name,
    required this.phase,
    this.toolId,
    this.detail,
    this.durationSeconds,
    this.arguments,
    this.result,
  });

  bool get isTerminal => phase == GatewayToolActivityPhase.completed;

  String get displayName {
    final words = name.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (words.isEmpty) return 'Tool';
    return words[0].toUpperCase() + words.substring(1);
  }

  String get statusLabel {
    switch (phase) {
      case GatewayToolActivityPhase.running:
        return 'Running';
      case GatewayToolActivityPhase.generating:
        return 'Preparing';
      case GatewayToolActivityPhase.completed:
        return durationSeconds == null
            ? 'Completed'
            : 'Completed in ${_formatDuration(durationSeconds!)}';
    }
  }

  static GatewayToolActivity? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    final phase = switch (eventType) {
      'tool.start' => GatewayToolActivityPhase.running,
      'tool.generating' => GatewayToolActivityPhase.generating,
      'tool.complete' => GatewayToolActivityPhase.completed,
      _ => null,
    };
    if (phase == null) return null;

    final toolId = _firstText(data, const ['tool_id']);
    final rawName = _firstText(data, const ['name']) ?? 'tool';
    final name = _normalizeText(rawName, _maxNameLength) ?? 'tool';
    final durationSeconds = _duration(data['duration_s']);
    final detail = switch (phase) {
      GatewayToolActivityPhase.completed => _normalizeText(
        _firstText(data, const ['summary']),
        _maxDetailLength,
      ),
      GatewayToolActivityPhase.generating => null,
      GatewayToolActivityPhase.running => _normalizeText(
        _firstText(data, const ['context']),
        _maxDetailLength,
      ),
    };

    return GatewayToolActivity(
      toolId: toolId,
      name: name,
      phase: phase,
      detail: detail,
      durationSeconds: durationSeconds,
      arguments: _payload(data['args']),
      result: _payload(data['result'] ?? data['result_text']),
    );
  }

  GatewayToolActivity merge(GatewayToolActivity update) {
    return GatewayToolActivity(
      toolId: update.toolId ?? toolId,
      name: update.name == 'tool' && name != 'tool' ? name : update.name,
      phase: update.phase,
      detail: update.detail ?? detail,
      durationSeconds: update.durationSeconds ?? durationSeconds,
      arguments: update.arguments ?? arguments,
      result: update.result ?? result,
    );
  }

  static String? _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String? _normalizeText(String? value, int maxLength) {
    if (value == null) return null;
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength - 1)}…';
  }

  static double? _duration(dynamic value) {
    if (value is num && value.isFinite && value >= 0) {
      return value.toDouble();
    }
    return null;
  }

  static String? _payload(dynamic value) {
    if (value == null) return null;
    String text;
    try {
      text = value is String ? value : jsonEncode(value);
    } catch (_) {
      text = value.toString();
    }
    final safe = text.replaceAll('\u0000', '').trim();
    if (safe.isEmpty) return null;
    return safe.length <= _maxPayloadLength
        ? safe
        : '${safe.substring(0, _maxPayloadLength - 1)}…';
  }

  static String _formatDuration(double value) {
    if (value < 1) return '${(value * 1000).round()} ms';
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} s';
  }
}
