import 'package:flutter/material.dart';

import '../models/app_preferences.dart';
import '../services/app_preferences.dart';
import '../theme/app_preferences_rendering.dart';
import 'studio_selection_tile.dart';
import 'studio_error.dart';

class TextSizeSettingsCard extends StatelessWidget {
  const TextSizeSettingsCard({required this.preferences, super.key});
  final AppPreferences preferences;

  Future<void> _showPicker(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => ValueListenableBuilder<AppPreferencesState>(
      valueListenable: preferences.state,
      builder: (context, state, _) {
        final control = state.textSize;
        return PopScope(
          canPop: !control.busy,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Text size',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Follows your Android text size.'),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Text size preview',
                    child: ExcludeSemantics(
                      child: Text('A little easier to read.'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  RadioGroup<AppTextSizePreference>(
                    groupValue: control.selected,
                    onChanged: (value) async {
                      final choose = control.choose;
                      if (value == null || choose == null) return;
                      final saved = await choose(value);
                      if (saved && sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    child: Column(
                      children: [
                        for (final preference in AppTextSizePreference.values)
                          StudioRadioTile<AppTextSizePreference>(
                            contentPadding: EdgeInsets.zero,
                            minTileHeight: 48,
                            minVerticalPadding: 8,
                            enabled: control.choose != null,
                            value: preference,
                            title: Text(preference.label),
                            subtitle: Text(preference.description),
                          ),
                      ],
                    ),
                  ),
                  if (control.notice != null) StudioError(control.notice!),
                  if (control.error != null) StudioError(control.error!),
                  if (control.busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AppPreferencesState>(
    valueListenable: preferences.state,
    builder: (context, state, _) => Semantics(
      label: 'Text size: ${state.textSize.selected?.label ?? 'Choose a value'}',
      button: true,
      onTap: () => _showPicker(context),
      child: ExcludeSemantics(
        child: ListTile(
          leading: const Icon(Icons.format_size),
          title: const Text('Text size'),
          subtitle: Text(
            state.textSize.selected?.label ??
                'Choose a value to repair the saved setting',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showPicker(context),
        ),
      ),
    ),
  );
}
