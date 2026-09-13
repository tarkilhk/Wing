import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Lets a reversed transcript hold the disclosure header in place during layout.
class ExpansionAnchorNotification extends Notification {
  ExpansionAnchorNotification(this.anchor);

  final BuildContext anchor;
}

class AnchoredExpansionTile extends StatelessWidget {
  const AnchoredExpansionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.children = const [],
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.minTileHeight,
    this.tilePadding,
    this.childrenPadding,
    this.shape,
    this.collapsedShape,
    this.expandedCrossAxisAlignment,
    this.onExpansionChanged,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool maintainState;
  final double? minTileHeight;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry? childrenPadding;
  final ShapeBorder? shape;
  final ShapeBorder? collapsedShape;
  final CrossAxisAlignment? expandedCrossAxisAlignment;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) => _ExpansionSizeObserver(
    child: ExpansionTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      initiallyExpanded: initiallyExpanded,
      maintainState: maintainState,
      minTileHeight: minTileHeight,
      tilePadding: tilePadding,
      childrenPadding: childrenPadding,
      shape: shape,
      collapsedShape: collapsedShape,
      expandedCrossAxisAlignment: expandedCrossAxisAlignment,
      onExpansionChanged: (expanded) {
        ExpansionAnchorNotification(context).dispatch(context);
        onExpansionChanged?.call(expanded);
      },
      children: children,
    ),
  );
}

class _ExpansionSizeObserver extends SingleChildRenderObjectWidget {
  const _ExpansionSizeObserver({required super.child});

  @override
  ExpansionAnchorBox createRenderObject(BuildContext context) =>
      ExpansionAnchorBox();
}

/// Reports the disclosure's own size, without reading descendants during layout.
class ExpansionAnchorBox extends RenderProxyBox {
  ValueChanged<double>? onHeightChanged;

  @override
  void performLayout() {
    final previousHeight = hasSize ? size.height : null;
    super.performLayout();
    if (previousHeight != null && previousHeight != size.height) {
      onHeightChanged?.call(size.height - previousHeight);
    }
  }
}
