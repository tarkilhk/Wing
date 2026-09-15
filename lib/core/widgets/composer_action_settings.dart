import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/composer_action.dart';
import '../services/device_preference.dart';
import 'composer_action_button.dart';
import 'studio_error.dart';

class ComposerActionSettings extends StatefulWidget {
  const ComposerActionSettings({super.key, required this.preferences});
  final SharedPreferences preferences;

  @override
  State<ComposerActionSettings> createState() => _ComposerActionSettingsState();
}

class _ComposerActionSettingsState extends State<ComposerActionSettings> {
  bool _saving = false;
  late ComposerAction _selected;

  @override
  void initState() {
    super.initState();
    _selected = ComposerAction.fromPreference(
      widget.preferences.getString(ComposerAction.preferenceKey),
    );
  }

  Future<void> _save(ComposerAction action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await saveDevicePreference(
        widget.preferences,
        ComposerAction.preferenceKey,
        action.name,
      );
      if (mounted) setState(() => _selected = action);
    } catch (_) {
      if (mounted) {
        showStudioError(
          context,
          'Could not save the default action. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default action while working',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'For this device. Hold the chat button and slide to choose another action. Idle chats use Send.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in ComposerAction.runningDefaults)
                  ChoiceChip(
                    avatar: Icon(composerActionIcon(action), size: 18),
                    label: Text(action.label),
                    selected: action == _selected,
                    onSelected: _saving ? null : (_) => _save(action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
