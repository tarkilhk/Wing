import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';
import 'package:flutter/services.dart';

import 'web_output_preview.dart';

/// Splits raw markdown into text segments and fenced code blocks.
///
/// Returns a list of [String] (regular markdown, rendered by MarkdownBody)
/// and [MarkdownCodeBlock] (rendered with copy/wrap controls). The fenced
/// blocks are removed from the surrounding markdown so they render once,
/// with full fidelity, instead of relying on flutter_markdown's `pre`
/// builder (which leaves its internal inline state unbalanced).
List<Object> splitMarkdownCodeBlocks(String content, {bool streaming = false}) {
  final result = <Object>[];
  final opening = RegExp(
    r'^ {0,3}(`{3,}|~{3,})([^\r\n]*)\r?$',
    multiLine: true,
  );
  var cursor = 0;
  while (cursor < content.length) {
    final match = opening.firstMatch(content.substring(cursor));
    if (match == null) break;
    final start = cursor + match.start;
    final fence = match.group(1)!;
    final info = match.group(2)!.trim();
    final bodyStart = cursor + match.end;
    final closing = RegExp(
      '^ {0,3}${RegExp.escape(fence[0])}{${fence.length},}[ \\t]*\\r?\$',
      multiLine: true,
    ).firstMatch(content.substring(bodyStart));
    final bodyEnd = closing == null
        ? content.length
        : bodyStart + closing.start;
    // An unfinished streaming fence uses the same selectable code renderer.
    final codeStart = bodyStart < content.length && content[bodyStart] == '\n'
        ? bodyStart + 1
        : bodyStart;
    if (start > cursor) {
      result.add(content.substring(cursor, start));
    }
    result.add(
      MarkdownCodeBlock(
        code: content.substring(codeStart, bodyEnd),
        language: info.isEmpty ? null : info.split(RegExp(r'\s+')).first,
        previewEnabled: closing != null && !streaming,
      ),
    );
    cursor = closing == null ? content.length : bodyStart + closing.end;
  }

  if (cursor < content.length) {
    result.add(content.substring(cursor));
  }
  return result;
}

/// Renders a fenced code block with a language label, copy, and wrap controls.
class MarkdownCodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final bool previewEnabled;

  const MarkdownCodeBlock({
    super.key,
    required this.code,
    this.language,
    this.previewEnabled = true,
  });

  @override
  State<MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<MarkdownCodeBlock> {
  bool _wrap = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Code copied'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceContainerLow;
    final header = theme.colorScheme.surfaceContainerHighest;
    final foreground = theme.colorScheme.onSurface;
    final language = widget.language?.toLowerCase();
    final diagramFormat = switch (language) {
      'mermaid' => WebOutputFormat.mermaid,
      'svg' => WebOutputFormat.svg,
      _ => null,
    };
    final diagramLimit = diagramFormat == WebOutputFormat.svg
        ? WebOutputPreview.maxSvgSourceLength
        : WebOutputPreview.maxMermaidSourceLength;

    final body = _wrap
        ? SelectableText(
            widget.code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
              color: foreground,
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
                color: foreground,
              ),
            ),
          );

    return Container(
      key: const Key('markdown-code-block'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: HermesRadius.card,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: header,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language ?? 'code',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (diagramFormat != null &&
                    widget.previewEnabled &&
                    widget.code.length <= diagramLimit)
                  IconButton(
                    tooltip: diagramFormat == WebOutputFormat.svg
                        ? 'Open SVG'
                        : 'Open diagram',
                    icon: Icon(
                      diagramFormat == WebOutputFormat.svg
                          ? Icons.image_outlined
                          : Icons.account_tree_outlined,
                      size: 18,
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WebOutputPreview(
                          source: widget.code,
                          format: diagramFormat,
                        ),
                      ),
                    ),
                  ),
                Tooltip(
                  message: _wrap ? 'Scroll horizontally' : 'Wrap lines',
                  child: IconButton(
                    icon: Icon(
                      _wrap ? Icons.swap_horiz : Icons.wrap_text,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _wrap = !_wrap),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Copy code',
                  child: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    onPressed: _copy,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: body),
        ],
      ),
    );
  }
}
