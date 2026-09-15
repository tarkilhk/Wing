import 'package:flutter/material.dart';

/// Keeps an action's caption and measured size unchanged while work is pending.
class StudioActionLabel extends StatelessWidget {
  const StudioActionLabel(this.label, {required this.busy, super.key});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    label: busy ? '$label, in progress' : label,
    liveRegion: busy,
    child: ExcludeSemantics(
      child: Stack(
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
