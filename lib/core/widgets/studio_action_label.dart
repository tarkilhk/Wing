import 'package:flutter/material.dart';

import '../theme/wing_theme.dart';

/// Keeps an action's caption and measured size unchanged while work is pending.
class StudioActionLabel extends StatelessWidget {
  const StudioActionLabel(this.label, {required this.busy, super.key})
    : _leadingIcon = null;

  /// A left-aligned row caption whose icon reserves the pending indicator space.
  const StudioActionLabel.row(
    this.label, {
    required this.busy,
    required IconData icon,
    super.key,
  }) : _leadingIcon = icon;

  final String label;
  final bool busy;
  final IconData? _leadingIcon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: busy ? '$label, in progress' : label,
    liveRegion: busy,
    child: ExcludeSemantics(
      child: _leadingIcon != null
          ? Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_leadingIcon, size: 20),
                ),
                const SizedBox(width: WingSpacing.md),
                Expanded(child: Text(label)),
              ],
            )
          : Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(label, textAlign: TextAlign.center),
                ),
                if (busy)
                  const Positioned(
                    left: 0,
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
    ),
  );
}
