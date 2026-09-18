import 'usage_cost.dart';

const usagePeriods = [1, 7, 30, 90, 365];
const usageTokenKeys = ['input_tokens', 'cache_read_tokens', 'output_tokens'];
const usageTokenLabels = ['Uncached input', 'Cached input', 'Output'];

/// Null counters stay unknown. Reasoning is already included in output.
class UsageTokens {
  final List<int?> values;
  UsageTokens.fromJson(Map<String, dynamic> row)
    : values = [for (final key in usageTokenKeys) usageTokenCount(row[key])];
  const UsageTokens.zero() : values = const [0, 0, 0];
  UsageTokens.sum(Iterable<UsageTokens> rows)
    : values = [
        for (var i = 0; i < 3; i++)
          _completeSum(rows.map((row) => row.values[i])),
      ];
  int? get total => _completeSum(values);
  bool get complete => total != null;

  static int? _completeSum(Iterable<int?> values) {
    var total = 0;
    for (final value in values) {
      if (value == null) return null;
      total += value;
    }
    return usageTokenCount(total);
  }
}

class UsageDay {
  final DateTime date;
  final UsageTokens tokens;
  const UsageDay(this.date, this.tokens);
  String get id => date.toIso8601String().substring(0, 10);
}

class UsageDaily {
  final List<UsageDay> days;
  UsageDaily._(this.days);

  factory UsageDaily.fromJson(
    Map<String, dynamic> data, {
    required int period,
    required DateTime loadedAt,
  }) {
    if (!usagePeriods.contains(period) || data['daily'] is! List) {
      throw const FormatException('Daily usage is unavailable.');
    }
    final byDate = <String, UsageTokens>{};
    for (final raw in data['daily'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid daily usage.');
      }
      final id = raw['day'];
      final date = id is String ? DateTime.tryParse('${id}T00:00:00Z') : null;
      if (date == null ||
          date.toIso8601String().substring(0, 10) != id ||
          byDate.containsKey(id)) {
        throw const FormatException('Invalid usage date.');
      }
      byDate[id as String] = UsageTokens.fromJson(raw);
    }
    final now = loadedAt.toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    // Hermes filters a rolling N*24 hours then groups by UTC session-start date.
    // Include the partial first date; a 1D query can therefore have two cells.
    final first = today.subtract(Duration(days: period));
    return UsageDaily._([
      for (var i = 0; i <= period; i++)
        UsageDay(
          first.add(Duration(days: i)),
          byDate[first
                  .add(Duration(days: i))
                  .toIso8601String()
                  .substring(0, 10)] ??
              const UsageTokens.zero(),
        ),
    ]);
  }
}

class UsageModelGroup {
  final String model;
  final String provider;
  final List<ModelUsageCost> rows;
  UsageModelGroup(this.model, this.provider, this.rows);
  String get id => '$provider/$model';
  UsageTokens get tokens =>
      UsageTokens.sum(rows.map((r) => UsageTokens.fromJson(r.usage)));
  UsageCostSummary get costs => UsageCostSummary(rows);
}

class UsageModels {
  final List<ModelUsageCost> rows;
  final List<UsageModelGroup> groups;
  UsageModels._(this.rows, this.groups);
  factory UsageModels.fromJson(
    Map<String, dynamic> data,
    OpenAiPricingCatalog? prices,
  ) {
    if (data['models'] is! List) {
      throw const FormatException('Model usage is unavailable.');
    }
    final rows = <ModelUsageCost>[];
    final grouped = <(String, String), List<ModelUsageCost>>{};
    for (final raw in data['models'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid model usage.');
      }
      final row = ModelUsageCost.fromUsage(raw, prices);
      rows.add(row);
      final key = (row.model, '${raw['provider'] ?? 'Provider unavailable'}');
      (grouped[key] ??= []).add(row);
    }
    final groups = [
      for (final entry in grouped.entries)
        UsageModelGroup(entry.key.$1, entry.key.$2, entry.value),
    ]..sort((a, b) => a.id.compareTo(b.id));
    return UsageModels._(rows, groups);
  }
  UsageCostSummary get costs => UsageCostSummary(rows);
  UsageTokens get tokens =>
      UsageTokens.sum(rows.map((r) => UsageTokens.fromJson(r.usage)));

  /// Reported provider totals cannot be split into token-type costs.
  List<double>? get tokenCosts {
    if (rows.isEmpty) return [0, 0, 0];
    if (rows.any((r) => !r.isApiEquivalent || r.amount == null)) return null;
    return [
      rows.fold(0, (sum, r) => sum + r.inputCost!),
      rows.fold(0, (sum, r) => sum + r.cachedInputCost!),
      rows.fold(0, (sum, r) => sum + r.outputCost!),
    ];
  }
}
