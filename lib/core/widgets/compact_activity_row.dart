import 'package:flutter/material.dart';

import '../theme/wing_theme.dart';
import 'activity_time.dart';
import 'anchored_expansion_tile.dart';

/// Text-sized tool/saved-agent headers. Spacing cannot be overridden by callers.
/// Detail content keeps its own layout; empty details produce a passive row.
class CompactActivityRow extends StatelessWidget {
  const CompactActivityRow({
    super.key,
    required this.icon,
    required this.lines,
    required this.time,
    this.details = const [],
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  final IconData icon;
  final List<Text> lines;
  final ActivityTime time;
  final List<Widget> details;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: WingTokens.of(context).muted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines,
          ),
        ),
        const SizedBox(width: 8),
        time,
      ],
    );
    if (details.isEmpty) return header;
    return IconTheme.merge(
      data: const IconThemeData(size: 16),
      child: ListTileTheme.merge(
        minVerticalPadding: 0,
        horizontalTitleGap: 8,
        child: AnchoredExpansionTile(
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onExpansionChanged,
          minTileHeight: 0,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          title: header,
          children: details,
        ),
      ),
    );
  }
}
