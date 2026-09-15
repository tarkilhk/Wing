import '../theme/wing_theme.dart';
import 'studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/slash_command.dart';
import '../services/profile_workspace_controller.dart';

/// Keyed by chat owner in the screen: late replies cannot paint another profile.
class SlashCommandSuggestions extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final ProfileChat chat;
  final TextEditingController composer;
  const SlashCommandSuggestions({
    super.key,
    required this.controller,
    required this.chat,
    required this.composer,
  });

  @override
  State<SlashCommandSuggestions> createState() =>
      _SlashCommandSuggestionsState();
}

class _SlashCommandSuggestionsState extends State<SlashCommandSuggestions> {
  Timer? _timer;
  int _generation = 0;
  List<SlashCommand> _items = [];
  String? _error;
  String _warning = '';
  bool _loading = false;
  String _query = '';
  int _replaceFrom = 0;

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
      _items = [];
      _error = null;
      _loading = query.startsWith('/');
    });
    if (!_loading) return;
    _timer = Timer(
      const Duration(milliseconds: 180),
      () => _load(query, generation),
    );
  }

  Future<void> _load(String query, int generation) async {
    try {
      final catalog = await widget.controller.commandCatalog(widget.chat);
      List<SlashCommand> items;
      var replaceFrom = 0;
      if (!query.contains(RegExp(r'\s'))) {
        items = catalog.search(query);
      } else {
        final result = await widget.controller.completeCommand(
          widget.chat,
          query,
        );
        items = (result['items'] as List)
            .map(
              (row) => SlashCommand(
                row['text'] as String,
                row['meta'] as String? ?? '',
                '',
              ),
            )
            .toList();
        // Hermes offsets count Unicode code points, Dart selections count UTF-16.
        final offset = result['replace_from'] as int;
        replaceFrom = String.fromCharCodes(query.runes.take(offset)).length;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = items;
        _replaceFrom = replaceFrom;
        _warning = catalog.warning;
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

  void _select(SlashCommand item) {
    final value = widget.composer.value;
    final end = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final suffix = value.text.substring(end);
    final insert = '${item.text}${suffix.startsWith(' ') ? '' : ' '}';
    final text = value.text.replaceRange(_replaceFrom, end, insert);
    widget.chat.draft = text;
    widget.composer.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: _replaceFrom + insert.length),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.composer.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_query.startsWith('/')) return const SizedBox.shrink();
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
            if (_warning.isNotEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(_warning)),
            if (!_loading &&
                _error == null &&
                _items.isEmpty &&
                !_query.contains(' '))
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No matching commands. You can still send a command by name.',
                ),
              ),
            for (final item in _items)
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
                onTap: () => _select(item),
              ),
          ],
        ),
      ),
    );
  }
}
