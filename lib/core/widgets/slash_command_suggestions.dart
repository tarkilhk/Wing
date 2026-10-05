import '../theme/wing_theme.dart';
import 'studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/slash_command.dart';

/// Keyed by chat owner in the screen: late replies cannot paint another profile.
class SlashCommandSuggestions extends StatefulWidget {
  final Future<SlashCompletion> Function(String query) loadCompletion;
  final Future<void> Function(String text) saveDraft;
  final TextEditingController composer;
  const SlashCommandSuggestions({
    super.key,
    required this.loadCompletion,
    required this.saveDraft,
    required this.composer,
  });

  @override
  State<SlashCommandSuggestions> createState() =>
      _SlashCommandSuggestionsState();
}

class _SlashCommandSuggestionsState extends State<SlashCommandSuggestions> {
  Timer? _timer;
  int _generation = 0;
  SlashCompletion? _completion;
  int _completionGeneration = -1;
  String? _error;
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.composer.addListener(_changed);
    _changed();
  }

  void _changed() {
    final value = widget.composer.value;
    final end = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final query = value.text.substring(0, end);
    if (query == _query) return;
    _query = query;
    final generation = ++_generation;
    _timer?.cancel();
    setState(() {
      _error = null;
      _loading = SlashCompletion.isQuery(query);
    });
    if (!_loading) return;
    _timer = Timer(
      const Duration(milliseconds: 180),
      () => _load(query, generation),
    );
  }

  Future<void> _load(String query, int generation) async {
    try {
      final completion = await widget.loadCompletion(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _completion = completion;
        _completionGeneration = generation;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Could not load commands. Tap to retry.';
      });
    }
  }

  Future<void> _select(SlashCompletion completion, SlashCommand item) async {
    final value = widget.composer.value;
    final end = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final edit = completion.select(item, text: value.text, cursor: end);
    if (edit == null) return;
    widget.composer.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.cursor),
    );
    try {
      await widget.saveDraft(edit.text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not save the draft. Your text is kept.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.composer.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SlashCompletion.isQuery(_query)) return const SizedBox.shrink();
    final completion =
        _completionGeneration == _generation && _completion?.query == _query
        ? _completion
        : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Material(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: WingRadius.card,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              TextButton(
                onPressed: () => _load(_query, ++_generation),
                child: StudioError(_error!),
              ),
            if (_completion?.warning.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_completion!.warning),
              ),
            if (!_loading &&
                _error == null &&
                completion?.showsNoMatches == true)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No matching commands. You can still send a command by name.',
                ),
              ),
            if (completion != null && !_loading)
              for (final item in completion.items)
                ListTile(
                  dense: true,
                  title: Text(item.text),
                  subtitle: Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: item.category.isEmpty
                      ? null
                      : Text(
                          item.category,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                  onTap: () => _select(completion, item),
                ),
          ],
        ),
      ),
    );
  }
}
