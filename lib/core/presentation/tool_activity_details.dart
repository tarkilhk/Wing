import '../models/chat_output.dart';
import '../services/web_preview.dart' show externalWebLink;

enum ToolDetailFormat { prose, source, diff }

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
  });

  final String label;
  final String text;
  final ToolDetailFormat format;
  final bool markdown;
  final Uri? link;
  final bool numberedLines;
  final bool secondary;
  final String? resourceTarget;

  bool get isReadContent => numberedLines && format == ToolDetailFormat.source;

  /// Stock read_file's numbered receipt stays intact for raw viewing/copying.
  /// Strip only its line-number decoration for the document renderer.
  String get documentText => numberedLines
      ? text.replaceAll(RegExp(r'^\d+\|', multiLine: true), '')
      : text;
}

/// Pure tool-specific layout facts shared by live and saved activities.
final class ToolActivityDetails {
  ToolActivityDetails._({
    required this.request,
    required this.response,
    required this.metadata,
    required this.images,
    required this.nativeVision,
    required this.exitCode,
    required this.resourceTarget,
    required this.readOptions,
  });

  final List<ToolDetailBlock> request;
  final List<ToolDetailBlock> response;
  final List<String> metadata;
  final List<({String label, String target})> images;
  final bool nativeVision;
  final num? exitCode;
  final String? resourceTarget;
  final List<String> readOptions;

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
    required List<({String label, String text, bool markdown, Uri? link})>
    details,
    required String? context,
  }) {
    final args = input is Map ? input : const {};
    final data = output is Map ? output : const {};
    final request = <ToolDetailBlock>[];
    final response = <ToolDetailBlock>[];
    final metadata = <String>[];
    final images = <({String label, String target})>[];
    final consumed = <String>{};
    final readOptions = <String>[];
    final nativeVision = data['_multimodal'] == true;
    final resourceTarget = [
      for (final key in ['image_url', 'video_url', 'path', 'file_path', 'url'])
        if (args[key] case final String value when value.isNotEmpty) value,
    ].firstOrNull;

    void requested(String key, String label, ToolDetailFormat format) {
      if (args[key] case final String value) {
        request.add(ToolDetailBlock(label: label, text: value, format: format));
        consumed.add(key);
      }
    }

    // File/image paths have their own selectable, copyable header. All other
    // request fields still appear below; no unknown inputs are silently dropped.
    for (final key in ['path', 'file_path', 'image_url', 'video_url', 'url']) {
      if (args[key] is String) consumed.add(key);
    }
    switch (name) {
      case 'terminal':
        requested('command', 'Command', ToolDetailFormat.source);
      case 'execute_code' || 'browser_exec':
        requested('code', 'Code', ToolDetailFormat.source);
      case 'patch':
        requested('old_string', 'Find', ToolDetailFormat.source);
        requested('new_string', 'Replace with', ToolDetailFormat.source);
        requested('patch', 'Requested patch', ToolDetailFormat.diff);
      case 'write_file':
        requested('content', 'Content to write', ToolDetailFormat.source);
      case 'vision_analyze' || 'video_analyze':
        requested('question', 'Question', ToolDetailFormat.prose);
      case 'web_search':
        requested('query', 'Query', ToolDetailFormat.prose);
      case 'search_files':
        requested('pattern', 'Pattern', ToolDetailFormat.source);
    }
    if (name == 'read_file') {
      for (final key in ['offset', 'limit']) {
        if (args.containsKey(key)) {
          readOptions.add('${_label(key)}: ${args[key]}');
          consumed.add(key);
        }
      }
    }
    final otherInputs = Map.fromEntries(
      args.entries.where((entry) => !consumed.contains(entry.key)),
    );
    if (otherInputs.isNotEmpty) {
      request.add(
        ToolDetailBlock(
          label: name == 'read_file'
              ? 'Read options'
              : request.isEmpty
              ? 'Request'
              : 'Options',
          text: _readable(otherInputs),
          secondary: name == 'read_file' || request.isNotEmpty,
        ),
      );
    } else if (input is String && input.isNotEmpty) {
      request.add(ToolDetailBlock(label: 'Request', text: input));
    } else if (input == null && context != null && context.isNotEmpty) {
      request.add(ToolDetailBlock(label: 'Request context', text: context));
    }

    if (name == 'read_file') {
      for (final (key, label) in [
        ('total_lines', 'Total lines'),
        ('file_size', 'File bytes'),
        ('next_offset', 'Next offset'),
      ]) {
        if (data[key] case final num value) metadata.add('$label: $value');
      }
      if (data['truncated'] == true) metadata.add('Partial file returned');
    }
    if (data['stdout_truncated'] == true) {
      metadata.add('Output truncated by server');
    }
    if (data['truncated'] == true && name != 'read_file') {
      metadata.add('Partial results returned');
    }
    if (name == 'search_files') {
      if (data['total_count'] case final num count) {
        metadata.add('Reported matches: $count');
      }
      if (data['total_count_is_lower_bound'] == true) {
        metadata.add('Count is a lower bound');
      }
    }
    if (name == 'write_file') {
      if (data['bytes_written'] case final num bytes) {
        metadata.add('Bytes written: $bytes');
      }
      if (data['verified'] case final bool verified) {
        metadata.add(
          verified ? 'Write verified by server' : 'Write not verified',
        );
      }
    }
    if (name == 'write_file' || name == 'patch') {
      if (data['lint'] case final Map lint) {
        if (lint['status'] case final String status) {
          metadata.add(
            'Syntax check: ${switch (status) {
              'ok' => 'Passed',
              'error' => 'Failed',
              'skipped' => 'Skipped',
              _ => status,
            }}',
          );
        }
        for (final key in ['output', 'message']) {
          if (lint[key] case final String text when text.isNotEmpty) {
            response.add(
              ToolDetailBlock(
                label: 'Syntax check ${key == 'output' ? 'output' : 'details'}',
                text: text,
                format: ToolDetailFormat.source,
              ),
            );
          }
        }
      }
      if (data['lsp_diagnostics'] case final String diagnostics
          when diagnostics.isNotEmpty) {
        response.add(
          ToolDetailBlock(
            label: 'Semantic diagnostics',
            text: diagnostics,
            format: ToolDetailFormat.source,
          ),
        );
      }
    }
    final groupedMatches = <String, List<Map>>{};
    final otherMatches = <Object?>[];
    if (name == 'search_files' && data['matches'] is List) {
      for (final match in data['matches'] as List) {
        if (match is Map &&
            match['path'] is String &&
            match['content'] is String) {
          groupedMatches
              .putIfAbsent(match['path'] as String, () => [])
              .add(match);
        } else {
          otherMatches.add(match);
        }
      }
      for (final entry in groupedMatches.entries) {
        for (var i = 0; i < entry.value.length; i++) {
          final match = entry.value[i];
          response.add(
            ToolDetailBlock(
              label: match['line'] is num ? 'Line: ${match['line']}' : 'Match',
              text: match['content'] as String,
              format: ToolDetailFormat.source,
              resourceTarget: i == 0 ? entry.key : null,
            ),
          );
        }
      }
    }
    if (name == 'vision_analyze') {
      if (args['image_url'] case final String image when image.isNotEmpty) {
        images.add((label: 'Analyzed image', target: image));
      }
    }
    if (name == 'image_generate') {
      if (data['image'] case final String image when image.isNotEmpty) {
        images.add((label: 'Generated image', target: image));
      }
    }

    // The native vision receipt hands pixels to the model. It is not an
    // analysis. Show the receipt verbatim under a truthful caption.
    for (final detail in details) {
      if (detail.label == 'Question') continue;
      if (detail.label == 'Context' && output == null) continue;
      if (name == 'read_file' &&
          const [
            'Total lines',
            'File size',
            'Next offset',
            'Truncated',
          ].contains(detail.label)) {
        continue;
      }
      if (const ['Success', 'Ok', 'Exit code'].contains(detail.label)) continue;
      if ((name == 'write_file' || name == 'patch') &&
          const ['Lint', 'Lsp diagnostics'].contains(detail.label)) {
        continue;
      }
      if (name == 'search_files' &&
          const [
            'Total count',
            'Total count is lower bound',
            'Truncated',
          ].contains(detail.label)) {
        continue;
      }
      if (name == 'write_file' &&
          const ['Bytes written', 'Verified'].contains(detail.label)) {
        continue;
      }
      final text = detail.text;
      final format = switch (name) {
        'read_file'
            when detail.label == 'Content' || detail.label == 'Result' =>
          ToolDetailFormat.source,
        'terminal' || 'execute_code' || 'browser_exec'
            when const [
              'Output',
              'Stdout',
              'Stderr',
              'Result',
            ].contains(detail.label) =>
          ToolDetailFormat.source,
        _ => ToolDetailFormat.prose,
      };
      response.add(
        ToolDetailBlock(
          label: nativeVision && detail.label == 'Result'
              ? 'Image receipt'
              : name == 'read_file' && format == ToolDetailFormat.source
              ? 'Raw content'
              : detail.label,
          text: text,
          format: format,
          markdown: name == 'read_file' && format == ToolDetailFormat.source
              ? RegExp(
                  r'\.(?:md|markdown)$',
                  caseSensitive: false,
                ).hasMatch(resourceTarget ?? '')
              : format == ToolDetailFormat.prose && detail.markdown,
          link: detail.link,
          numberedLines: name == 'read_file',
        ),
      );
    }
    for (final key in ['content', 'output', 'stdout', 'stderr']) {
      final label = name == 'read_file' && key == 'content'
          ? 'Raw content'
          : _label(key);
      if (data[key] == '' && !response.any((block) => block.label == label)) {
        response.add(
          ToolDetailBlock(
            label: label,
            text: '',
            numberedLines: name == 'read_file' && key == 'content',
            format:
                const [
                  'read_file',
                  'terminal',
                  'execute_code',
                  'browser_exec',
                ].contains(name)
                ? ToolDetailFormat.source
                : ToolDetailFormat.prose,
          ),
        );
      }
    }
    if (data['diff'] case final String diff when diff.isNotEmpty) {
      response.removeWhere((block) => block.label == 'Diff');
      response.insert(
        0,
        ToolDetailBlock(
          label: 'Reported diff',
          text: diff,
          format: ToolDetailFormat.diff,
        ),
      );
    }
    // Structured file-search results and nested operation receipts must be
    // readable even when the general text projection has no content field.
    for (final key in [
      'matches',
      'matches_text',
      'files',
      'counts',
      'lint',
      'lsp_diagnostics',
      'warning',
      '_warning',
      '_hint',
      'note',
    ]) {
      if ((name == 'write_file' || name == 'patch') &&
          const ['lint', 'lsp_diagnostics'].contains(key)) {
        continue;
      }
      if (key == 'matches' && groupedMatches.isNotEmpty) {
        if (otherMatches.isNotEmpty) {
          response.add(
            ToolDetailBlock(
              label: 'Other matches',
              text: _readable(otherMatches),
              format: ToolDetailFormat.source,
            ),
          );
        }
        continue;
      }
      final value = data[key];
      if (value != null &&
          _readable(value).isNotEmpty &&
          !response.any((block) => block.label == _label(key))) {
        response.add(
          ToolDetailBlock(
            label: _label(key),
            text: _readable(value),
            format: name == 'search_files'
                ? ToolDetailFormat.source
                : ToolDetailFormat.prose,
          ),
        );
      }
    }
    for (final entry in data.entries) {
      if ((entry.value is Map || entry.value is List) &&
          !const [
            'content',
            'results',
            'data',
            'matches',
            'files',
            'counts',
            'lint',
            'lsp_diagnostics',
          ].contains(entry.key) &&
          !response.any(
            (block) => block.label == _label(entry.key.toString()),
          )) {
        response.add(
          ToolDetailBlock(
            label: _label(entry.key.toString()),
            text: _readable(entry.value),
          ),
        );
      }
    }
    if (response.isEmpty &&
        output != null &&
        output is! String &&
        !(output is Map && output.length == 1 && data['content'] is List) &&
        details.isEmpty) {
      final text = _readable(output);
      if (text.isNotEmpty) {
        response.add(ToolDetailBlock(label: 'Result', text: text));
      }
    }
    final exit = data['exit_code'];
    return ToolActivityDetails._(
      request: List.unmodifiable(request),
      response: List.unmodifiable(response),
      metadata: List.unmodifiable(metadata),
      images: List.unmodifiable(images),
      nativeVision: nativeVision,
      exitCode: exit is num && exit.isFinite ? exit : null,
      resourceTarget: resourceTarget,
      readOptions: List.unmodifiable(readOptions),
    );
  }
}

String _label(String key) {
  final words = key.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return words.isEmpty
      ? 'Value'
      : '${words[0].toUpperCase()}${words.substring(1)}';
}

String _readable(Object? value, [String indent = '']) {
  if (value is Map) {
    return value.entries
        .map((entry) {
          final nested = entry.value is Map || entry.value is List;
          return '$indent${_label(entry.key.toString())}:${nested ? '\n${_readable(entry.value, '$indent  ')}' : ' ${entry.value ?? 'null'}'}';
        })
        .join('\n');
  }
  if (value is List) {
    return value
        .map(
          (item) =>
              '$indent${item is Map || item is List ? '\n${_readable(item, '$indent  ')}' : item ?? 'null'}',
        )
        .join('\n');
  }
  return value?.toString() ?? '';
}
