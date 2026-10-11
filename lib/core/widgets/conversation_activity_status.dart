import 'package:flutter/material.dart';
import 'activity_shimmer.dart';
import 'status_transition.dart';

/// Shared chat status presentation; each conversation supplies its own facts.
class ConversationActivityStatus extends StatelessWidget {
  const ConversationActivityStatus({
    super.key,
    required this.label,
    required this.leading,
    required this.active,
    required this.wrap,
  });
  final String? label;
  final Widget leading;
  final bool active, wrap;
  @override
  Widget build(BuildContext context) {
    final text = label;
    return StatusTransition(
      child: text == null
          ? null
          : Semantics(
              container: true,
              liveRegion: true,
              label: text,
              child: ExcludeSemantics(
                child: Tooltip(
                  message: text,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        leading,
                        const SizedBox(width: 8),
                        Expanded(
                          child: ActivityShimmer(
                            active: active,
                            child: Text(
                              text,
                              maxLines: wrap ? null : 1,
                              overflow: wrap
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The normal chat glyph, including Wing's reduced-motion presentation.
class ConversationStatusIndicator extends StatelessWidget {
  const ConversationStatusIndicator({
    super.key,
    required this.running,
    required this.icon,
    required this.color,
  });
  final bool running;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: running && !MediaQuery.disableAnimationsOf(context)
        ? CircularProgressIndicator(strokeWidth: 2, color: color)
        : Icon(icon, size: 18, color: color),
  );
}
