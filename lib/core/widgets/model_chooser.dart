import 'package:flutter/material.dart';
import '../models/model_choice.dart';
import '../presentation/chat_model_labels.dart';
import '../theme/wing_theme.dart';
import 'model_card.dart';
import 'studio_error.dart';
import 'studio_selection_tile.dart';

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
  final bool promoteSelected;
  final String? selectedStatus;
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
    this.promoteSelected = false,
    this.selectedStatus,
    this.enabled = true,
    this.onReviewProviderAccess,
  });
  @override
  State<ModelChooser> createState() => _ModelChooserState();
}

class _ModelChooserState extends State<ModelChooser> {
  late List<ModelChoice> _choices;
  final _search = TextEditingController();
  String _query = '';
  String? _provider;
  String? _refreshError;
  bool _refreshing = false;
  bool _refreshed = false;
  @override
  void initState() {
    super.initState();
    _choices = widget.choices;
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
        _choices = choices;
        _refreshed = true;
        if (!_choices.any((c) => c.provider == _provider)) _provider = null;
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

  bool _matches(ModelChoice c, String q) =>
      c.model.toLowerCase().contains(q) ||
      c.provider.toLowerCase().contains(q) ||
      c.routeLabel.toLowerCase().contains(q) ||
      c.label.toLowerCase().contains(q);

  Widget _choice(
    ModelChoice choice, {
    bool missing = false,
    bool showInput = false,
    bool showOutput = false,
  }) {
    final tokens = WingTokens.of(context);
    final selected = widget.selected == ModelSelection.model(choice);
    final enlarged = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final prices = choice.prices;
    final input = prices?.free == true ? 'Free' : prices?.input;
    final output = prices?.free == true ? 'Free' : prices?.output;
    final label = catalogModelLabel(choice.label);
    return Material(
      color: selected
          ? tokens.accent.withValues(alpha: .12)
          : Colors.transparent,
      borderRadius: WingRadius.control,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              selected: selected,
              inMutuallyExclusiveGroup: true,
              label: '${choice.label}, ${choice.routeLabel}',
              child: InkWell(
                key: Key(
                  '${widget.keyPrefix}-${choice.provider}-${choice.model}',
                ),
                borderRadius: WingRadius.control,
                onTap: widget.enabled
                    ? () => widget.onSelected(ModelSelection.model(choice))
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Icon(
                            selected
                                ? Icons.check_rounded
                                : Icons.circle_outlined,
                            size: selected ? 16 : 10,
                            color: selected ? tokens.accent : tokens.border,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: tokens.typography.body.copyWith(
                                  fontSize: 14,
                                  color: selected
                                      ? tokens.accent
                                      : tokens.onSurface,
                                ),
                              ),
                              if (selected && widget.selectedStatus != null)
                                Text(
                                  widget.selectedStatus!,
                                  style: tokens.typography.label.copyWith(
                                    color: tokens.accent,
                                  ),
                                ),
                              if (missing)
                                Text(
                                  'Not in the current model list; availability unconfirmed',
                                  style: tokens.typography.label.copyWith(
                                    color: tokens.muted,
                                  ),
                                ),
                              if (choice.detail?.isNotEmpty == true)
                                Text(
                                  choice.detail!,
                                  style: tokens.typography.label.copyWith(
                                    color: tokens.muted,
                                  ),
                                ),
                              if (enlarged && (input != null || output != null))
                                Text(
                                  [
                                    if (input != null) 'In $input',
                                    if (output != null) 'Out $output',
                                  ].join(' · '),
                                  style: tokens.typography.label.copyWith(
                                    color: tokens.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!enlarged) ...[
                          for (final price in [
                            if (showInput) input,
                            if (showOutput) output,
                          ])
                            SizedBox(
                              width: 48,
                              child: Text(
                                price ?? '',
                                textAlign: TextAlign.right,
                                style: tokens.typography.label.copyWith(
                                  color: tokens.muted,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: Key('info-${choice.provider}-${choice.model}'),
            tooltip: 'About ${choice.label}',
            onPressed: widget.enabled
                ? () => showModelCard(context, choice)
                : null,
            icon: Icon(
              Icons.info_outline_rounded,
              size: 17,
              color: tokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final query = _query.trim().toLowerCase();
    final providers = <String, String>{
      for (final choice in _choices) choice.provider: choice.routeLabel,
    };
    final filtered = _choices
        .where(
          (c) =>
              (_provider == null || c.provider == _provider) &&
              _matches(c, query),
        )
        .toList();
    final selected = widget.selected?.choice;
    if (widget.promoteSelected && selected != null) {
      final index = filtered.indexWhere(
        (c) => c.provider == selected.provider && c.model == selected.model,
      );
      if (index > 0) filtered.insert(0, filtered.removeAt(index));
    }
    final groups = <String, List<ModelChoice>>{};
    for (final choice in filtered) {
      groups.putIfAbsent(choice.provider, () => []).add(choice);
    }
    final missing =
        selected != null &&
        !_choices.any(
          (c) => c.provider == selected.provider && c.model == selected.model,
        );
    final showMissing =
        missing &&
        (_provider == null || _provider == selected.provider) &&
        _matches(selected, query);
    final specials = widget.specialOptions
        .where(
          (o) =>
              query.isEmpty ||
              o.title.toLowerCase().contains(query) ||
              (o.description?.toLowerCase().contains(query) ?? false),
        )
        .toList();
    final enlarged = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      label: widget.scopeLabel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key('${widget.keyPrefix}-search'),
                    enabled: widget.enabled,
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search models or providers',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear model search',
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    key:
                        widget.refreshKey ??
                        Key('refresh-${widget.keyPrefix}s'),
                    tooltip: 'Refresh models',
                    onPressed: widget.enabled && !_refreshing ? _refresh : null,
                    icon: _refreshing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
          ),
          if (widget.groupByProvider && providers.length > 1)
            SizedBox(
              height: mathFilterHeight(context),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final entry in [
                    const MapEntry<String?, String>(null, 'All'),
                    ...providers.entries,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          foregroundColor: _provider == entry.key
                              ? tokens.accent
                              : tokens.muted,
                          backgroundColor: _provider == entry.key
                              ? tokens.accent.withValues(alpha: .12)
                              : Colors.transparent,
                          textStyle: tokens.typography.label,
                        ),
                        onPressed: widget.enabled
                            ? () => setState(() => _provider = entry.key)
                            : null,
                        child: Text(entry.value),
                      ),
                    ),
                ],
              ),
            ),
          if (_refreshError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StudioError(_refreshError!),
            ),
          if (_refreshed && widget.onReviewProviderAccess != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('review-model-provider-access'),
                onPressed: widget.enabled
                    ? widget.onReviewProviderAccess
                    : null,
                child: const Text('Review provider access'),
              ),
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
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                  if (showMissing) _choice(selected, missing: true),
                  if (widget.groupByProvider)
                    for (final entry in groups.entries) ...[
                      Padding(
                        key: Key('${widget.keyPrefix}-provider-${entry.key}'),
                        padding: const EdgeInsets.only(
                          left: 8,
                          top: 8,
                          bottom: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.value.first.routeLabel,
                                style: tokens.typography.label.copyWith(
                                  color: tokens.muted,
                                ),
                              ),
                            ),
                            if (!enlarged &&
                                entry.value.any(
                                  (c) =>
                                      c.prices?.input != null ||
                                      c.prices?.output != null ||
                                      c.prices?.free == true,
                                )) ...[
                              for (final column in [
                                if (entry.value.any(
                                  (c) =>
                                      c.prices?.input != null ||
                                      c.prices?.free == true,
                                ))
                                  'In',
                                if (entry.value.any(
                                  (c) =>
                                      c.prices?.output != null ||
                                      c.prices?.free == true,
                                ))
                                  'Out',
                              ])
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    column,
                                    textAlign: TextAlign.right,
                                    style: tokens.typography.label.copyWith(
                                      color: tokens.muted,
                                    ),
                                  ),
                                ),
                            ],
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      if (entry.value.any(
                        (c) =>
                            c.prices?.input != null ||
                            c.prices?.output != null ||
                            c.prices?.free == true,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Text(
                            'Per 1M tokens',
                            style: tokens.typography.label.copyWith(
                              fontSize: 10,
                              color: tokens.muted,
                            ),
                          ),
                        ),
                      for (final choice in entry.value)
                        _choice(
                          choice,
                          showInput: entry.value.any(
                            (c) =>
                                c.prices?.input != null ||
                                c.prices?.free == true,
                          ),
                          showOutput: entry.value.any(
                            (c) =>
                                c.prices?.output != null ||
                                c.prices?.free == true,
                          ),
                        ),
                    ]
                  else
                    for (final choice in filtered)
                      _choice(
                        choice,
                        showInput: filtered.any(
                          (c) =>
                              c.prices?.input != null || c.prices?.free == true,
                        ),
                        showOutput: filtered.any(
                          (c) =>
                              c.prices?.output != null ||
                              c.prices?.free == true,
                        ),
                      ),
                  if (filtered.isEmpty && specials.isEmpty && !showMissing)
                    Padding(
                      padding: const EdgeInsets.all(16),
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
      ),
    );
  }

  double mathFilterHeight(BuildContext context) =>
      48 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 40);
}
