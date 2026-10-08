import 'package:flutter/material.dart';

import '../presentation/resource_identity.dart';
import '../theme/wing_theme.dart';

/// Compact resource identity. The tap reveals the exact supplied target nearby;
/// it does not resolve relative paths against the client's filesystem.
class ResourceFilename extends StatelessWidget {
  final String target;
  final String? label;
  final TextStyle? style;

  const ResourceFilename({
    super.key,
    required this.target,
    this.label,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    Offset? tapPosition;
    final uri = Uri.tryParse(target);
    final address =
        uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
    Future<void> showPath() async {
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()!
              as RenderBox;
      final ownBox = context.findRenderObject()! as RenderBox;
      final position = overlay.globalToLocal(
        tapPosition ?? ownBox.localToGlobal(ownBox.size.center(Offset.zero)),
      );
      final tokens = WingTokens.of(context);
      await showMenu<void>(
        context: context,
        requestFocus: false,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(position.dx, position.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        constraints: BoxConstraints(
          maxWidth: (overlay.size.width - 16).clamp(0, 360),
        ),
        color: tokens.raised,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: WingRadius.card,
          side: BorderSide(color: tokens.border),
        ),
        menuPadding: const EdgeInsets.all(WingSpacing.sm),
        items: [
          PopupMenuItem<void>(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child: SelectableText(
              target,
              style: tokens.typography.mono.copyWith(color: tokens.onSurface),
            ),
          ),
        ],
      );
    }

    return Tooltip(
      message: address ? 'Show resource address' : 'Show file path',
      child: InkWell(
        onTapDown: (details) => tapPosition = details.globalPosition,
        onTap: showPath,
        borderRadius: WingRadius.control,
        child: Text(
          label ?? resourceFileName(target),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

/// The activity viewer's deliberate compact-control exception to page controls.
class ResourceViewerAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const ResourceViewerAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: const EdgeInsets.all(WingSpacing.sm),
    style: IconButton.styleFrom(
      minimumSize: const Size(32, 32),
      maximumSize: const Size(32, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(icon, size: 16),
  );
}

/// One header geometry for document, image, HTML, SVG and PDF file viewers.
class ResourceViewerAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String? target;
  final List<Widget> actions;
  final bool stacked;

  ResourceViewerAppBar({
    super.key,
    required BuildContext context,
    required this.title,
    this.target,
    this.actions = const [],
  }) : stacked = MediaQuery.textScalerOf(context).scale(14) > 21;

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (stacked && actions.isNotEmpty ? 40 : 0),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    return AppBar(
      titleSpacing: WingSpacing.sm,
      backgroundColor: tokens.raised,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: tokens.border)),
      title: target == null
          ? Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.section,
            )
          : ResourceFilename(target: target!, style: tokens.typography.section),
      actions: stacked
          ? null
          : [
              ...actions,
              if (actions.isNotEmpty) const SizedBox(width: WingSpacing.sm),
            ],
      bottom: stacked && actions.isNotEmpty
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: Padding(
                padding: const EdgeInsets.only(
                  right: WingSpacing.sm,
                  bottom: WingSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ),
            )
          : null,
    );
  }
}
