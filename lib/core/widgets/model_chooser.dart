import 'package:flutter/material.dart';

import '../theme/wing_theme.dart';
import 'studio_error.dart';
import 'studio_selection_tile.dart';

/// A model and its actual provider route. Display text never becomes identity.
class ModelChoice {
  final String provider;
  final String model;
  final String? providerLabel;
  final String? displayName;
  final String? detail;

  const ModelChoice({
    required this.provider,
    required this.model,
    this.providerLabel,
    this.displayName,
    this.detail,
  });

  String get routeLabel => providerLabel?.trim().isNotEmpty == true
      ? providerLabel!.trim()
      : provider;

  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName!.trim() : model;

  static List<ModelChoice> fromOptions(Map<String, dynamic> response) {
    final choices = <ModelChoice>[];
    final providers = response['providers'];
    if (providers is! List || providers.any((row) => row is! Map)) {
      throw const FormatException('Expected a list of records');
    }
    for (final row in providers) {
      final provider = Map<String, dynamic>.from(row as Map);
      final slug =
          (provider['slug'] ?? provider['id'])?.toString().trim() ?? '';
      final label =
          (provider['name'] ?? provider['display_name'] ?? provider['title'])
              ?.toString()
              .trim();
      final models = provider['models'];
      if (slug.isEmpty || models is! List) continue;
      for (final value in models) {
        final model = value is String
            ? value.trim()
            : value is Map
            ? (value['id'] ?? value['model'] ?? value['name'])
                      ?.toString()
                      .trim() ??
                  ''
            : '';
        if (model.isNotEmpty) {
          choices.add(
            ModelChoice(
              provider: slug,
              model: model,
              providerLabel: label?.isEmpty == true ? null : label,
            ),
          );
        }
      }
    }
    return choices;
  }
}

enum ModelSpecialChoice { automatic, profileDefault }

/// A typed selection. The two inherited choices cannot be mistaken for a route.
class ModelSelection {
  final ModelChoice? choice;
  final ModelSpecialChoice? special;

  const ModelSelection.model(ModelChoice this.choice) : special = null;
  const ModelSelection.special(ModelSpecialChoice this.special) : choice = null;

  @override
  bool operator ==(Object other) =>
      other is ModelSelection &&
      special == other.special &&
      choice?.provider == other.choice?.provider &&
      choice?.model == other.choice?.model;

  @override
  int get hashCode => Object.hash(special, choice?.provider, choice?.model);
}

class ModelSpecialOption {
  final ModelSpecialChoice value;
  final String title;
  final String? description;

  const ModelSpecialOption(this.value, this.title, {this.description});
}

/// Browsing and draft selection only. The enclosing editor owns persistence.
class ModelChooser extends StatefulWidget {
  final List<ModelChoice> choices;
  final ModelSelection? selected;
  final ValueChanged<ModelSelection> onSelected;
  final Future<List<ModelChoice>> Function()? onRefresh;
  final ValueChanged<List<ModelChoice>>? onChoicesChanged;
  final List<ModelSpecialOption> specialOptions;
  final String scopeLabel;
  final String keyPrefix;
  final Key? refreshKey;
  final bool groupByProvider;
  final bool enabled;
  final VoidCallback? onReviewProviderAccess;

  const ModelChooser({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
    required this.scopeLabel,
    this.onRefresh,
    this.onChoicesChanged,
    this.specialOptions = const [],
    this.keyPrefix = 'model',
    this.refreshKey,
    this.groupByProvider = true,
    this.enabled = true,
    this.onReviewProviderAccess,
  });

  @override
  State<ModelChooser> createState() => _ModelChooserState();
}

class _ModelChooserState extends State<ModelChooser> {
  late List<ModelChoice> _choices;
  final _search = TextEditingController();
  final _selectedAnchor = GlobalKey();
  final _expanded = <String>{};
  String _query = '';
  String? _refreshError;
  bool _refreshing = false;
  bool _refreshed = false;
  bool _catalogChanged = false;

  @override
  void initState() {
    super.initState();
    _choices = widget.choices;
    final provider = widget.selected?.choice?.provider;
    if (provider != null) _expanded.add(provider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedAnchor.currentContext;
      if (mounted && context != null) {
        Scrollable.ensureVisible(context, alignment: 0.25);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final reload = widget.onRefresh;
    if (reload == null || _refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final choices = await reload();
      if (!mounted) return;
      setState(() {
        final before = _choices
            .map((choice) => (choice.provider, choice.model))
            .toSet();
        final after = choices
            .map((choice) => (choice.provider, choice.model))
            .toSet();
        _catalogChanged =
            before.length != after.length || !before.containsAll(after);
        _choices = choices;
        _refreshed = true;
      });
      widget.onChoicesChanged?.call(choices);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshError = 'Refresh failed. Previous list shown.';
        _refreshed = true;
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  bool _matches(ModelChoice choice, String query) =>
      choice.model.toLowerCase().contains(query) ||
      choice.provider.toLowerCase().contains(query) ||
      choice.routeLabel.toLowerCase().contains(query) ||
      choice.label.toLowerCase().contains(query);

  Widget _choice(ModelChoice choice, {bool missing = false}) {
    final selected = widget.selected == ModelSelection.model(choice);
    final description = <String>[
      if (choice.label != choice.model) choice.model,
      if (choice.detail?.isNotEmpty == true) choice.detail!,
      if (missing) 'Not in the current model list; availability unconfirmed',
    ];
    final tile = StudioRadioTile<ModelSelection>(
      key: Key('${widget.keyPrefix}-${choice.provider}-${choice.model}'),
      value: ModelSelection.model(choice),
      enabled: widget.enabled,
      title: Text(choice.label),
      subtitle: description.isEmpty ? null : Text(description.join(' · ')),
    );
    return selected ? KeyedSubtree(key: _selectedAnchor, child: tile) : tile;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final query = _query.trim().toLowerCase();
    final filtered = _choices
        .where((choice) => _matches(choice, query))
        .toList();
    final groups = <String, List<ModelChoice>>{};
    for (final choice in filtered) {
      groups.putIfAbsent(choice.provider, () => []).add(choice);
    }
    final missingChoice = widget.selected?.choice;
    final missing =
        missingChoice != null &&
        !_choices.any(
          (choice) =>
              choice.provider == missingChoice.provider &&
              choice.model == missingChoice.model,
        );
    final specials = widget.specialOptions.where(
      (option) =>
          query.isEmpty ||
          option.title.toLowerCase().contains(query) ||
          (option.description?.toLowerCase().contains(query) ?? false),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WingSpacing.lg,
            WingSpacing.xs,
            WingSpacing.lg,
            WingSpacing.sm,
          ),
          child: TextField(
            key: Key('${widget.keyPrefix}-search'),
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search models',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear model search',
                      onPressed: () {
                        _search.clear();
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: const OutlineInputBorder(
                borderRadius: WingRadius.control,
              ),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WingSpacing.lg,
            0,
            WingSpacing.lg,
            WingSpacing.xs,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final refreshKey =
                  widget.refreshKey ?? Key('refresh-${widget.keyPrefix}s');
              final refreshIcon = _refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18);
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.scopeLabel,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ),
                  if (widget.onRefresh != null)
                    compact
                        ? IconButton(
                            key: refreshKey,
                            tooltip: 'Refresh models',
                            onPressed: widget.enabled && !_refreshing
                                ? _refresh
                                : null,
                            icon: refreshIcon,
                          )
                        : TextButton.icon(
                            key: refreshKey,
                            onPressed: widget.enabled && !_refreshing
                                ? _refresh
                                : null,
                            icon: refreshIcon,
                            label: Text(
                              _refreshing ? 'Refreshing…' : 'Refresh models',
                            ),
                          ),
                ],
              );
            },
          ),
        ),
        if (_refreshError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WingSpacing.lg),
            child: StudioError(_refreshError!),
          )
        else if (_refreshed)
          Semantics(
            liveRegion: true,
            child: Text(
              _choices.isEmpty
                  ? 'No models returned for this profile.'
                  : _catalogChanged
                  ? 'Models updated. Still missing a model?'
                  : 'List refreshed. Still missing a model?',
              style: tokens.typography.label.copyWith(color: tokens.muted),
            ),
          ),
        if (_refreshed && widget.onReviewProviderAccess != null)
          TextButton(
            key: const Key('review-model-provider-access'),
            onPressed: widget.onReviewProviderAccess,
            child: const Text('Review provider access'),
          ),
        Expanded(
          child: RadioGroup<ModelSelection>(
            groupValue: widget.selected,
            onChanged: widget.enabled
                ? (value) {
                    if (value != null) widget.onSelected(value);
                  }
                : (_) {},
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                WingSpacing.sm,
                0,
                WingSpacing.sm,
                WingSpacing.md,
              ),
              children: [
                for (final option in specials)
                  StudioRadioTile<ModelSelection>(
                    key: Key('${widget.keyPrefix}-${option.value.name}'),
                    value: ModelSelection.special(option.value),
                    enabled: widget.enabled,
                    title: Text(option.title),
                    subtitle: option.description == null
                        ? null
                        : Text(option.description!),
                  ),
                if (missingChoice != null &&
                    missing &&
                    (query.isEmpty || _matches(missingChoice, query)))
                  _choice(missingChoice, missing: true),
                if (widget.groupByProvider)
                  for (final entry in groups.entries)
                    ExpansionTile(
                      key: Key(
                        '${widget.keyPrefix}-provider-${entry.key}${query.isEmpty ? '' : '-search-$query'}',
                      ),
                      initiallyExpanded:
                          query.isNotEmpty ||
                          _expanded.contains(entry.key) ||
                          entry.key == widget.selected?.choice?.provider,
                      onExpansionChanged: query.isNotEmpty
                          ? null
                          : (open) => open
                                ? _expanded.add(entry.key)
                                : _expanded.remove(entry.key),
                      title: Text(entry.value.first.routeLabel),
                      subtitle: Text(entry.key),
                      children: [
                        for (final choice in entry.value) _choice(choice),
                      ],
                    )
                else
                  for (final choice in filtered) _choice(choice),
                if (filtered.isEmpty &&
                    specials.isEmpty &&
                    !(missingChoice != null &&
                        missing &&
                        (query.isEmpty || _matches(missingChoice, query))))
                  Padding(
                    padding: const EdgeInsets.all(WingSpacing.lg),
                    child: Text(
                      query.isEmpty
                          ? 'No models available for this profile'
                          : 'No matching models',
                      style: tokens.typography.body.copyWith(
                        color: tokens.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
