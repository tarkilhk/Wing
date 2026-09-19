import 'package:flutter/material.dart';

import '../models/hermes_profile.dart';
import '../theme/wing_theme.dart';

/// Desktop's name-derived profile hue (unsigned 32-bit UTF-16 hash).
/// Verified against Hermes 7c6f21a5e12ba9b1c674ec9b410fa6b8c45de4f8.
Color? desktopProfileColor(String name) {
  final key = name.trim();
  if (key.isEmpty || key == 'default') return null;
  final hash = key.codeUnits.fold<int>(
    0,
    (hash, unit) => (hash * 31 + unit) & 0xffffffff,
  );
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), .68, .58).toColor();
}

/// A bounded viewport: more profiles scroll inside, never widen the header.
class ChatProfileBar extends StatelessWidget {
  const ChatProfileBar({
    super.key,
    required this.profiles,
    required this.selectedProfiles,
    required this.onSelected,
  });

  final List<HermesProfile> profiles;
  final Set<String> selectedProfiles;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final ordered = [...profiles]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const ValueKey('chat-profile-scroll'),
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final profile in ordered)
                  Builder(
                    builder: (context) {
                      final selected = selectedProfiles.contains(profile.name);
                      final color =
                          desktopProfileColor(profile.name) ?? tokens.muted;
                      final hint = selected
                          ? 'Clear profile filter'
                          : 'Filter chats by ${profile.label}';
                      return Semantics(
                        button: true,
                        selected: selected,
                        label: profile.label,
                        hint: hint,
                        excludeSemantics: true,
                        onTap: () => onSelected(profile.name),
                        child: Tooltip(
                          message: '${profile.label} · $hint',
                          child: TextButton(
                            key: ValueKey('chat-profile-${profile.name}'),
                            style: TextButton.styleFrom(
                              fixedSize: const Size(24, 48),
                              minimumSize: const Size(24, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 14,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.standard,
                              shape: RoundedRectangleBorder(
                                borderRadius: WingRadius.control,
                              ),
                            ),
                            onPressed: () => onSelected(profile.name),
                            child: Opacity(
                              opacity: selected ? 1 : .55,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: color.withValues(
                                    alpha: selected ? .30 : .22,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Center(
                                  child: Text(
                                    profile.label.characters.first
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
