import 'dart:convert';

import '../models/gateway_activity.dart';
import '../models/transcript_message.dart';
import 'desktop_tool_labels.dart';
import 'tool_activity_details.dart';

enum ToolCallOutcome { running, completed, success, warning, error }

/// Readable projection of delivered facts. It owns no execution or transport.
final class ToolCallPresentation {
  ToolCallPresentation._({
    required this.name,
    required this.title,
    required this.target,
    required this.subtitle,
    required this.status,
    required this.outcome,
    required this.activityDetails,
    required this.arguments,
    required this.result,
    required this.labels,
    this.callId,
    this.context,
    this.summary,
    this.durationSeconds,
    this.startedAt,
  });

  final String name;
  final String? callId;
  final String? context;
  final String? summary;
  final String title;
  final String? target;
  final String status;
  final ToolCallOutcome outcome;
  final ToolActivityDetails activityDetails;
  final String? arguments;
  final String? result;
  final List<ToolCallLabel> labels;
  final double? durationSeconds;
  final Duration? startedAt;

  /// One compact input fact; raw targets and inputs remain unmodified.
  final String subtitle;

  /// Exceptions replace the input subtitle; normal completion adds no notice.
  String? get notice => switch (outcome) {
    ToolCallOutcome.warning || ToolCallOutcome.error => status,
    _ => null,
  };

  /// Shared desktop captions for a tool name delivered by Hermes.
  static String titleFor(String name, {required bool completed}) {
    final catalog = desktopToolLabels[name];
    if (name == 'skill_view') return completed ? 'Read skill' : 'Reading skill';
    if (catalog != null) return completed ? catalog.done : catalog.pending;
    return _humanize(name);
  }

  factory ToolCallPresentation.live(GatewayToolActivity activity) => _project(
    name: activity.name,
    callId: activity.toolId,
    arguments: activity.arguments,
    result: activity.result,
    labels: activity.labels,
    completed: activity.isTerminal,
    durationSeconds: activity.durationSeconds,
    startedAt: activity.startedAt,
    context: activity.context,
    summary: activity.summary,
  );

  factory ToolCallPresentation.saved(TranscriptToolResult result) => _project(
    name: result.name,
    callId: result.callId,
    arguments: result.arguments,
    result: result.rawResult.isEmpty ? result.text : result.rawResult,
    labels: result.labels,
    completed: true,
    durationSeconds: result.durationSeconds,
    context: result.context,
    summary: result.summary,
  );

  static ToolCallPresentation _project({
    required String name,
    required String? arguments,
    required String? result,
    required List<ToolCallLabel> labels,
    required bool completed,
    String? callId,
    double? durationSeconds,
    Duration? startedAt,
    String? context,
    String? summary,
  }) {
    final input = decodeToolPayload(arguments);
    final output = decodeToolPayload(result);
    final args = input is Map ? input : const {};
    final data = output is Map ? output : const {};
    final title = labels.isNotEmpty
        ? labels.first.text
        : titleFor(name, completed: completed);
    final target =
        _firstText(args, const [
          'image_url',
          'video_url',
          'url',
          'file_path',
          'path',
          'query',
          'pattern',
          'command',
          'name',
        ]) ??
        _listTarget(args['urls']) ??
        (labels.isNotEmpty ? _nonempty(labels.first.preview) : null);
    var outcome = completed
        ? ToolCallOutcome.completed
        : ToolCallOutcome.running;
    var status = completed
        ? (summary == null ? 'Completed' : _oneLine(summary))
        : 'Running';
    if (completed) {
      final error = _firstText(data, const ['error']);
      final exit = data['exit_code'];
      if (data['success'] == false ||
          data['ok'] == false ||
          data['isError'] == true ||
          error != null ||
          data['error'] == true ||
          const ['error', 'timeout', 'interrupted'].contains(data['status']) ||
          (exit is num && exit != 0)) {
        outcome = ToolCallOutcome.error;
        status = error == null ? 'Failed' : _oneLine(error);
        if (exit is num && exit != 0) status = 'Exited with code $exit';
      } else if (_returned404(data)) {
        outcome = ToolCallOutcome.warning;
        status = 'Returned a 404 page';
      } else if (_firstText(data, const ['fallback_warning'])
          case final warning?) {
        outcome = ToolCallOutcome.warning;
        status = _oneLine(warning);
      } else if (data['no_change'] == true) {
        status = 'No change';
      } else if (data['status'] == 'unchanged') {
        outcome = ToolCallOutcome.completed;
        status = 'Already loaded';
      } else if (data['success'] == true ||
          data['ok'] == true ||
          data['status'] == 'success' ||
          data['verified'] == true) {
        outcome = ToolCallOutcome.success;
        status = summary == null ? 'Completed' : _oneLine(summary);
      }
    }
    final details = <({String label, String text, bool markdown, Uri? link})>[];
    if (args['question'] is String) {
      details.add(_detail('Question', args['question'] as String));
    }
    if (output is Map) {
      for (final key in const [
        'analysis',
        'text',
        'message',
        'error',
        'output',
        'stdout',
        'stderr',
        'content',
        'scale_note',
      ]) {
        final value = output[key];
        if (value is String && value.trim().isNotEmpty) {
          details.add(
            _detail(
              _humanize(key),
              value,
              allowMarkdown: !const [
                'stdout',
                'stderr',
                'output',
              ].contains(key),
            ),
          );
        }
      }
      if (output['content'] case final List parts) {
        for (final part in parts) {
          if (part is Map &&
              part['type'] == 'text' &&
              part['text'] is String &&
              (part['text'] as String).trim().isNotEmpty) {
            details.add(_detail('Result', part['text'] as String));
          }
        }
      }
      final nested = output['data'];
      final sources = [
        if (output['results'] is List) ...output['results'] as List,
        if (nested is Map) ...[
          if (nested['results'] is List) ...nested['results'] as List,
          if (nested['web'] is List) ...nested['web'] as List,
        ],
      ];
      if (sources.isNotEmpty) {
        for (final source in sources) {
          if (source is! Map) continue;
          final sourceTitle =
              _firstText(source, const ['title', 'url', 'name']) ?? 'Result';
          final content = _firstText(source, const [
            'content',
            'snippet',
            'description',
            'text',
          ]);
          final url = _firstText(source, const ['url']);
          // Results also contain structured operation receipts, not just web
          // sources. Render their delivered scalar facts rather than an empty
          // source block. Unprojected nested data stays available in raw details.
          final text = url != null || content != null
              ? _sourceText(url, content)
              : _scalarFacts(source, heading: sourceTitle);
          if (text.trim().isNotEmpty) {
            details.add(_detail(sourceTitle, text, link: _sourceUri(url)));
          }
        }
      }
      // Generic structured tools retain scalar facts without exposing JSON as
      // their default content. Nested structures remain in full raw details.
      if (details.isEmpty) {
        for (final entry in output.entries) {
          if ((entry.value is String &&
                  (entry.value as String).trim().isNotEmpty) ||
              entry.value is num ||
              entry.value is bool) {
            details.add(
              _detail(_humanize(entry.key.toString()), entry.value.toString()),
            );
          }
        }
      }
    } else if (output is String && output.trim().isNotEmpty) {
      details.add(
        _detail(
          'Result',
          output,
          allowMarkdown: name != 'terminal' && name != 'execute_code',
        ),
      );
    }
    if (details.isEmpty && (summary ?? context) != null) {
      details.add(
        _detail(summary != null ? 'Summary' : 'Context', (summary ?? context)!),
      );
    }
    return ToolCallPresentation._(
      name: name,
      callId: callId,
      context: context,
      summary: summary,
      title: title,
      target: target == null ? null : _oneLine(target),
      subtitle: _inputDetail(name, args, data, labels, context),
      status: status,
      outcome: outcome,
      activityDetails: ToolActivityDetails.project(
        name: name,
        input: input,
        output: output,
        details: details,
        context: context,
      ),
      arguments: arguments,
      result: result,
      labels: labels,
      durationSeconds: durationSeconds,
      startedAt: completed ? null : startedAt,
    );
  }
}

String _inputDetail(
  String name,
  Map args,
  Map data,
  List<ToolCallLabel> labels,
  String? context,
) {
  String display(String value) {
    final text = _oneLine(value);
    if (text.startsWith('data:')) return 'Attached image';
    return text.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  }

  String? list(Object? value) {
    if (value is! List) return null;
    final values = value
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .map(display);
    return values.isEmpty ? null : values.join(' · ');
  }

  if (labels.isNotEmpty && labels.first.preview.trim().isNotEmpty) {
    return display(labels.first.preview);
  }
  final code = _firstText(args, const ['code']);
  if (name == 'browser_exec' && code != null) {
    // Only literal input URLs are summarized. Never evaluate code or borrow a
    // URL from another call; scripts may use entirely different browser tabs.
    final literals = RegExp(r'''(["'])(.*?)\1''').allMatches(code);
    for (final literal in literals) {
      final url = RegExp(
        r'''https?://[^\s"'<>`\\]+''',
      ).firstMatch(literal.group(2)!)?.group(0);
      if (url != null && !url.contains('{') && !url.contains('}')) {
        return display(url);
      }
    }
    final first = code.trim().split('\n').first.trim();
    if (first.startsWith('#') && first.substring(1).trim().isNotEmpty) {
      return _oneLine(first.substring(1));
    }
    return _oneLine(code);
  }
  if (name == 'search_files') {
    final pattern = _firstText(args, const ['pattern', 'query']);
    final path = _firstText(args, const ['path']);
    if (pattern != null || path != null) {
      return [?pattern, ?path].map(display).join(' · ');
    }
  }
  if (args['tasks'] case final List tasks
      when name == 'delegate_task' && tasks.isNotEmpty) {
    final goal = tasks.first is Map
        ? _firstText(tasks.first as Map, const ['goal'])
        : null;
    return '${tasks.length} ${tasks.length == 1 ? 'task' : 'tasks'}${goal == null ? '' : ' · ${_oneLine(goal)}'}';
  }
  if (name == 'delegate_task' && data['goals'] is List) {
    final goals = (data['goals'] as List)
        .whereType<String>()
        .where((goal) => goal.trim().isNotEmpty)
        .toList();
    if (goals.isNotEmpty) {
      return '${goals.length} ${goals.length == 1 ? 'task' : 'tasks'} · ${_oneLine(goals.first)}';
    }
  }
  final target =
      _firstText(args, const [
        'image_url',
        'url',
        'file_path',
        'path',
        'query',
        'pattern',
        'command',
        'name',
        'goal',
        'prompt',
        'ref',
        'selector',
        'text',
        'content',
        'code',
        'subagent_id',
      ]) ??
      list(args['urls']) ??
      list(args['names']);
  final action = _firstText(args, const ['action']);
  if (action != null) {
    return [_humanize(action), if (target != null) display(target)].join(' · ');
  }
  if (target != null) return display(target);
  if (context != null && context.trim().isNotEmpty) return display(context);
  final deliveredTarget = _firstText(data, const ['url', 'file_path', 'path']);
  if (deliveredTarget != null) return display(deliveredTarget);
  return 'No input details supplied';
}

/// Decode delivered JSON for presentation, preserving raw output at its source.
Object? decodeToolPayload(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  // Stock Hermes wraps external output with a security preamble. Preserve the
  // exact wrapper in raw details; extract only its enclosed data for display.
  if (text.startsWith('<untrusted_tool_result ') &&
      text.endsWith('</untrusted_tool_result>')) {
    final start = RegExp(r'^\s*[{\[]', multiLine: true).firstMatch(text);
    if (start != null) {
      text = text
          .substring(start.start, text.lastIndexOf('</untrusted_tool_result>'))
          .trim();
    }
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    return raw;
  }
}

String? _firstText(Map data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

String? _nonempty(String text) => text.trim().isEmpty ? null : text;
String? _listTarget(Object? value) => value is List && value.isNotEmpty
    ? value.whereType<String>().join(' · ')
    : null;
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
String _scalarFacts(Map data, {required String heading}) {
  final facts = [
    for (final entry in data.entries)
      if ((entry.value is String &&
              (entry.value as String).trim().isNotEmpty) ||
          entry.value is num ||
          entry.value is bool)
        entry,
  ];
  final body = facts.where(
    (entry) =>
        !((entry.key == 'name' || entry.key == 'title') &&
            entry.value == heading),
  );
  return (body.isEmpty ? facts : body)
      .map((entry) => '${_humanize(entry.key.toString())}: ${entry.value}')
      .join('\n');
}

Uri? _sourceUri(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty
      ? uri
      : null;
}

String _sourceText(String? url, String? content) =>
    _sourceUri(url) != null ? content ?? url! : [?url, ?content].join('\n\n');

String _humanize(String text) {
  final words = text.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return words.isEmpty
      ? 'Tool'
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

bool _returned404(Map data) {
  if (data['status_code'] == 404) return true;
  final sources = data['results'];
  if (sources is! List) return false;
  return sources.any(
    (source) =>
        source is Map &&
        (source['status_code'] == 404 ||
            RegExp(
              r'(?:^|[-|:])\s*404(?:\s+error|\s+page\s+not\s+found|\s+not\s+found)?\s*(?:$|[-|:])',
              caseSensitive: false,
            ).hasMatch('${source['title'] ?? ''}') ||
            RegExp(
              r'^\s*(?:#{1,6}\s*)?404\s+page\s+not\s+found\s*$',
              caseSensitive: false,
              multiLine: true,
            ).hasMatch('${source['content'] ?? ''}')),
  );
}

String formatToolDuration(double seconds) {
  if (seconds < 1) return '${(seconds * 1000).round()} ms';
  if (seconds < 60) return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
  final whole = seconds.floor();
  return '${whole ~/ 60}m ${whole % 60}s';
}

({String label, String text, bool markdown, Uri? link}) _detail(
  String label,
  String text, {
  bool allowMarkdown = true,
  Uri? link,
}) => (
  label: label,
  text: text,
  link: link,
  markdown:
      allowMarkdown &&
      RegExp(r'(^|\n)(#{1,6} |[-*] |```)|\[[^\]]+\]\(|\*\*').hasMatch(text),
);
