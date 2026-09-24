import 'package:flutter/material.dart';

import '../models/hermes_profile.dart';
import '../services/profile_color_store.dart';
import '../theme/profile_colors.dart';
import '../theme/wing_theme.dart';

/// The same direct profile choices in Chats and Administration.
class ProfileSelector extends StatefulWidget {
  const ProfileSelector({
    super.key,
    required this.profiles,
    required this.selectedProfile,
    required this.onSelected,
    this.colors,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.trailing,
  });

  final List<HermesProfile> profiles;
  final String? selectedProfile;
  final ValueChanged<String>? onSelected;
  final ProfileColorStore? colors;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  @override
  State<ProfileSelector> createState() => _ProfileSelectorState();
}

class _ProfileSelectorState extends State<ProfileSelector> {
  final _selected = GlobalKey();
  static const _colorNames = [
    'Red',
    'Orange',
    'Yellow',
    'Lime',
    'Green',
    'Spring',
    'Cyan',
    'Azure',
    'Blue',
    'Violet',
    'Magenta',
    'Rose',
  ];

  Future<void> _chooseColor(HermesProfile profile) async {
    final store = widget.colors;
    if (store == null) return;
    final selected = store.read(profile.name);
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final tokens = WingTokens.of(sheetContext);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Color for ${profile.label}',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: desktopProfileSwatches.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.3,
                ),
                itemBuilder: (context, index) {
                  final color = desktopProfileSwatches[index];
                  final isSelected = selected == index;
                  return Semantics(
                    label: _colorNames[index],
                    selected: isSelected,
                    button: true,
                    onTap: () => Navigator.pop(sheetContext, index),
                    child: ExcludeSemantics(
                      child: TextButton(
                        key: ValueKey('profile-color-$index'),
                        onPressed: () => Navigator.pop(sheetContext, index),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: WingRadius.control,
                            side: BorderSide(
                              color: isSelected ? tokens.accent : tokens.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                            child: isSelected
                                ? Icon(
                                    Icons.check,
                                    size: 18,
                                    color:
                                        ThemeData.estimateBrightnessForColor(
                                              color,
                                            ) ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                key: const ValueKey('profile-color-automatic'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.auto_awesome_outlined, color: tokens.muted),
                title: const Text('Automatic color'),
                trailing: selected == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, -1),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted || choice == (selected ?? -1)) return;
    try {
      final saved = await store.write(
        profile.name,
        choice == -1 ? null : choice,
      );
      if (!saved) throw StateError('Could not save the profile color.');
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the profile color.')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(ProfileSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedProfile != oldWidget.selectedProfile ||
        widget.profiles != oldWidget.profiles) {
      _revealSelection();
    }
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedContext = _selected.currentContext;
      final target = selectedContext?.findRenderObject();
      if (selectedContext != null && target != null) {
        // Only reveal horizontally; never move the enclosing page's position.
        Scrollable.of(
          selectedContext,
        ).position.ensureVisible(target, alignment: .5);
      }
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('profile-selector'),
    height: 48 + (MediaQuery.textScalerOf(context).scale(14) - 14),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: Row(
        children: [
          for (final profile in widget.profiles)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: GestureDetector(
                  onLongPress: widget.colors == null
                      ? null
                      : () => _chooseColor(profile),
                  child: TextButton(
                    key: ValueKey('profile-${profile.name}'),
                    style:
                        TextButton.styleFrom(
                          minimumSize: const Size(48, 36),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          visualDensity: VisualDensity.standard,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          foregroundColor: _profileColor(profile.name),
                          backgroundColor: _profileColor(profile.name)
                              .withValues(
                                alpha: widget.selectedProfile == profile.name
                                    ? 0.22
                                    : 0.09,
                              ),
                          shape: RoundedRectangleBorder(
                            borderRadius: WingRadius.control,
                          ),
                        ).copyWith(
                          side: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.focused)) {
                              return BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              );
                            }
                            return BorderSide(
                              color: _profileColor(
                                profile.name,
                              ).withValues(alpha: 0.28),
                            );
                          }),
                        ),
                    onPressed: widget.onSelected == null
                        ? null
                        : () => widget.onSelected!(profile.name),
                    child: Semantics(
                      key: widget.selectedProfile == profile.name
                          ? _selected
                          : null,
                      selected: widget.selectedProfile == profile.name,
                      child: Text(
                        profile.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.trailing != null) Center(child: widget.trailing!),
        ],
      ),
    ),
  );

  Color _profileColor(String name) {
    final choice = widget.colors?.read(name);
    final color = choice == null
        ? desktopProfileColor(name)
        : desktopProfileSwatches[choice];
    if (color == null) return WingTokens.of(context).muted;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(
          Theme.of(context).brightness == Brightness.dark ? .68 : .34,
        )
        .toColor();
  }
}
