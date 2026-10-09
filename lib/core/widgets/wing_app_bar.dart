import 'package:flutter/material.dart';
import 'health_alerts/health_alert_bell.dart';

/// All routes share the Chats density: a 48dp title/action row, followed by
/// optional scope context. At enlarged text, secondary actions get their own
/// row; the bell always remains beside the title. No business policy or I/O.
class WingAppBar extends StatelessWidget implements PreferredSizeWidget {
  WingAppBar({
    super.key,
    required BuildContext context,
    this.title,
    this.leading,
    this.actions = const [],
    this.contextRow,
    this.contextHeight = 48,
    this.bottom,
    this.backgroundColor,
    this.surfaceTintColor,
    this.shape,
    this.centerTitle = false,
    this.titleSpacing = 8,
    this.automaticallyImplyLeading = true,
    bool inlineActions = false,
  }) : _large =
           !inlineActions && MediaQuery.textScalerOf(context).scale(16) >= 24 {
    final style = titleStyle(context);
    final label = title is Text ? (title as Text).data : null;
    final available =
        (MediaQuery.sizeOf(context).width -
                56 -
                16 -
                48 -
                (_large ? 0 : actions.length * 48))
            .clamp(80.0, double.infinity);
    final painter = TextPainter(
      text: TextSpan(text: label ?? 'Title', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: title is Text ? (title as Text).maxLines ?? 6 : 1,
    )..layout(maxWidth: available);
    _rowHeight = (painter.height + 8).clamp(48.0, double.infinity);
    painter.dispose();
  }
  final Widget? title, leading, contextRow;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final double contextHeight, titleSpacing;
  final Color? backgroundColor, surfaceTintColor;
  final ShapeBorder? shape;
  final bool centerTitle, automaticallyImplyLeading;
  final bool _large;
  late final double _rowHeight;
  static TextStyle titleStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleLarge!.copyWith(fontSize: 24, fontWeight: FontWeight.w600);
  double get _bottomHeight =>
      (contextRow == null ? 0 : contextHeight) +
      (_large && actions.isNotEmpty ? 48 : 0) +
      (bottom?.preferredSize.height ?? 0);
  @override
  Size get preferredSize => Size.fromHeight(_rowHeight + _bottomHeight);
  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: _rowHeight,
    titleSpacing: titleSpacing,
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    centerTitle: centerTitle,
    backgroundColor: backgroundColor,
    surfaceTintColor: surfaceTintColor,
    shape: shape,
    titleTextStyle: titleStyle(context),
    title: title == null
        ? null
        : MediaQuery(
            data: MediaQuery.of(context),
            child: title is Text && (title as Text).data != null
                ? Text(
                    (title as Text).data!,
                    maxLines: (title as Text).maxLines ?? 6,
                    softWrap: (title as Text).softWrap,
                    overflow: (title as Text).overflow,
                  )
                : title!,
          ),
    actions: [const HealthAlertBell(), if (!_large) ...actions],
    bottom: _bottomHeight == 0
        ? null
        : PreferredSize(
            preferredSize: Size.fromHeight(_bottomHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (contextRow != null)
                  SizedBox(
                    height: contextHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: contextRow,
                    ),
                  ),
                if (_large && actions.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ),
                ?bottom,
              ],
            ),
          ),
  );
}
