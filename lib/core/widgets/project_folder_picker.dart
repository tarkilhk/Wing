import 'package:wing/core/theme/wing_theme.dart';
import 'studio_error.dart';
import 'package:flutter/material.dart';

import '../models/chat_list_view.dart';

class ProjectFolderPickerDialog extends StatefulWidget {
  final Future<List<ProjectFolderSuggestion>> Function() discover;

  const ProjectFolderPickerDialog({super.key, required this.discover});

  @override
  State<ProjectFolderPickerDialog> createState() =>
      _ProjectFolderPickerDialogState();
}

class _ProjectFolderPickerDialogState extends State<ProjectFolderPickerDialog> {
  final _path = TextEditingController();
  List<ProjectFolderSuggestion>? _suggestions;
  bool _loading = false;
  bool _hasPath = false;
  bool _failed = false;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _findFolders() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final suggestions = await widget.discover();
      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _suggestions = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(ProjectFolderSuggestion suggestion) {
    _path.text = suggestion.path;
    _path.selection = TextSelection.collapsed(offset: _path.text.length);
    setState(() => _hasPath = true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Project folder on Hermes host'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('project-folder-path'),
            controller: _path,
            onChanged: (value) =>
                setState(() => _hasPath = value.trim().isNotEmpty),
            decoration: const InputDecoration(labelText: 'Absolute path'),
          ),
          const SizedBox(height: 12),
          StudioButtonPress(
            child: IconButton.outlined(
              key: const ValueKey('project-folder-find'),
              tooltip: 'Find folders',
              onPressed: _loading ? null : _findFolders,
              icon: _loading
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        value: MediaQuery.disableAnimationsOf(context)
                            ? 0.75
                            : null,
                        strokeWidth: 2,
                        semanticsLabel: 'Finding project folders',
                      ),
                    )
                  : const Icon(Icons.search),
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            const StudioError(
              'Folders could not be loaded. Enter an absolute path instead.',
            ),
          ] else if (_suggestions case final suggestions?) ...[
            const SizedBox(height: 8),
            if (suggestions.isEmpty)
              const Text(
                'No repository folders found. Enter an absolute path instead.',
              )
            else
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = suggestions[index];
                    return StudioButtonPress(
                      child: ListTile(
                        key: ValueKey('project-folder-${suggestion.path}'),
                        title: Text(suggestion.label),
                        subtitle: Text(suggestion.path),
                        onTap: () => _select(suggestion),
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    ),
    actions: [
      StudioButtonPress(
        child: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      StudioButtonPress(
        child: IconButton.filled(
          key: const ValueKey('project-folder-continue'),
          tooltip: 'Use folder',
          onPressed: _hasPath
              ? () => Navigator.pop(context, _path.text.trim())
              : null,
          icon: const Icon(Icons.check),
        ),
      ),
    ],
  );
}
