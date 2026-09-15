import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'markdown_code_block.dart';

enum WebOutputFormat { mermaid, svg, html }

/// A disposable native preview opened explicitly from its source.
class WebOutputPreview extends StatefulWidget {
  static const maxMermaidSourceLength = 50000;
  static const maxSvgSourceLength = 256 * 1024;
  static const maxHtmlSourceLength = 1024 * 1024;
  static const viewType = 'com.tarkilhk.wing/mermaid_diagram';

  final String source;
  final WebOutputFormat format;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const WebOutputPreview({
    super.key,
    required this.source,
    required this.format,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<WebOutputPreview> createState() => _WebOutputPreviewState();
}

class _WebOutputPreviewState extends State<WebOutputPreview> {
  bool _showSource = false;

  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final limit = switch (widget.format) {
      WebOutputFormat.mermaid => WebOutputPreview.maxMermaidSourceLength,
      WebOutputFormat.svg => WebOutputPreview.maxSvgSourceLength,
      WebOutputFormat.html => WebOutputPreview.maxHtmlSourceLength,
    };
    final canRender =
        supported && widget.source.isNotEmpty && widget.source.length <= limit;
    final label = switch (widget.format) {
      WebOutputFormat.mermaid => 'diagram',
      WebOutputFormat.svg => 'SVG',
      WebOutputFormat.html => 'HTML',
    };
    final language = widget.format.name;
    final previewIcon = switch (widget.format) {
      WebOutputFormat.mermaid => Icons.account_tree_outlined,
      WebOutputFormat.svg => Icons.image_outlined,
      WebOutputFormat.html => Icons.web_asset_outlined,
    };
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (widget.format == WebOutputFormat.mermaid
                  ? 'Diagram'
                  : '$label preview'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.onAction != null)
            IconButton(
              tooltip: widget.actionLabel,
              icon: const Icon(Icons.ios_share),
              onPressed: widget.onAction,
            ),
          if (canRender)
            IconButton(
              tooltip: _showSource ? 'Show $label' : 'Show source',
              icon: Icon(_showSource ? previewIcon : Icons.code),
              onPressed: () => setState(() => _showSource = !_showSource),
            ),
        ],
      ),
      body: SafeArea(
        child: _showSource || !canRender
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!canRender)
                      Text('This $label is available as source here.'),
                    MarkdownCodeBlock(
                      code: widget.source,
                      language: language,
                      previewEnabled: false,
                    ),
                  ],
                ),
              )
            : AndroidView(
                key: ValueKey((theme.brightness, theme.colorScheme)),
                viewType: WebOutputPreview.viewType,
                creationParamsCodec: const StandardMessageCodec(),
                creationParams: {
                  'source': widget.source,
                  'dark': theme.brightness == Brightness.dark,
                  'format': language,
                  'palette': {
                    'canvas': theme.colorScheme.surface.toARGB32(),
                    'panel': theme.canvasColor.toARGB32(),
                    'text': theme.colorScheme.onSurface.toARGB32(),
                    'muted': theme.colorScheme.onSurfaceVariant.toARGB32(),
                    'border': theme.colorScheme.outlineVariant.toARGB32(),
                    'error': theme.colorScheme.error.toARGB32(),
                    'accent': theme.colorScheme.primary.toARGB32(),
                  },
                },
              ),
      ),
    );
  }
}
