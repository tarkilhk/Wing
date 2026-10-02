import 'package:flutter/material.dart';

/// Retains stock Markdown paragraph text controls without changing its spans or
/// layout. Images and custom inline widgets remain owned by their builders.
List<Widget> retainMarkdownParagraphText(List<Widget> children) => [
  for (final child in children)
    if (child is Column)
      Column(
        key: child.key,
        mainAxisAlignment: child.mainAxisAlignment,
        mainAxisSize: child.mainAxisSize,
        crossAxisAlignment: child.crossAxisAlignment,
        textDirection: child.textDirection,
        verticalDirection: child.verticalDirection,
        textBaseline: child.textBaseline,
        spacing: child.spacing,
        children: [
          for (final (index, run) in child.children.indexed)
            _retainInlineRun(run, index),
        ],
      )
    else
      child,
];

Widget _retainInlineRun(Widget child, int index) {
  if (child is Padding && child.child is Wrap) {
    return Padding(
      key: child.key,
      padding: child.padding,
      child: _retainInlineRun(child.child!, index),
    );
  }
  if (child is! Wrap) return child;
  return Wrap(
    key: child.key,
    direction: child.direction,
    alignment: child.alignment,
    spacing: child.spacing,
    runAlignment: child.runAlignment,
    runSpacing: child.runSpacing,
    crossAxisAlignment: child.crossAxisAlignment,
    textDirection: child.textDirection,
    verticalDirection: child.verticalDirection,
    clipBehavior: child.clipBehavior,
    children: [
      for (final (position, text) in child.children.indexed)
        if (text is SelectableText &&
            text.textSpan != null &&
            // The stock inline merger leaves zero-span custom widgets alone.
            text.textSpan!.children?.isEmpty != true &&
            text.key is UniqueKey)
          _ParagraphText(key: ValueKey((index, position)), text: text)
        else
          text,
    ],
  );
}

class _ParagraphText extends StatefulWidget {
  const _ParagraphText({super.key, required this.text});

  final SelectableText text;

  @override
  State<_ParagraphText> createState() => _ParagraphTextState();
}

class _ParagraphTextState extends State<_ParagraphText> {
  EditableTextState? _editable;

  void _selectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    // Locate the inner controller only when the user selects text; ordinary
    // streaming updates do not traverse the widget tree.
    if (selection.isValid && !selection.isCollapsed && _editable == null) {
      void visit(Element element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          _editable = element.state as EditableTextState;
        } else if (_editable == null) {
          element.visitChildElements(visit);
        }
      }

      context.visitChildElements(visit);
    }
    widget.text.onSelectionChanged?.call(selection, cause);
  }

  @override
  void didUpdateWidget(covariant _ParagraphText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final editable = _editable;
    if (editable == null || !editable.mounted) return;
    final selection = editable.widget.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final span = widget.text.textSpan!;
    final before = oldWidget.text.textSpan!.toPlainText(
      includeSemanticsLabels: false,
    );
    final after = span.toPlainText(includeSemanticsLabels: false);
    if (!after.startsWith(before) || selection.end > after.length) return;
    final hadFocus = editable.widget.focusNode.hasFocus;

    // SelectableText replaces its private controller when spans change, even
    // when its State survives. Restore an unchanged selected range after that
    // update, unless the user has made a newer selection or the source changed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !editable.mounted ||
          !identical(widget.text.textSpan, span) ||
          (hadFocus && !editable.widget.focusNode.hasFocus)) {
        return;
      }
      final controller = editable.widget.controller;
      if (!controller.selection.isValid) controller.selection = selection;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    // These are the exact properties set by the stock paragraph builder. Its
    // original selection callback and current link recognizers remain intact.
    return SelectableText.rich(
      text.textSpan!,
      textScaler: text.textScaler,
      textAlign: text.textAlign,
      onSelectionChanged: _selectionChanged,
      onTap: text.onTap,
    );
  }
}
