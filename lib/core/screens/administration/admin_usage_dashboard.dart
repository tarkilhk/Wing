import 'package:flutter/material.dart';
import '../../models/usage_analytics.dart';
import '../../models/usage_cost.dart';
import '../../services/administration_repository.dart';
import '../../services/usage_analytics.dart';
import '../../theme/wing_theme.dart';
import 'admin_usage_details.dart';
import 'admin_widgets.dart';
import 'usage_charts.dart';

class UsageDashboard extends StatefulWidget {
  final ProfileAdministration profile;
  const UsageDashboard({super.key, required this.profile});
  @override
  State<UsageDashboard> createState() => _UsageDashboardState();
}

class _UsageDashboardState extends State<UsageDashboard> {
  late UsageAnalyticsReader _reader;
  final _cache = <int, UsageAnalyticsResult>{};
  final _pending = <int>{};
  final _modelColors = <String, int>{};
  int _days = 7;
  String? _selected;
  bool _breakdownModels = true;
  bool _breakdownCost = false;
  bool _trendModels = true;
  bool _trendCost = false;
  UsageAnalyticsResult? get _data => _cache[_days];

  @override
  void initState() {
    super.initState();
    _reader = UsageAnalyticsReader(widget.profile);
    _load();
  }

  Future<void> _load() async {
    final days = _days;
    if (_pending.contains(days)) return;
    setState(() => _pending.add(days));
    final result = await _reader.load(days);
    if (!mounted) return;
    final old = _cache[days];
    setState(() {
      _pending.remove(days);
      _cache[days] = UsageAnalyticsResult(
        models: result.models ?? old?.models,
        daily: result.daily ?? old?.daily,
        modelsError: result.modelsError,
        dailyError: result.dailyError,
        loadedAt: result.modelsError != null || result.dailyError != null
            ? old?.loadedAt ?? result.loadedAt
            : result.loadedAt,
      );
    });
  }

  void _period(int days) {
    setState(() {
      _days = days;
      _selected = null;
    });
    if (!_cache.containsKey(days)) _load();
  }

  String _number(num? value) => value == null
      ? 'Unavailable'
      : MaterialLocalizations.of(context).formatDecimal(value.toInt());
  String _value(double? value, bool cost) =>
      cost ? formatUsageUsd(value) : compactUsage(value);
  Widget _quiet(String text) =>
      Text(text, style: Theme.of(context).textTheme.bodySmall);

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final models = data?.models;
    final daily = data?.daily;
    final summary = models?.costs;
    final loading = _pending.contains(_days);
    final selected = daily?.days.where((d) => d.id == _selected).firstOrNull;
    final costTitle = summary?.isMixed == true
        ? 'Estimated usage value'
        : summary?.hasSubscription == true
        ? 'API-equivalent cost'
        : 'Estimated cost';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final days in usagePeriods)
              _Choice(
                label: '${days}D',
                selected: _days == days,
                neutral: true,
                onPressed: () => _period(days),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (data == null) ...[
          const LinearProgressIndicator(semanticsLabel: 'Loading usage'),
          const SizedBox(height: 20),
          const Text('Loading usage…'),
        ] else ...[
          if (data.modelsError != null || data.dailyError != null)
            AdminNotice.error(
              '${[data.modelsError, data.dailyError].whereType<String>().join(' ')}${models != null || daily != null ? ' Showing retained data where available; last successful load ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(data.loadedAt.toLocal()))}.' : ''} Use Refresh to retry.',
            ),
          if (loading)
            const LinearProgressIndicator(semanticsLabel: 'Refreshing usage'),
          LayoutBuilder(
            builder: (context, constraints) {
              final stats = [
                _Stat(
                  label: 'Tokens',
                  value: models == null || models.rows.isEmpty
                      ? models == null
                            ? 'Unavailable'
                            : '0'
                      : compactUsage(models.tokens.total),
                  detail:
                      models?.tokens.total == null &&
                          models != null &&
                          models.rows.isNotEmpty
                      ? 'Some counts unavailable'
                      : 'Across models',
                  exact: _number(models?.tokens.total),
                ),
                _Stat(
                  label: costTitle,
                  value: models?.rows.isEmpty == true
                      ? 'USD 0.00'
                      : formatUsageUsd(summary?.total),
                  detail: summary?.isPartial == true
                      ? 'Partial total'
                      : summary?.hasSubscription == true
                      ? 'Not a bill'
                      : 'Hermes estimate',
                ),
              ];
              if (MediaQuery.textScalerOf(context).scale(16) > 24 ||
                  constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [stats[0], const SizedBox(height: 12), stats[1]],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: stats[0]),
                  const SizedBox(width: 16),
                  Expanded(child: stats[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Usage by day', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (daily != null)
            UsageCalendar(
              daily: daily,
              selected: _selected,
              onSelected: (day) => setState(
                () => _selected = _selected == day.id ? null : day.id,
              ),
            )
          else
            _quiet(
              'Daily usage unavailable. Period totals may still be available.',
            ),
          const SizedBox(height: 20),
          _ChartHeader(
            section: 'Breakdown',
            models: _breakdownModels,
            cost: _breakdownCost,
            onGroup: () => setState(() => _breakdownModels = !_breakdownModels),
            onCost: (v) => setState(() => _breakdownCost = v),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              _quiet(
                selected == null
                    ? 'Last $_days ${_days == 1 ? 'day' : 'days'} · all models'
                    : MaterialLocalizations.of(
                        context,
                      ).formatFullDate(selected.date),
              ),
              if (selected != null)
                TextButton(
                  onPressed: () => setState(() => _selected = null),
                  child: const Text('All days'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _breakdown(models, selected),
          const SizedBox(height: 24),
          _ChartHeader(
            section: 'Trend',
            models: _trendModels,
            cost: _trendCost,
            onGroup: () => setState(() => _trendModels = !_trendModels),
            onCost: (v) => setState(() => _trendCost = v),
          ),
          const SizedBox(height: 8),
          _trend(daily),
          const SizedBox(height: 20),
          _about(models),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(loading ? 'Refreshing…' : 'Refresh'),
          ),
        ),
      ],
    );
  }

  Widget _breakdown(UsageModels? models, UsageDay? selected) {
    if (selected != null && (_breakdownModels || _breakdownCost)) {
      return _Unavailable(
        message: _breakdownCost
            ? 'Daily API-equivalent costs need model counts that Hermes does not provide by day.'
            : 'Hermes does not provide a model breakdown by day.',
        action: 'Show daily tokens',
        onPressed: () => setState(() {
          _breakdownModels = false;
          _breakdownCost = false;
        }),
      );
    }
    if (selected == null && models == null) {
      return const Text('Period breakdown unavailable.');
    }
    if (selected == null && models!.rows.isEmpty) {
      return const Text('No recorded model usage in this period.');
    }
    final colors = usageColors(context);
    final segments = <UsageSegment>[];
    if (_breakdownModels) {
      // Keep the same segment order across measure changes so widths morph.
      for (final group in models!.groups) {
        segments.add(
          UsageSegment(
            id: group.id,
            label: group.model,
            value: _breakdownCost
                ? group.costs.total
                : group.tokens.total?.toDouble(),
            color:
                colors[_modelColors.putIfAbsent(
                      group.id,
                      () => _modelColors.length,
                    ) %
                    colors.length],
            partial: _breakdownCost && group.costs.isPartial,
            onTap: () => _modelDetails(group),
          ),
        );
      }
    } else {
      final tokens = selected?.tokens ?? models!.tokens;
      final costs = models?.tokenCosts;
      if (_breakdownCost && costs == null) {
        return const _Unavailable(
          message:
              'Cost per token type is available only when every model has a complete subscription API estimate. Hermes reports other costs as one combined amount.',
        );
      }
      for (var i = 0; i < 3; i++) {
        segments.add(
          UsageSegment(
            id: usageTokenKeys[i],
            label: usageTokenLabels[i],
            value: _breakdownCost ? costs![i] : tokens.values[i]?.toDouble(),
            color: colors[i],
          ),
        );
      }
    }
    final partial = segments.any((s) => s.value == null || s.partial);
    final noValues = segments.every((s) => s.value == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!noValues) UsageComposition(segments: segments),
        if (partial)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _quiet(
              'Partial breakdown · unavailable values are excluded from the bar.',
            ),
          ),
        const SizedBox(height: 8),
        for (final segment in segments)
          Semantics(
            label:
                '${segment.label}: ${_breakdownCost ? formatUsageUsd(segment.value) : '${_number(segment.value)} tokens'}${segment.partial ? ', partial' : ''}',
            child: InkWell(
              onTap: segment.onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: segment.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        segment.label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${_value(segment.value, _breakdownCost)}${segment.partial ? ' · partial' : ''}',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (segment.onTap != null)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.chevron_right, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _trend(UsageDaily? daily) {
    if (_trendModels || _trendCost) {
      return _Unavailable(
        message: _trendCost
            ? 'Daily API-equivalent costs are unavailable: daily totals do not identify models.'
            : 'Hermes provides daily tokens by type, but no daily model history.',
        action: 'Show token trend',
        onPressed: () => setState(() {
          _trendModels = false;
          _trendCost = false;
        }),
      );
    }
    if (daily == null) {
      return const Text('Daily usage unavailable. Use Refresh to retry.');
    }
    if (daily.days.any((d) => !d.tokens.complete)) {
      return const Text(
        'Some daily token counts are unavailable. Select a date in the grid to inspect its recorded counts.',
      );
    }
    if (daily.days.every((d) => d.tokens.total == 0)) {
      return const Text('No recorded daily tokens in this period.');
    }
    return UsageAreaChart(daily: daily, selected: _selected);
  }

  Widget _about(UsageModels? models) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('About this usage'),
    childrenPadding: const EdgeInsets.only(bottom: 12),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _quiet(
        'Daily charts group accumulated session tokens by UTC session-start date, not the date of each request. The first and last date can be partial days.',
      ),
      const SizedBox(height: 8),
      _quiet(
        'Period model totals also include background usage. Daily charts exclude it, so the totals may differ. Output already includes reasoning tokens.',
      ),
      const SizedBox(height: 8),
      _quiet(
        models?.costs.hasSubscription == true
            ? 'Subscription usage is valued at published API rates, not billed spend. Base rates exclude cache-write charges and long-context or service-tier adjustments. Tap a model for counts, rates and pricing sources.'
            : 'Costs are Hermes estimates, not provider invoices. Tap a model for its recorded counts.',
      ),
      if (models?.costs.isMixed == true) ...[
        const SizedBox(height: 8),
        _quiet(
          'Hermes estimates: ${formatUsageUsd(models!.costs.reported)} · Subscription API equivalent: ${formatUsageUsd(models.costs.apiEquivalent)}',
        ),
      ],
    ],
  );

  void _modelDetails(UsageModelGroup group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        maxChildSize: .95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Model details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close details',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              widget.profile.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (group.rows.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${group.rows.length} recorded contributions, including background usage.',
                ),
              ),
            for (final (i, model) in group.rows.indexed)
              UsageModelDetails(
                model: model,
                total: _data?.models?.costs.total,
                storageKey: PageStorageKey(
                  'usage-details:${widget.profile.scope.storageNamespace}:$_days:${group.id}:$i',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final bool neutral;
  final VoidCallback onPressed;
  const _Choice({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.neutral = false,
  });
  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: neutral ? tokens.onSurface : null,
          backgroundColor: selected
              ? neutral
                    ? tokens.border.withValues(alpha: .35)
                    : Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

class _ChartHeader extends StatelessWidget {
  final String section;
  final bool models;
  final bool cost;
  final VoidCallback onGroup;
  final ValueChanged<bool> onCost;
  const _ChartHeader({
    required this.section,
    required this.models,
    required this.cost,
    required this.onGroup,
    required this.onCost,
  });
  @override
  Widget build(BuildContext context) {
    final title = TextButton(
      key: ValueKey('usage-${section.toLowerCase()}-group'),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
        foregroundColor: WingTokens.of(context).onSurface,
      ),
      onPressed: onGroup,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$section per ${models ? 'model' : 'token type'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.swap_horiz, size: 18),
        ],
      ),
    );
    final choices = Wrap(
      alignment: WrapAlignment.end,
      children: [
        _Choice(
          label: 'Tokens',
          selected: !cost,
          onPressed: () => onCost(false),
        ),
        _Choice(label: 'Cost', selected: cost, onPressed: () => onCost(true)),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 350 ||
            MediaQuery.textScalerOf(context).scale(16) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              Align(alignment: Alignment.centerRight, child: choices),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 8),
            choices,
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final String? exact;
  const _Stat({
    required this.label,
    required this.value,
    required this.detail,
    this.exact,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Tooltip(
        message: exact ?? value,
        child: Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ),
      const SizedBox(height: 4),
      Text(detail, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _Unavailable extends StatelessWidget {
  final String message;
  final String? action;
  final VoidCallback? onPressed;
  const _Unavailable({required this.message, this.action, this.onPressed});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: WingTokens.of(context).raised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        if (action != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onPressed, child: Text(action!)),
          ),
      ],
    ),
  );
}
