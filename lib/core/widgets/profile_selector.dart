import 'package:flutter/material.dart';

import '../models/hermes_profile.dart';
import '../theme/profile_workspace_theme.dart';
import '../theme/wing_theme.dart';

/// The same direct profile choices in Chats and Administration.
class ProfileSelector extends StatefulWidget {
  const ProfileSelector({
    super.key,
    required this.profiles,
    required this.selectedProfile,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.trailing,
  });

  final List<HermesProfile> profiles;
  final String? selectedProfile;
  final ValueChanged<String>? onSelected;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  @override
  State<ProfileSelector> createState() => _ProfileSelectorState();
}

class _ProfileSelectorState extends State<ProfileSelector> {
  final _selected = GlobalKey();
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
                child: TextButton(
                  key: ValueKey('profile-${profile.name}'),
                  style:
                      TextButton.styleFrom(
                        minimumSize: const Size(48, 36),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        visualDensity: VisualDensity.standard,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        foregroundColor: profileAccent(context, profile.name),
                        backgroundColor: profileAccent(context, profile.name)
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
                            color: profileAccent(
                              context,
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
          if (widget.trailing != null) Center(child: widget.trailing!),
        ],
      ),
    ),
  );
}
