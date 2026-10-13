import '../widgets/studio_action_label.dart';
import '../widgets/studio_error.dart';
import '../widgets/project_folder_picker.dart';
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
  'flame': Icons.local_fire_department_outlined,
  'star-full': Icons.star_outline,
  'heart': Icons.favorite_outline,
  'zap': Icons.bolt_outlined,
  'target': Icons.adjust,
  'lightbulb': Icons.lightbulb_outline,
  'tools': Icons.handyman_outlined,
  'device-desktop': Icons.desktop_windows_outlined,
  'device-mobile': Icons.phone_android_outlined,
  'terminal': Icons.terminal,
  'dashboard': Icons.dashboard_outlined,
  'globe': Icons.public,
  'broadcast': Icons.cell_tower_outlined,
  'cloud': Icons.cloud_outlined,
  'database': Icons.storage_outlined,
  'package': Icons.inventory_2_outlined,
  'book': Icons.menu_book_outlined,
  'organization': Icons.business_outlined,
  'bug': Icons.bug_report_outlined,
  'shield': Icons.shield_outlined,
  'key': Icons.key_outlined,
  'gift': Icons.card_giftcard_outlined,
  'telescope': Icons.travel_explore_outlined,
  'home': Icons.home_outlined,
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
            _ProjectAppearancePicker(
              color: _color,
              icon: _icon,
              enabled: !_pending,
              onColor: (value) => setState(() => _color = value),
              onIcon: (value) => setState(() => _icon = value),
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
        StudioButtonPress(
          child: TextButton(
            onPressed: _pending ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        StudioButtonPress(
          child: FilledButton(
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
        ),
      ],
    ),
  );
}

class _ProjectAppearancePicker extends StatelessWidget {
  const _ProjectAppearancePicker({
    required this.color,
    required this.icon,
    required this.enabled,
    required this.onColor,
    required this.onIcon,
  });

  final String color;
  final String icon;
  final bool enabled;
  final ValueChanged<String> onColor;
  final ValueChanged<String> onIcon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Color'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ChoiceButton(
            key: const ValueKey('project-color-none'),
            selected: color.isEmpty,
            label: 'Default color',
            onPressed: !enabled ? null : () => onColor(''),
            child: const Icon(Icons.block, size: 20),
          ),
          for (var index = 0; index < _projectColors.length; index++)
            _ChoiceButton(
              key: ValueKey('project-color-$index'),
              selected: color == _projectColors[index],
              label: 'Color ${index + 1}',
              onPressed: !enabled ? null : () => onColor(_projectColors[index]),
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
            selected: icon.isEmpty,
            label: 'Default icon',
            onPressed: !enabled ? null : () => onIcon(''),
            child: const Icon(Icons.restart_alt, size: 20),
          ),
          for (final entry in _projectIcons.entries)
            _ChoiceButton(
              key: ValueKey('project-icon-${entry.key}'),
              selected: icon == entry.key,
              label: entry.key,
              onPressed: !enabled ? null : () => onIcon(entry.key),
              child: Icon(entry.value, size: 20),
            ),
        ],
      ),
    ],
  );
}

/// One draft keeps the project's name, host folder and appearance together.
class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({
    super.key,
    required this.discover,
    required this.create,
  });

  final Future<List<ProjectFolderSuggestion>> Function() discover;
  final Future<void> Function(ProjectCreationDraft) create;

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _name = TextEditingController();
  final _errorScroll = ScrollController();
  String _path = '';
  String _color = '';
  String _icon = 'folder-library';
  bool _pending = false;
  String? _failure;

  @override
  void dispose() {
    _name.dispose();
    _errorScroll.dispose();
    super.dispose();
  }

  Future<void> _chooseFolder() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => ProjectFolderPickerDialog(discover: widget.discover),
    );
    if (!mounted || path == null) return;
    setState(() => _path = path);
  }

  Future<void> _create() async {
    if (_pending || _name.text.trim().isEmpty || _path.isEmpty) return;
    setState(() {
      _pending = true;
      _failure = null;
    });
    try {
      await widget.create((
        name: _name.text.trim(),
        path: _path,
        color: _color,
        icon: _icon,
      ));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = error is StateError
              ? error.message.toString()
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_pending,
    child: AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('New project'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                projectAvatar(
                  context,
                  BrowserProject(
                    id: 'draft',
                    name: _name.text,
                    color: _color,
                    icon: _icon,
                  ),
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('project-name-field'),
                    controller: _name,
                    enabled: !_pending,
                    maxLength: 200,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Project name',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _path.isEmpty ? 'Choose a folder on Hermes' : _path,
                    key: const ValueKey('project-chosen-folder'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                StudioButtonPress(
                  child: IconButton.outlined(
                    key: const ValueKey('project-choose-folder'),
                    tooltip: 'Choose project folder',
                    onPressed: _pending ? null : _chooseFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _ProjectAppearancePicker(
              color: _color,
              icon: _icon,
              enabled: !_pending,
              onColor: (value) => setState(() => _color = value),
              onIcon: (value) => setState(() => _icon = value),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_failure != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: Scrollbar(
                    controller: _errorScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const ValueKey('project-create-error'),
                      controller: _errorScroll,
                      primary: false,
                      child: StudioError(_failure!),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  StudioButtonPress(
                    child: IconButton(
                      tooltip: 'Cancel',
                      onPressed: _pending ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  StudioButtonPress(
                    child: IconButton.filled(
                      key: const ValueKey('project-create-confirm'),
                      tooltip: 'Create project',
                      onPressed:
                          _pending || _name.text.trim().isEmpty || _path.isEmpty
                          ? null
                          : _create,
                      icon: _pending
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                value: MediaQuery.disableAnimationsOf(context)
                                    ? 0.75
                                    : null,
                                strokeWidth: 2,
                                semanticsLabel: 'Creating project',
                              ),
                            )
                          : const Icon(Icons.check),
                    ),
                  ),
                ],
              ),
            ],
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
    child: StudioButtonPress(
      child: IconButton(
        tooltip: label,
        isSelected: selected,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
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
