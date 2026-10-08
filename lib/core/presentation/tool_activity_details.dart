import 'dart:convert';

import 'skill_document.dart';

import '../models/chat_output.dart';
import '../services/web_preview.dart' show externalWebLink;

part 'tool_activities/files.dart';
part 'tool_activities/browser_web.dart';
part 'tool_activities/execution_media.dart';
part 'tool_activities/state.dart';
part 'tool_activities/discovery.dart';

enum ToolDetailRole {
  text,
  code,
  command,
  output,
  question,
  search,
  skill,
  task,
  warning,
  diff,
}

enum ToolActivityLayout { sections, file, search }

enum ToolReceiptState { completed, warning, error }

enum ToolDetailFormat { prose, source, diff }

/// Tool selection binds the received document to its exact primary receipt block.
final class SkillActivityDocument {
  const SkillActivityDocument({required this.document, required this.content});
  final SkillDocument document;
  final ToolDetailBlock content;
}

/// A section of an observed request or receipt, never an inferred tool effect.
final class ToolDetailBlock {
  const ToolDetailBlock({
    required this.label,
    required this.text,
    this.format = ToolDetailFormat.prose,
    this.markdown = false,
    this.link,
    this.numberedLines = false,
    this.secondary = false,
    this.resourceTarget,
    this.facts = const [],
    this.copyable = false,
    this.role = ToolDetailRole.text,
    this.exactCopyText,
    this.showEmpty = false,
  });

  final String label;
  final String text;
  final ToolDetailFormat format;
  final bool markdown;
  final Uri? link;
  final bool numberedLines;
  final bool secondary;
  final String? resourceTarget;
  final List<String> facts;
  final bool copyable;
  final ToolDetailRole role;
  final String? exactCopyText;
  final bool showEmpty;
  String get copyText => exactCopyText ?? text;

  bool get isReadContent => numberedLines && format == ToolDetailFormat.source;

  /// Stock read_file's numbered receipt stays intact for raw viewing/copying.
  /// Strip only its line-number decoration for the document renderer.
  String get documentText => numberedLines
      ? text.replaceAll(RegExp(r'^\d+\|', multiLine: true), '')
      : text;
}

/// One pure semantic owner: exact tool identity chooses fields; views only render.
final class ToolActivityDetails {
  ToolActivityDetails._(_ToolProjection p)
    : request = List.unmodifiable(p.request),
      response = List.unmodifiable(p.response),
      metadata = List.unmodifiable(p.metadata),
      images = List.unmodifiable(p.images),
      nativeVision = p.nativeVision,
      exitCode = p.exitCode,
      resourceTarget = p.resourceTarget,
      headerFacts = List.unmodifiable(p.headerFacts),
      layout = p.layout,
      receiptState = p.state,
      receiptStatus = p.status,
      skill = p.skill,
      intent = p.intent;

  final List<ToolDetailBlock> request, response;
  final List<String> metadata, headerFacts;
  final List<({String label, String target})> images;
  final bool nativeVision;
  final num? exitCode;
  final String? resourceTarget;
  final ToolActivityLayout layout;
  final ToolReceiptState? receiptState;
  final String? receiptStatus, intent;
  final SkillActivityDocument? skill;

  ChatOutput? resourceFor(String target) {
    final image = images.any((image) => image.target == target);
    final web = externalWebLink(target);
    final uri = Uri.tryParse(target);
    final windowsPath = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(target);
    if (target.trim().isEmpty ||
        (web == null && uri?.hasScheme == true && !windowsPath)) {
      return null;
    }
    return ChatOutput(
      kind: image
          ? ChatOutputKind.image
          : web != null
          ? ChatOutputKind.link
          : ChatOutputKind.file,
      path: web == null ? target : null,
      url: web?.toString(),
      label:
          (web?.path ?? target)
              .split(RegExp(r'[\\/]'))
              .where((part) => part.isNotEmpty)
              .lastOrNull ??
          target,
    );
  }

  factory ToolActivityDetails.project({
    required String name,
    required Object? input,
    required Object? output,
  }) {
    final p = _ToolProjection(name, input, output);
    switch (name) {
      case 'read_file':
        _readFile(p);
      case 'write_file':
        _writeFile(p);
      case 'patch':
        _patchFile(p);
      case 'search_files':
        _searchFiles(p);
      case 'terminal':
        _terminal(p);
      case 'execute_code':
        _executeCode(p);
      case 'browser_exec':
        _browserExec(p);
      case 'image_generate':
        _imageGenerate(p);
      case 'vision_analyze':
        _visionAnalyze(p);
      case 'browser_navigate':
        _browserNavigate(p);
      case 'browser_snapshot':
        _browserSnapshot(p);
      case 'browser_click':
        _browserClick(p);
      case 'browser_type':
        _browserType(p);
      case 'web_search':
        _webSearch(p);
      case 'web_extract':
        _webExtract(p);
      case 'desktop_preview':
        _desktopPreview(p);
      case 'drive_preview':
        _drivePreview(p);
      case 'memory':
        _memory(p);
      case 'skill_view':
        _skillView(p);
      case 'skill_manage':
        _skillManage(p);
      case 'todo_list':
        _todoList(p);
      case 'delegate_task':
        _delegateTask(p);
      case 'cronjob_manage':
        _cronjobManage(p);
      case 'session_search':
        _sessionSearch(p);
      case 'tool_search':
        _toolSearch(p);
      case 'tool_describe':
        _toolDescribe(p);
      case 'tool_call':
        _toolCall(p);
      case 'clarify':
        _clarify(p);
      default:
        _unknownTool(p);
    }
    p.finish();
    return ToolActivityDetails._(p);
  }
}

/// Private builders share formatting, never automatic field promotion or I/O.
final class _ToolProjection {
  _ToolProjection(this.name, Object? input, this.output)
    : args = input is Map ? input : const {},
      data = output is Map ? output : const {};
  final String name;
  final Map args, data;
  final Object? output;
  final request = <ToolDetailBlock>[], response = <ToolDetailBlock>[];
  final metadata = <String>[], headerFacts = <String>[];
  final images = <({String label, String target})>[];
  String? resourceTarget, status, intent;
  SkillActivityDocument? skill;
  ToolActivityLayout layout = ToolActivityLayout.sections;
  ToolReceiptState? state;
  bool nativeVision = false;
  num? exitCode;
  void addRequest(
    String label,
    Object? value, {
    ToolDetailFormat format = ToolDetailFormat.prose,
    ToolDetailRole role = ToolDetailRole.text,
    bool markdown = false,
    bool copyable = false,
    List<String> facts = const [],
    String? target,
    String? exactCopyText,
  }) {
    if (value is! String) return;
    request.add(
      ToolDetailBlock(
        showEmpty: value.isEmpty,
        label: label,
        text: value,
        format: format,
        role: role,
        markdown: markdown,
        copyable: copyable,
        facts: facts,
        resourceTarget: target,
        exactCopyText: exactCopyText,
      ),
    );
  }

  void addResponse(
    String label,
    Object? value, {
    ToolDetailFormat format = ToolDetailFormat.prose,
    ToolDetailRole role = ToolDetailRole.text,
    bool markdown = false,
    bool copyable = false,
    List<String> facts = const [],
    String? target,
    Uri? link,
    bool numberedLines = false,
    bool secondary = false,
    String? exactCopyText,
  }) {
    if (value is! String || value.trim().isEmpty) return;
    response.add(
      ToolDetailBlock(
        label: label,
        text: value,
        format: format,
        role: role,
        markdown: markdown,
        copyable: copyable,
        facts: facts,
        resourceTarget: target,
        link: link,
        numberedLines: numberedLines,
        secondary: secondary,
        exactCopyText: exactCopyText,
      ),
    );
  }

  void fact(String label, Object? value, {bool result = false}) {
    if (value == null || (value is String && value.trim().isEmpty)) return;
    (result ? metadata : headerFacts).add('$label: ${_display(value)}');
  }

  void options(Map source, Map<String, String> labels) {
    for (final entry in labels.entries) {
      fact(entry.value, source[entry.key]);
    }
  }

  void warning(Object? value, {String label = 'Warning'}) {
    if (value is! String || value.trim().isEmpty) return;
    addResponse(label, value, role: ToolDetailRole.warning, secondary: true);
    if (state != ToolReceiptState.error) {
      state = ToolReceiptState.warning;
      status ??= 'Completed with a warning';
    }
  }

  void image(String label, Object? target) {
    if (target is String &&
        target.trim().isNotEmpty &&
        !images.any((i) => i.target == target)) {
      images.add((label: label, target: target));
    }
  }

  void finish() {
    // Stock delivery can retain a literal textual receipt rather than its map.
    // Keep that received evidence cohesive; never reconstruct missing fields.
    if (output is String && response.isEmpty && !nativeVision) {
      addResponse(
        'Result',
        output,
        format: ToolDetailFormat.source,
        role: ToolDetailRole.output,
        copyable: true,
      );
    }
    final error = _text(data['error']);
    if (error != null) {
      if (!response.any((b) => b.text.contains(error))) {
        addResponse('Error', error, role: ToolDetailRole.warning);
      }
      state = ToolReceiptState.error;
      status ??= 'Failed';
    } else if (data['success'] == false ||
        data['ok'] == false ||
        data['isError'] == true) {
      state = ToolReceiptState.error;
      status ??= 'Failed';
    }
    if (data['no_change'] == true && state == null) {
      status = 'No change';
    }
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
List<Map> _maps(Object? value) =>
    value is List ? value.whereType<Map>().toList() : const [];
String _display(Object? value) => value is String
    ? value
    : value is List
    ? value.map(_display).join(' · ')
    : value is Map
    ? const JsonEncoder.withIndent('  ').convert(value)
    : '$value';
String _literal(Object? value) =>
    value is String ? value : const JsonEncoder.withIndent('  ').convert(value);
Uri? _web(Object? value) => value is String ? externalWebLink(value) : null;
void _unknownTool(_ToolProjection p) {
  for (final key in [
    'code',
    'command',
    'prompt',
    'question',
    'content',
    'query',
  ]) {
    if (p.args[key] is String) {
      p.addRequest(
        'Request',
        p.args[key],
        format: const ['code', 'command'].contains(key)
            ? ToolDetailFormat.source
            : ToolDetailFormat.prose,
        copyable: const ['code', 'command', 'prompt', 'content'].contains(key),
      );
      break;
    }
  }
  p.image('Returned image', _nativeImage(p.output));
  // Unknown contracts get one meaningful receipt, never a toolbar per JSON key.
  if (p.output is String) {
    p.addResponse('Result', p.output, copyable: true);
    return;
  }
  for (final key in ['result', 'text', 'content', 'output', 'message']) {
    if (p.data[key] is String) {
      p.addResponse('Result', p.data[key], copyable: key != 'message');
      break;
    }
  }
  if (p.data['content'] case final List parts) {
    final text = parts
        .whereType<Map>()
        .where((v) => v['type'] == 'text')
        .map((v) => _text(v['text']))
        .whereType<String>()
        .join('\n\n');
    p.addResponse('Result', text, copyable: true);
  }
}
