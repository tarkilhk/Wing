import 'package:flutter/material.dart';

import '../models/hermes_profile.dart';
import '../theme/profile_workspace_theme.dart';
import '../theme/wing_theme.dart';

/// The same direct profile choices in Chats and Administration.
class ProfileSelector extends StatelessWidget {
  const ProfileSelector({
    super.key,
    required this.profiles,
    required this.selectedProfile,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<HermesProfile> profiles;
  final String? selectedProfile;
  final ValueChanged<String>? onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('profile-selector'),
    height: 48 + (MediaQuery.textScalerOf(context).scale(14) - 14),
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      children: [
        for (final profile in profiles)
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
                            alpha: selectedProfile == profile.name
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
                onPressed: onSelected == null
                    ? null
                    : () => onSelected!(profile.name),
                child: Semantics(
                  selected: selectedProfile == profile.name,
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
      ],
    ),
  );
}
