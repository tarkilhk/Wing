import 'package:flutter/material.dart';

import '../models/connection.dart';
import '../models/hermes_profile.dart';
import '../theme/wing_theme.dart';
import 'connection_icon_picker.dart';

typedef WorkspaceChoice = ({String id, bool isConnection});

Future<WorkspaceChoice?> showWorkspacePicker(
  BuildContext context, {
  required List<SavedConnection> connections,
  required String connectionId,
  required List<HermesProfile> profiles,
  required String? profileName,
  required bool busy,
  required bool includeProfiles,
}) {
  final tokens = WingTokens.of(context);
  final colors = Theme.of(context).colorScheme;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  RelativeRect position() {
    final box = context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    return RelativeRect.fromRect(
      Rect.fromLTWH(rect.left, rect.bottom + 4, rect.width, 0),
      Offset.zero & overlay.size,
    );
  }

  var lastPosition = position();
  PopupMenuItem<WorkspaceChoice> heading(String label) => PopupMenuItem(
    enabled: false,
    height: 32,
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
  PopupMenuItem<WorkspaceChoice> option(
    WorkspaceChoice value,
    String label,
    bool selected, {
    IconData? icon,
  }) => PopupMenuItem(
    key: ValueKey(
      'workspace-${value.isConnection ? 'connection' : 'profile'}-${value.id}',
    ),
    value: value,
    enabled: !busy,
    padding: EdgeInsets.zero,
    child: Semantics(
      selected: selected,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        color: selected ? colors.primaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  return showMenu<WorkspaceChoice>(
    context: context,
    semanticLabel: includeProfiles
        ? 'Choose connection and profile'
        : 'Choose connection',
    requestFocus: true,
    positionBuilder: (_, _) {
      if (context.mounted) lastPosition = position();
      return lastPosition;
    },
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
    color: tokens.raised,
    surfaceTintColor: Colors.transparent,
    elevation: 4,
    shape: RoundedRectangleBorder(
      borderRadius: WingRadius.card,
      side: BorderSide(color: tokens.border),
    ),
    items: [
      heading('Connection'),
      for (final connection in connections)
        option(
          (id: connection.id, isConnection: true),
          connection.label,
          connection.id == connectionId,
          icon: connection.icon.glyph,
        ),
      if (includeProfiles) ...[
        const PopupMenuDivider(),
        heading('Profile'),
        if (profiles.isEmpty) heading('Profiles unavailable'),
        for (final profile in profiles)
          option(
            (id: profile.name, isConnection: false),
            profile.label,
            profile.name == profileName,
          ),
      ],
    ],
  );
}
