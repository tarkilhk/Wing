import '../theme/wing_theme.dart';
import 'studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/slash_command.dart';

/// Skill emphasis is a text projection: selection, copy and IME stay native.
class SkillComposerController extends TextEditingController {
  SkillComposerController({super.text});
  SkillComposerController.fromValue(super.value) : super.fromValue();

  final _skills = <String>{};
  Object? _scope;

  void setScope(Object? scope) {
    if (_scope == scope) return;
    _scope = scope;
    _skills.clear();
  }

  void observeCommands(Iterable<SlashCommand> commands) {
    final previous = _skills.length;
    _skills.addAll(commands.where((c) => c.isSkill).map((c) => c.text));
    if (_skills.length != previous) notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final skills = SlashSkillReference.inText(text, _skills).toList();
    final composing =
        withComposing &&
            value.isComposingRangeValid &&
            !value.composing.isCollapsed
        ? value.composing
        : TextRange.empty;
    final boundaries = <int>{
      0,
      text.length,
      for (final skill in skills) ...[skill.start, skill.end],
      if (composing.isValid) ...[composing.start, composing.end],
    }.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < boundaries.length - 1; i++)
          TextSpan(
            text: text.substring(boundaries[i], boundaries[i + 1]),
            style: TextStyle(
              color:
                  skills.any(
                    (s) =>
                        s.start <= boundaries[i] && s.end >= boundaries[i + 1],
                  )
                  ? Theme.of(context).colorScheme.primary
                  : null,
              fontWeight:
                  skills.any(
                    (s) =>
                        s.start <= boundaries[i] && s.end >= boundaries[i + 1],
                  )
                  ? FontWeight.w700
                  : null,
              decoration:
                  composing.isValid &&
                      composing.start <= boundaries[i] &&
                      composing.end >= boundaries[i + 1]
                  ? TextDecoration.underline
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Keyed by chat owner in the screen: late replies cannot paint another profile.
class SlashCommandSuggestions extends StatefulWidget {
  final Future<SlashCompletion> Function(String query) loadCompletion;
  final Future<void> Function() refreshCommands;
  final Future<void> Function(String text) saveDraft;
  final Future<void> Function(SlashCommand skill) inspectSkill;
  final SkillComposerController composer;
  const SlashCommandSuggestions({
    super.key,
    required this.loadCompletion,
    required this.refreshCommands,
    required this.saveDraft,
    required this.inspectSkill,
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
  bool _refreshing = false;
  String _query = '';
  SlashCommand? _inspecting;

  @override
  void initState() {
    super.initState();
    widget.composer.addListener(_changed);
    _changed();
    unawaited(_observeCatalog());
  }

  Future<void> _observeCatalog() async {
    try {
      final catalog = await widget.loadCompletion('/');
      if (mounted) widget.composer.observeCommands(catalog.items);
    } catch (_) {
      // Catalog errors appear through the active picker with its retry action.
    }
  }

  void _changed() {
    final value = widget.composer.value;
    final end = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final query = value.selection.isValid && !value.selection.isCollapsed
        ? ''
        : value.text.substring(0, end);
    if (query == _query) return;
    _query = query;
    final generation = ++_generation;
    _timer?.cancel();
    setState(() {
      _error = null;
      _loading = SlashCompletion.isQuery(query);
    });
    if (!_loading || _refreshing) return;
    _timer = Timer(
      const Duration(milliseconds: 180),
      () => _load(query, generation),
    );
  }

  Future<void> _load(String query, int generation) async {
    try {
      final completion = await widget.loadCompletion(query);
      if (!mounted || generation != _generation) return;
      widget.composer.observeCommands(completion.items);
      setState(() {
        _completion = completion;
        _completionGeneration = generation;
        _loading = false;
      });
      _reveal(generation);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Could not load commands.';
      });
      _reveal(generation);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    var refreshed = false;
    _timer?.cancel();
    ++_generation;
    setState(() {
      _refreshing = true;
      _loading = true;
      _error = null;
    });
    try {
      await widget.refreshCommands();
      if (!mounted) return;
      final catalog = await widget.loadCompletion('/');
      if (!mounted) return;
      widget.composer.observeCommands(catalog.items);
      refreshed = true;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not refresh skills.';
      });
      _reveal(_generation);
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          if (refreshed) _loading = SlashCompletion.isQuery(_query);
        });
        if (refreshed && _loading) {
          unawaited(_load(_query, ++_generation));
        }
      }
    }
  }

  void _reveal(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      // Long drafts can put the helper above the composer's visible viewport
      // while the Android keyboard is open. Reveal it without moving focus.
      unawaited(Scrollable.ensureVisible(context, alignment: 0));
    });
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

  Future<void> _inspect(SlashCommand item) async {
    if (_inspecting != null) return;
    setState(() => _inspecting = item);
    try {
      await widget.inspectSkill(item);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: StudioError(
            'Could not read this skill. Check the connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _inspecting = null);
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
    final header = Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _error != null
                ? StudioError(_error!)
                : Text(
                    !_loading && completion?.showsNoMatches == true
                        ? 'No matching commands.'
                        : 'Commands',
                  ),
          ),
        ),
        TextFieldTapRegion(
          child: IconButton(
            tooltip: 'Refresh skills',
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
        ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Material(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: WingRadius.card,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Flexible(child: SingleChildScrollView(child: header))
            else
              header,
            if (_error == null)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (completion?.warning.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(completion!.warning),
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
                          trailing: item.isSkill
                              ? IconButton(
                                  tooltip: 'Inspect ${item.text}',
                                  constraints: const BoxConstraints.tightFor(
                                    width: 48,
                                    height: 48,
                                  ),
                                  onPressed: _inspecting == null
                                      ? () => _inspect(item)
                                      : null,
                                  icon: identical(_inspecting, item)
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.visibility_outlined,
                                          size: 20,
                                        ),
                                )
                              : item.category.isEmpty
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
          ],
        ),
      ),
    );
  }
}
