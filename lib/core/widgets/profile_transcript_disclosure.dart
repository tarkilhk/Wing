import 'package:flutter/material.dart';
import 'anchored_expansion_tile.dart';

/// Quiet metadata header for optional details between conversation messages.
class ProfileTranscriptDisclosure extends StatefulWidget {
  const ProfileTranscriptDisclosure({
    super.key,
    required this.label,
    required this.icon,
    required this.children,
    this.summary,
    this.initiallyExpanded = false,
    this.childrenPadding = EdgeInsets.zero,
  });

  final String label;
  final IconData icon;
  final Widget? summary;
  final List<Widget> children;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry childrenPadding;

  @override
  State<ProfileTranscriptDisclosure> createState() =>
      _ProfileTranscriptDisclosureState();
}

class _ProfileTranscriptDisclosureState
    extends State<ProfileTranscriptDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTileTheme.merge(
      minVerticalPadding: 0,
      horizontalTitleGap: 0,
      child: AnchoredExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        maintainState: true,
        minTileHeight: 28,
        tilePadding: EdgeInsets.zero,
        childrenPadding: widget.childrenPadding,
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        shape: const Border(),
        collapsedShape: const Border(),
        trailing: const SizedBox.shrink(),
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        title: DefaultTextStyle(
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: color,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(widget.label),
                    ?widget.summary,
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: color,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        children: widget.children,
      ),
    );
  }
}
