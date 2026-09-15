import 'package:flutter/material.dart';

/// A failure is identifiable by its icon, text and semantic color in any theme.
class StudioError extends StatelessWidget {
  const StudioError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.error_outline, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

void showStudioError(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: StudioError(message)));
}
