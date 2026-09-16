import 'package:flutter/material.dart';

/// A select-only field whose popup consumes Studio's shared menu theme.
class StudioSelect<T> extends StatelessWidget {
  const StudioSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T? value;
  final List<({T value, String label})> options;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownMenu<T>(
    initialSelection: value,
    maxLines: null,
    label: Text(label),
    enabled: onChanged != null,
    selectOnly: true,
    requestFocusOnTap: true,
    expandedInsets: EdgeInsets.zero,
    onSelected: onChanged,
    dropdownMenuEntries: [
      for (final option in options)
        DropdownMenuEntry(
          value: option.value,
          label: option.label,
          labelWidget: Text(option.label),
          style: ButtonStyle(
            backgroundColor: option.value == value
                ? WidgetStatePropertyAll(
                    Theme.of(context).colorScheme.primaryContainer,
                  )
                : null,
          ),
        ),
    ],
  );
}
