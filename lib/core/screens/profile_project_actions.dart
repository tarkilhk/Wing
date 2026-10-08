import '../widgets/studio_action_label.dart';
import '../widgets/studio_error.dart';
import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';
import '../theme/wing_icons.dart';
import '../widgets/workspace_action_menu.dart';

import '../models/chat_list_view.dart';
import '../models/browser_actions.dart';
import '../services/chat_browser_data.dart';

const _projectColors = <String>[
  'hsl(0 68% 58%)',
  'hsl(30 68% 58%)',
  'hsl(60 68% 58%)',
  'hsl(90 68% 58%)',
  'hsl(120 68% 58%)',
  'hsl(150 68% 58%)',
  'hsl(180 68% 58%)',
  'hsl(210 68% 58%)',
  'hsl(240 68% 58%)',
  'hsl(270 68% 58%)',
  'hsl(300 68% 58%)',
  'hsl(330 68% 58%)',
];

const _projectIcons = <String, IconData>{
  'folder-library': Icons.folder_outlined,
  'repo': Icons.account_tree_outlined,
  'rocket': Icons.rocket_launch_outlined,
  'beaker': Icons.science_outlined,
  'star-full': Icons.star_outline,
  'target': Icons.adjust,
  'lightbulb': Icons.lightbulb_outline,
  'terminal': Icons.terminal,
  'globe': Icons.public,
  'database': Icons.storage_outlined,
  'book': Icons.menu_book_outlined,
  'bug': Icons.bug_report_outlined,
};

Future<void> showProjectActions(
  BuildContext context,
  BrowserActionSession session,
) async {
  final choice = await showWorkspaceActionMenu(
    context,
    session.title,
    session.scope.profileName,
    [
      for (final choice in session.choices)
        (
          choice.action == BrowserAction.newChat ? 'new' : choice.action.name,
          choice.label,
          switch (choice.action) {
            BrowserAction.newChat => WingIcons.newChat,
            BrowserAction.rename => Icons.edit_outlined,
            BrowserAction.appearance => Icons.palette_outlined,
            _ => Icons.delete_outline,
          },
          choice.enabled,
        ),
    ],
    keyPrefix: 'project-action',
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'new') {
    if (!await session.perform(BrowserAction.newChat) &&
        session.state.error != null) {
      throw StateError(session.state.error!);
    }
    return;
  }
  final action = BrowserAction.values.byName(choice);
  await showDialog<void>(
    context: context,
    builder: (context) => _ProjectDialog(
      action: action,
      initialName: session.title,
      initialColor: session.project!.color,
      initialIcon: session.project!.icon,
      session: session,
    ),
  );
}

Widget projectAvatar(
  BuildContext context,
  BrowserProject project, {
  double size = 36,
}) {
  final scheme = Theme.of(context).colorScheme;
  final color = _parseProjectColor(project.color) ?? scheme.secondary;
  final icon = _projectIcons[project.icon] ?? Icons.folder_outlined;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: WingRadius.control,
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: (size * 0.55).clamp(16.0, 24.0), color: color),
  );
}

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({
    required this.action,
    required this.initialName,
    required this.initialColor,
    required this.initialIcon,
    required this.session,
  });

  final BrowserAction action;
  final String initialName;
  final String initialColor;
  final String initialIcon;
  final BrowserActionSession session;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late String _color = widget.initialColor;
  late String _icon = widget.initialIcon;
  bool get _pending => widget.session.state.submitting;
  String? get _failure => widget.session.state.error;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await widget.session.perform(
      widget.action,
      name: _name.text,
      color: _color,
      icon: _icon,
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: AlertDialog(
      scrollable: true,
      title: Text(switch (widget.action) {
        BrowserAction.rename => 'Rename project',
        BrowserAction.appearance => 'Project appearance',
        BrowserAction.delete => 'Delete project?',
        _ => throw StateError('Unsupported project dialog'),
      }),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.action == BrowserAction.rename)
            TextField(
              key: const ValueKey('project-name-field'),
              controller: _name,
              autofocus: true,
              enabled: !_pending,
              maxLength: 200,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Project name'),
            )
          else if (widget.action == BrowserAction.appearance) ...[
            const Text('Color'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChoiceButton(
                  key: const ValueKey('project-color-none'),
                  selected: _color.isEmpty,
                  label: 'Default color',
                  onPressed: _pending
                      ? null
                      : () => setState(() => _color = ''),
                  child: const Icon(Icons.block, size: 20),
                ),
                for (var index = 0; index < _projectColors.length; index++)
                  _ChoiceButton(
                    key: ValueKey('project-color-$index'),
                    selected: _color == _projectColors[index],
                    label: 'Color ${index + 1}',
                    onPressed: _pending
                        ? null
                        : () => setState(() => _color = _projectColors[index]),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _parseProjectColor(_projectColors[index]),
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Icon'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChoiceButton(
                  key: const ValueKey('project-icon-none'),
                  selected: _icon.isEmpty,
                  label: 'Default icon',
                  onPressed: _pending ? null : () => setState(() => _icon = ''),
                  child: const Icon(Icons.folder_outlined, size: 20),
                ),
                for (final entry in _projectIcons.entries)
                  _ChoiceButton(
                    key: ValueKey('project-icon-${entry.key}'),
                    selected: _icon == entry.key,
                    label: entry.key,
                    onPressed: _pending
                        ? null
                        : () => setState(() => _icon = entry.key),
                    child: Icon(entry.value, size: 20),
                  ),
              ],
            ),
          ] else
            Text(
              'Remove "${widget.initialName}" from Hermes? Its chats will remain in Recents and All chats. Files on the host will not be deleted.',
            ),
          if (_failure != null) ...[
            const SizedBox(height: 12),
            StudioError(_failure!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _pending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey(switch (widget.action) {
            BrowserAction.rename => 'project-rename-save',
            BrowserAction.appearance => 'project-appearance-save',
            BrowserAction.delete => 'project-delete-confirm',
            _ => throw StateError('Unsupported project dialog'),
          }),
          style: widget.action == BrowserAction.delete
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: _pending ? null : _save,
          child: StudioActionLabel(
            widget.action == BrowserAction.delete ? 'Delete' : 'Save',
            busy: _pending,
          ),
        ),
      ],
    ),
  );
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    super.key,
    required this.selected,
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    selected: selected,
    child: IconButton(
      tooltip: label,
      isSelected: selected,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        side: WidgetStateProperty.resolveWith((states) {
          final colors = Theme.of(context).colorScheme;
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: colors.outlineVariant);
          }
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colors.primary, width: 3);
          }
          return null;
        }),
      ),
      onPressed: onPressed,
      icon: child,
    ),
  );
}

Color? _parseProjectColor(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch(value);
  if (hex != null) {
    var digits = hex.group(1)!;
    if (digits.length == 3) {
      digits = digits.split('').map((digit) => '$digit$digit').join();
    }
    return Color(0xff000000 | int.parse(digits, radix: 16));
  }
  final hsl = RegExp(
    r'^hsl\(\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(\d+(?:\.\d+)?)%\s*[, ]\s*(\d+(?:\.\d+)?)%\s*\)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (hsl == null) return null;
  final hue = double.parse(hsl.group(1)!) % 360;
  final saturation = double.parse(hsl.group(2)!).clamp(0, 100) / 100;
  final lightness = double.parse(hsl.group(3)!).clamp(0, 100) / 100;
  return HSLColor.fromAHSL(
    1,
    hue < 0 ? hue + 360 : hue,
    saturation,
    lightness,
  ).toColor();
}
