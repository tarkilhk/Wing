import 'studio_task_marker.dart';
import 'studio_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../models/chat_output.dart';
import '../models/deliverable_reference.dart';
import '../services/file_open_error_message.dart';
import '../services/markdown_inline_parser.dart';
import '../services/markdown_qa_variant.dart';
import '../services/completion_diagnostics.dart';
import '../services/web_preview.dart';
import '../theme/profile_markdown_style.dart';
import 'chat_image_preview.dart';
import 'markdown_code_block.dart';
import 'block_reusing_markdown_body.dart';
import 'background_markdown_content.dart';
import 'deliverable_attachment.dart';

/// Renders Markdown message content without conversation chrome.
class MarkdownMessageContent extends StatefulWidget {
  final String data;
  final bool streaming;
  final Future<void> Function(ChatOutput output)? onOpenRemoteFile;
  final Future<bool> Function(ChatOutput output)? onDownloadRemoteFile;
  final bool deliverables;
  final String? documentPath;
  final String? initialFragment;

  const MarkdownMessageContent({
    super.key,
    required this.data,
    this.streaming = false,
    this.onOpenRemoteFile,
    this.onDownloadRemoteFile,
    this.deliverables = false,
    this.documentPath,
    this.initialFragment,
  });

  @override
  State<MarkdownMessageContent> createState() => _MarkdownMessageContentState();
}

class _MarkdownMessageContentState extends State<MarkdownMessageContent> {
  // Retain only this mounted message's rendering. Unrelated stream/activity
  // updates must not split code fences, recreate styles and reparse its prose.
  Widget? _content;
  List<({Object source, Widget child})> _segments = const [];
  bool _refreshSegments = true;
  bool _segmentsStreaming = false;
  MarkdownStyleSheet? _styleSheet;
  ThemeData? _markdownTheme;
  Map<String, MarkdownElementBuilder>? _markdownBuilders;
  final _parsers = <int, MarkdownInlineParser>{};
  final _deliverableSyntaxes = <md.InlineSyntax>[
    MediaReferenceSyntax(),
    DeliverableLinkSyntax(),
    DeliverableCodeSyntax(
      guard: markdownQaVariant != MarkdownQaVariant.baseline,
    ),
    HtmlFilePathSyntax(),
  ];
  final _headingKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.event(
        'markdown.message.init',
        values: {'streaming': widget.streaming ? 1 : 0},
      );
    }
    _scheduleFragment();
  }

  void _scheduleFragment() {
    if (widget.initialFragment == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToFragment(widget.initialFragment!);
    });
  }

  Future<void> _scrollToFragment(String fragment) async {
    final target = fragment.isEmpty
        ? context
        : _headingKeys[fragment]?.currentContext;
    if (target != null) {
      // The marker is inline; align the complete heading, not its midpoint.
      final heading = target.findAncestorRenderObjectOfType<RenderWrap>();
      await Scrollable.of(target).position.ensureVisible(
        heading ?? target.findRenderObject()!,
        alignment: 0,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: StudioError('This heading is not in the available preview.'),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data ||
        widget.streaming != oldWidget.streaming ||
        widget.deliverables != oldWidget.deliverables ||
        widget.documentPath != oldWidget.documentPath ||
        widget.initialFragment != oldWidget.initialFragment ||
        (widget.onOpenRemoteFile == null) !=
            (oldWidget.onOpenRemoteFile == null) ||
        (widget.onDownloadRemoteFile == null) !=
            (oldWidget.onDownloadRemoteFile == null)) {
      _content = null;
      if (CompletionDiagnostics.enabled) {
        CompletionDiagnostics.event(
          'markdown.message.invalidate',
          values: {
            'dataChanged': widget.data != oldWidget.data ? 1 : 0,
            'streamingChanged': widget.streaming != oldWidget.streaming ? 1 : 0,
          },
        );
      }
    }
    if (widget.deliverables != oldWidget.deliverables ||
        widget.documentPath != oldWidget.documentPath ||
        (widget.onOpenRemoteFile == null) !=
            (oldWidget.onOpenRemoteFile == null) ||
        (widget.onDownloadRemoteFile == null) !=
            (oldWidget.onDownloadRemoteFile == null)) {
      _markdownBuilders = null;
      _refreshSegments = true;
      _parsers.clear();
    }
    if (widget.initialFragment != oldWidget.initialFragment) {
      _scheduleFragment();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.event('markdown.message.dependencies');
    }
    // Theme, text scale and viewport changes still refresh the rendered content.
    _content = null;
    _styleSheet = null;
    _markdownTheme = null;
    _markdownBuilders = null;
    _refreshSegments = true;
  }

  Future<void> _open(BuildContext context, String href) async {
    final uri = externalWebLink(href);
    var opened = false;
    if (uri != null) {
      opened = await openWebPreview(uri);
    } else {
      final output = widget.documentPath == null
          ? explicitRemoteFileOutput(href)
          : resolveDocumentFileLink(href, widget.documentPath!);
      if (output != null &&
          output.path == widget.documentPath &&
          output.fragment != null) {
        await _scrollToFragment(output.fragment!);
        return;
      }
      if (output != null && widget.onOpenRemoteFile != null) {
        try {
          await widget.onOpenRemoteFile!(output);
          return;
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: StudioError(fileOpenErrorMessage(error))),
            );
          }
          return;
        }
      }
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: StudioError(
            uri == null
                ? 'Only web links and linked Hermes files can be opened here.'
                : 'Could not open this link.',
          ),
        ),
      );
    }
  }

  void _previewImage(BuildContext context, String href, String title) {
    final uri = externalWebLink(href);
    if (uri == null) {
      _open(context, href);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (previewContext) => ChatImagePreview(
          uri: uri,
          title: title,
          onOpenExternal: () => _open(previewContext, href),
        ),
      ),
    );
  }

  void _tapLink(String text, String? href, String title) {
    if (href != null) _open(context, href);
  }

  Widget _buildImage(MarkdownImageConfig config) => OutlinedButton.icon(
    onPressed: () =>
        _previewImage(context, config.uri.toString(), config.alt ?? 'Image'),
    icon: const Icon(Icons.image_outlined),
    label: Text(
      config.alt ?? 'Open image link',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_content != null) {
      if (CompletionDiagnostics.enabled) {
        CompletionDiagnostics.event('markdown.message.cached');
      }
      return _content!;
    }
    final start = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final result = _content = _buildContent(context);
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.finish(
        'markdown.message.build',
        start,
        values: {'segments': _segments.length},
      );
    }
    return result;
  }

  Widget _buildContent(BuildContext context) {
    MediaQuery.sizeOf(context);
    MediaQuery.textScalerOf(context);
    final theme = Theme.of(context);
    final styleSheet = _styleSheet ??= profileMarkdownStyle(theme);
    final markdownTheme = _markdownTheme ??= profileMarkdownTheme(theme);
    final builders = _markdownBuilders ??= {
      if (widget.documentPath != null)
        _headingAnchorTag: _HeadingAnchorBuilder(_headingKeys),
      if (widget.deliverables)
        deliverableElementTag: _DeliverableBuilder(
          widget.onOpenRemoteFile == null
              ? null
              : (output) => widget.onOpenRemoteFile!(output),
          widget.onDownloadRemoteFile == null
              ? null
              : (output) => widget.onDownloadRemoteFile!(output),
          maxWidth: MediaQuery.sizeOf(context).width,
        ),
    };
    _headingKeys.clear();
    final headings = _HeadingBuilder(_headingKeys);
    final splitStart = CompletionDiagnostics.enabled
        ? CompletionDiagnostics.start()
        : 0;
    final sources = splitMarkdownCodeBlocks(
      widget.data,
      streaming: widget.streaming,
    );
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.finish(
        'markdown.fence.split',
        splitStart,
        values: {
          'segments': sources.length,
          'prose': sources.whereType<String>().length,
          'code': sources.whereType<MarkdownCodeBlock>().length,
        },
      );
    }
    final next = <({Object source, Widget child})>[];
    final usedParsers = <int>{};
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      final previous = index < _segments.length ? _segments[index] : null;
      // Retain the complete subtree, including code controls and the inherited
      // wrappers around prose. Heading previews still traverse every segment
      // to rebuild their document-wide anchor registry.
      if (!_refreshSegments &&
          widget.documentPath == null &&
          previous != null &&
          (_segmentsStreaming == widget.streaming ||
              source is MarkdownCodeBlock) &&
          _sameMarkdownSegment(previous.source, source)) {
        next.add(previous);
        if (_parsers.containsKey(index)) usedParsers.add(index);
        continue;
      }
      Widget prose(String text, List<md.Node>? nodes) {
        final options = widget.documentPath != null
            ? MarkdownBody(
                data: text,
                checkboxBuilder: _buildTaskMarker,
                inlineSyntaxes: widget.deliverables
                    ? _deliverableSyntaxes
                    : null,
                paddingBuilders: {
                  for (var level = 1; level <= 6; level++) 'h$level': headings,
                },
                builders: builders,
                selectable: true,
                onTapLink: _tapLink,
                sizedImageBuilder: _buildImage,
                styleSheet: styleSheet,
              )
            : BlockReusingMarkdownBody(
                data: text,
                parsedNodes: nodes,
                checkboxBuilder: _buildTaskMarker,
                inlineSyntaxes: widget.deliverables
                    ? _deliverableSyntaxes
                    : null,
                builders: builders,
                selectable: true,
                onTapLink: _tapLink,
                sizedImageBuilder: _buildImage,
                styleSheet: styleSheet,
              );
        return options;
      }

      List<md.Node>? nodes;
      if (source is String &&
          widget.documentPath == null &&
          markdownQaVariant == MarkdownQaVariant.cache) {
        usedParsers.add(index);
        nodes = (_parsers[index] ??= MarkdownInlineParser(
          deliverables: widget.deliverables,
        )).parse(source);
      }
      final child = source is MarkdownCodeBlock
          ? source
          // This is an inline viewport, not the screen edge. Otherwise the
          // system bottom inset lifts table scrollbars into the last row.
          : MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Theme(
                data: markdownTheme,
                child:
                    widget.documentPath == null &&
                        markdownQaVariant == MarkdownQaVariant.background
                    ? BackgroundMarkdownContent(
                        data: source as String,
                        deliverables: widget.deliverables,
                        streaming: widget.streaming,
                        builder: (text, parsed) => prose(text, parsed),
                      )
                    : prose(source as String, nodes),
              ),
            );
      next.add((source: source, child: child));
    }
    _segments = next;
    _segmentsStreaming = widget.streaming;
    _parsers.removeWhere((index, _) => !usedParsers.contains(index));
    _refreshSegments = false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final segment in next) segment.child],
    );
  }

  @override
  void dispose() {
    if (CompletionDiagnostics.enabled) {
      CompletionDiagnostics.event('markdown.message.dispose');
    }
    super.dispose();
  }
}

bool _sameMarkdownSegment(Object previous, Object current) =>
    previous is String && current is String
    ? previous == current
    : previous is MarkdownCodeBlock &&
          current is MarkdownCodeBlock &&
          previous.code == current.code &&
          previous.language == current.language &&
          previous.previewEnabled == current.previewEnabled;

class _DeliverableBuilder extends MarkdownElementBuilder {
  _DeliverableBuilder(this.onOpen, this.onDownload, {required this.maxWidth});

  final Future<void> Function(ChatOutput)? onOpen;
  final Future<bool> Function(ChatOutput)? onDownload;
  final double maxWidth;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final path = element.attributes['path']!;
    // Keep this an inline node: Markdown tables and emphasized links cannot
    // contain block nodes. Bound table cells, which scroll horizontally, too.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DeliverableAttachment(
        output: ChatOutput(
          kind: ChatOutputKind.values.byName(element.attributes['kind']!),
          path: path,
          url: null,
          label: element.attributes['name']!,
          fragment: element.attributes['fragment']?.isEmpty == false
              ? element.attributes['fragment']
              : null,
        ),
        onOpen: onOpen,
        onDownload: onDownload,
      ),
    );
  }
}

const _headingAnchorTag = 'wing-heading-anchor';

/// Insert an invisible scroll target while retaining the renderer's heading
/// typography, emphasis, links and selection behavior.
class _HeadingBuilder extends MarkdownPaddingBuilder {
  _HeadingBuilder(this.keys);
  final Map<String, GlobalKey> keys;

  @override
  void visitElementBefore(md.Element element) {
    final slug = element.textContent
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\p{L}\p{N}_\-\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s'), '-');
    var id = slug;
    var suffix = 0;
    while (keys.containsKey(id)) {
      id = '$slug-${++suffix}';
    }
    keys[id] = GlobalKey();
    element.children!.insert(
      0,
      md.Element.empty(_headingAnchorTag)..attributes['id'] = id,
    );
  }
}

class _HeadingAnchorBuilder extends MarkdownElementBuilder {
  _HeadingAnchorBuilder(this.keys);
  final Map<String, GlobalKey> keys;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => SizedBox(key: keys[element.attributes['id']], width: 0, height: 1);
}

Widget _buildTaskMarker(bool checked) => StudioTaskMarker(completed: checked);
