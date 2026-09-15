import 'package:flutter/material.dart';

/// Read-only Markdown task state, expressed with a filled background.
class StudioTaskMarker extends StatelessWidget {
  const StudioTaskMarker({required this.completed, super.key});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      checked: completed,
      label: completed ? 'Completed task' : 'Incomplete task',
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: completed ? colors.primaryContainer : Colors.transparent,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
