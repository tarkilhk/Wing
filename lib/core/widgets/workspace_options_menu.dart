import 'package:flutter/material.dart';

import '../theme/wing_theme.dart';
import 'compact_switch.dart';

/// View filters and workspace commands, anchored below the app-bar control.
class WorkspaceOptionsMenu extends StatelessWidget {
  const WorkspaceOptionsMenu({
    super.key,
    required this.enabled,
    required this.projectsOnly,
    required this.inProject,
    required this.archived,
    required this.unreadOnly,
    required this.includeAutomated,
    required this.onSelected,
  });

  final bool enabled;
  final bool projectsOnly;
  final bool inProject;
  final bool archived;
  final bool unreadOnly;
  final bool includeAutomated;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Workspace options',
      icon: const Icon(Icons.more_horiz, size: 20),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      position: PopupMenuPosition.under,
      offset: const Offset(0, WingSpacing.xs),
      constraints: const BoxConstraints(minWidth: 288, maxWidth: 288),
      color: tokens.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: WingRadius.card,
        side: BorderSide(color: tokens.border),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: WingSpacing.xs),
      requestFocus: true,
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(duration: WingMotion.fast),
      onSelected: onSelected,
      itemBuilder: (_) => [
        if (!projectsOnly) ...[
          if (!inProject && !archived)
            _Option(
              'unread',
              'Unread only',
              Icons.mark_chat_unread_outlined,
              toggled: unreadOnly,
            ),
          _Option(
            'include-automated',
            'Include automated chats',
            Icons.smart_toy_outlined,
            toggled: includeAutomated,
          ),
          const PopupMenuDivider(height: 9),
        ],
        if (inProject)
          _Option('project-actions', 'Project actions', Icons.folder_outlined),
        if (!projectsOnly)
          _Option(
            'new-project',
            'New project',
            Icons.create_new_folder_outlined,
          ),
        if (!archived && !projectsOnly)
          _Option('archived', 'Archived chats', Icons.inventory_2_outlined),
        if (!projectsOnly) const PopupMenuDivider(height: 9),
        _Option('refresh', 'Refresh', Icons.refresh),
      ],
    );
  }
}

class _Option extends PopupMenuItem<String> {
  _Option(String id, this.label, this.icon, {this.toggled})
    : super(
        key: ValueKey('workspace-option-$id'),
        value: id,
        height: 48,
        child: null,
        padding: const EdgeInsets.symmetric(horizontal: WingSpacing.lg),
      );

  final String label;
  final IconData icon;
  final bool? toggled;

  @override
  PopupMenuItemState<String, _Option> createState() => _OptionState();
}

class _OptionState extends PopupMenuItemState<String, _Option> {
  @override
  Widget buildSemantics({required Widget child}) => widget.toggled == null
      ? super.buildSemantics(child: child)
      : Semantics(
          enabled: widget.enabled,
          toggled: widget.toggled,
          child: child,
        );

  @override
  Widget buildChild() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WingSpacing.xs),
      child: Row(
        children: [
          Icon(widget.icon, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: WingSpacing.md),
          Expanded(
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 16,
                color: colors.onSurface,
              ),
            ),
          ),
          if (widget.toggled case final value?) ...[
            const SizedBox(width: WingSpacing.md),
            // The native menu row owns focus, semantics and activation. The
            // switch is its state indicator; tapping it selects the same row.
            ExcludeSemantics(
              child: ExcludeFocus(
                child: IgnorePointer(
                  child: CompactSwitch(value: value, onChanged: (_) {}),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
