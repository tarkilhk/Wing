import '../widgets/studio_action_label.dart';
import '../widgets/studio_error.dart';
import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';
import '../widgets/workspace_action_menu.dart';

import '../services/profile_workspace_controller.dart';

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

enum _ProjectAction { rename, appearance, delete }

Future<void> showProjectActions(
  BuildContext context,
  ProfileWorkspaceController controller,
  Map<String, dynamic> project,
) async {
  final current = controller.current;
  if (current == null) return;
  final owner = current.scope;
  final captured = Map<String, dynamic>.from(project);
  final id = captured['id']?.toString().trim() ?? '';
  if (id.isEmpty) return;
  final rawName = captured['name']?.toString().trim();
  final name = rawName == null || rawName.isEmpty
      ? 'Untitled project'
      : rawName;

  final choice =
      await showWorkspaceActionMenu(context, name, owner.profileName, [
        ('new', 'New chat', Icons.add_rounded, true),
        ('rename', 'Rename', Icons.edit_outlined, true),
        ('appearance', 'Appearance', Icons.palette_outlined, true),
        ('delete', 'Delete', Icons.delete_outline, true),
      ], keyPrefix: 'project-action');
  if (choice == null || !context.mounted) return;
  if (choice == 'new') {
    final resource = controller.current;
    if (resource == null || resource.scope != owner) {
      throw StateError('Profile changed. Open the menu again.');
    }
    final target = resource.projects.firstWhere(
      (project) => project['id'] == id,
      orElse: () =>
          throw StateError('Project is unavailable. Open the menu again.'),
    );
    await controller.createChat(inProject: target, owner: owner);
    return;
  }
  final action = _ProjectAction.values.byName(choice);

  await showDialog<void>(
    context: context,
    builder: (context) => _ProjectDialog(
      action: action,
      initialName: name,
      initialColor: captured['color']?.toString() ?? '',
      initialIcon: captured['icon']?.toString() ?? '',
      submit: (name, color, icon) => switch (action) {
        _ProjectAction.rename => controller.updateProject(
          owner,
          id,
          name: name,
        ),
        _ProjectAction.appearance => controller.updateProject(
          owner,
          id,
          color: color,
          icon: icon,
        ),
        _ProjectAction.delete => controller.deleteProject(owner, id),
      },
    ),
  );
}

Widget projectAvatar(
  BuildContext context,
  Map<String, dynamic> project, {
  double size = 36,
}) {
  final scheme = Theme.of(context).colorScheme;
  final color =
      _parseProjectColor(project['color']?.toString()) ?? scheme.secondary;
  final icon =
      _projectIcons[project['icon']?.toString()] ?? Icons.folder_outlined;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: HermesRadius.control,
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: (size * 0.55).clamp(16.0, 24.0), color: color),
  );
}

typedef _ProjectSubmit =
    Future<void> Function(String name, String color, String icon);

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({
    required this.action,
    required this.initialName,
    required this.initialColor,
    required this.initialIcon,
    required this.submit,
  });

  final _ProjectAction action;
  final String initialName;
  final String initialColor;
  final String initialIcon;
  final _ProjectSubmit submit;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late String _color = widget.initialColor;
  late String _icon = widget.initialIcon;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (_submitting || widget.action == _ProjectAction.rename && name.isEmpty) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.submit(name, _color, _icon);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        final message = error is StateError ? error.message.toString() : '';
        _error =
            message.startsWith('Profile changed.') ||
                message.startsWith('Project is unavailable.')
            ? message
            : 'The project change was not acknowledged. Check the connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(switch (widget.action) {
      _ProjectAction.rename => 'Rename project',
      _ProjectAction.appearance => 'Project appearance',
      _ProjectAction.delete => 'Delete project?',
    }),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.action == _ProjectAction.rename)
          TextField(
            key: const ValueKey('project-name-field'),
            controller: _name,
            autofocus: true,
            enabled: !_submitting,
            maxLength: 200,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Project name'),
          )
        else if (widget.action == _ProjectAction.appearance) ...[
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
                onPressed: _submitting
                    ? null
                    : () => setState(() => _color = ''),
                child: const Icon(Icons.block, size: 20),
              ),
              for (var index = 0; index < _projectColors.length; index++)
                _ChoiceButton(
                  key: ValueKey('project-color-$index'),
                  selected: _color == _projectColors[index],
                  label: 'Color ${index + 1}',
                  onPressed: _submitting
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
                onPressed: _submitting
                    ? null
                    : () => setState(() => _icon = ''),
                child: const Icon(Icons.folder_outlined, size: 20),
              ),
              for (final entry in _projectIcons.entries)
                _ChoiceButton(
                  key: ValueKey('project-icon-${entry.key}'),
                  selected: _icon == entry.key,
                  label: entry.key,
                  onPressed: _submitting
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
        if (_error != null) ...[
          const SizedBox(height: 12),
          StudioError(_error!),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: ValueKey(switch (widget.action) {
          _ProjectAction.rename => 'project-rename-save',
          _ProjectAction.appearance => 'project-appearance-save',
          _ProjectAction.delete => 'project-delete-confirm',
        }),
        style: widget.action == _ProjectAction.delete
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        onPressed: _submitting ? null : _save,
        child: StudioActionLabel(
          widget.action == _ProjectAction.delete ? 'Delete' : 'Save',
          busy: _submitting,
        ),
      ),
    ],
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
        side: WidgetStateProperty.resolveWith((states) {
          final colors = Theme.of(context).colorScheme;
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: colors.outlineVariant);
          }
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colors.primary, width: 3);
          }
          return selected ? BorderSide(color: colors.primary, width: 2) : null;
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
