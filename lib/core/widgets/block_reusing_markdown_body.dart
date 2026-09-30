import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Retains unchanged top-level prose blocks while a message grows.
///
/// Every update still parses the complete Markdown document, so a late link
/// reference or a new setext/table/list line can change an earlier block. Only
/// blocks with an identical resolved AST keep their widgets and recognizers.
class BlockReusingMarkdownBody extends MarkdownBody {
  const BlockReusingMarkdownBody({
    super.key,
    required super.data,
    super.selectable,
    super.styleSheet,
    super.styleSheetTheme,
    super.syntaxHighlighter,
    super.onSelectionChanged,
    super.onTapLink,
    super.onTapText,
    super.imageDirectory,
    super.blockSyntaxes,
    super.inlineSyntaxes,
    super.extensionSet,
    super.sizedImageBuilder,
    super.checkboxBuilder,
    super.bulletBuilder,
    super.builders,
    super.paddingBuilders,
    super.listItemCrossAxisAlignment,
    super.shrinkWrap,
    super.fitContent,
    super.softLineBreak,
  });

  @override
  State<MarkdownWidget> createState() => _BlockReusingMarkdownBodyState();
}

class _BlockReusingMarkdownBodyState extends State<MarkdownWidget> {
  List<_RenderedBlock> _blocks = [];
  Widget? _content;
  bool _refreshBlocks = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Match the stock renderer's theme/text-scale dependencies. Viewport width
    // also matters for the message's inline attachment and image builders.
    _content = null;
    _refreshBlocks = true;
  }

  @override
  void didUpdateWidget(covariant MarkdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) _content = null;
    if (widget.selectable != oldWidget.selectable ||
        widget.styleSheet != oldWidget.styleSheet ||
        widget.styleSheetTheme != oldWidget.styleSheetTheme ||
        widget.syntaxHighlighter != oldWidget.syntaxHighlighter ||
        widget.onSelectionChanged != oldWidget.onSelectionChanged ||
        widget.onTapText != oldWidget.onTapText ||
        widget.imageDirectory != oldWidget.imageDirectory ||
        widget.blockSyntaxes != oldWidget.blockSyntaxes ||
        widget.inlineSyntaxes != oldWidget.inlineSyntaxes ||
        widget.extensionSet != oldWidget.extensionSet ||
        widget.sizedImageBuilder != oldWidget.sizedImageBuilder ||
        widget.checkboxBuilder != oldWidget.checkboxBuilder ||
        widget.bulletBuilder != oldWidget.bulletBuilder ||
        widget.builders != oldWidget.builders ||
        widget.paddingBuilders != oldWidget.paddingBuilders ||
        widget.listItemCrossAxisAlignment !=
            oldWidget.listItemCrossAxisAlignment ||
        widget.fitContent != oldWidget.fitContent ||
        widget.softLineBreak != oldWidget.softLineBreak ||
        (widget as MarkdownBody).shrinkWrap !=
            (oldWidget as MarkdownBody).shrinkWrap ||
        (widget.onTapLink == null) != (oldWidget.onTapLink == null)) {
      _content = null;
      _refreshBlocks = true;
    }
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      block.delegate.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_content != null) return _content!;
    MediaQuery.sizeOf(context);
    final cupertino =
        widget.styleSheetTheme == MarkdownStyleSheetBaseTheme.cupertino ||
        (widget.styleSheetTheme == MarkdownStyleSheetBaseTheme.platform &&
            (Platform.isIOS || Platform.isMacOS));
    final fallback = cupertino
        ? MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context))
        : MarkdownStyleSheet.fromTheme(Theme.of(context));
    final style = fallback
        .copyWith(textScaler: MediaQuery.textScalerOf(context))
        .merge(widget.styleSheet);
    final nodes = md.Document(
      blockSyntaxes: widget.blockSyntaxes,
      inlineSyntaxes: widget.inlineSyntaxes,
      extensionSet: widget.extensionSet ?? md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(const LineSplitter().convert(widget.data));
    final next = <_RenderedBlock>[];
    // Heading padding builders mutate the AST and manage document scroll keys.
    // Keep their existing full-render behavior until their anchors are assigned
    // independently of renderer traversal.
    final refresh = _refreshBlocks || widget.paddingBuilders.isNotEmpty;
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final signature = jsonEncode(_astValue(node));
      final previous = index < _blocks.length ? _blocks[index] : null;
      if (!refresh && previous?.signature == signature) {
        next.add(previous!);
        continue;
      }
      previous?.delegate.dispose();
      final delegate = _BlockDelegate(this);
      final children = MarkdownBuilder(
        delegate: delegate,
        selectable: widget.selectable,
        styleSheet: style,
        imageDirectory: widget.imageDirectory,
        sizedImageBuilder: widget.sizedImageBuilder,
        checkboxBuilder: widget.checkboxBuilder,
        bulletBuilder: widget.bulletBuilder,
        builders: widget.builders,
        paddingBuilders: widget.paddingBuilders,
        fitContent: widget.fitContent,
        listItemCrossAxisAlignment: widget.listItemCrossAxisAlignment,
        onSelectionChanged: widget.onSelectionChanged,
        onTapText: widget.onTapText,
        softLineBreak: widget.softLineBreak,
      ).build([node]);
      next.add(_RenderedBlock(signature, children, delegate));
    }
    for (var index = next.length; index < _blocks.length; index++) {
      _blocks[index].delegate.dispose();
    }
    _blocks = next;
    _refreshBlocks = false;
    final children = <Widget>[];
    for (final block in _blocks) {
      if (block.children.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(SizedBox(height: style.blockSpacing));
      }
      children.addAll(block.children);
    }
    // Keep this parent even with a single block: adding a second block must
    // retain the first block's mounted selectable text and attachment state.
    return _content = Column(
      mainAxisSize: (widget as MarkdownBody).shrinkWrap
          ? MainAxisSize.min
          : MainAxisSize.max,
      crossAxisAlignment: widget.fitContent
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

Object _astValue(md.Node node) {
  if (node is md.Text) return ['text', node.text];
  final element = node as md.Element;
  final keys = element.attributes.keys.toList()..sort();
  return [
    element.tag,
    {for (final key in keys) key: element.attributes[key]},
    element.children?.map(_astValue).toList(),
  ];
}

class _RenderedBlock {
  _RenderedBlock(this.signature, this.children, this.delegate);
  final String signature;
  final List<Widget> children;
  final _BlockDelegate delegate;
}

class _BlockDelegate implements MarkdownBuilderDelegate {
  _BlockDelegate(this.owner);
  final _BlockReusingMarkdownBodyState owner;
  final _recognizers = <GestureRecognizer>[];

  @override
  BuildContext get context => owner.context;

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => owner.widget.onTapLink?.call(text, href, title);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    code = code.replaceAll(RegExp(r'\n$'), '');
    return owner.widget.syntaxHighlighter?.format(code) ??
        TextSpan(style: styleSheet.code, text: code);
  }

  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}
