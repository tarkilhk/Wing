import 'dart:convert';

/// Published standard API rates, applied only to the openai-codex route.
/// Exact IDs avoid pricing a newly discovered model as a different model.
class OpenAiPricingCatalog {
  final Map<String, OpenAiModelPrice> _models;

  OpenAiPricingCatalog._(this._models);

  factory OpenAiPricingCatalog.fromJson(String source) {
    final json = jsonDecode(source);
    if (json is! Map || json['version'] != 1 || json['currency'] != 'USD') {
      throw const FormatException('Invalid OpenAI price catalogue');
    }
    final models = json['models'];
    if (models is! Map || models.isEmpty) {
      throw const FormatException('Missing OpenAI prices');
    }
    final prices = <String, OpenAiModelPrice>{};
    for (final entry in models.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw const FormatException('Invalid model ID');
      }
      prices[entry.key as String] = OpenAiModelPrice._fromJson(entry.value);
    }
    return OpenAiPricingCatalog._(Map.unmodifiable(prices));
  }

  OpenAiModelPrice? priceFor(String model) => _models[model];
}

class OpenAiModelPrice {
  final double input;
  final double cachedInput;
  final double output;

  const OpenAiModelPrice._(this.input, this.cachedInput, this.output);

  factory OpenAiModelPrice._fromJson(Object? value) {
    if (value is! Map || value['usd_per_million'] is! Map) {
      throw const FormatException('Invalid model price');
    }
    final rates = value['usd_per_million'] as Map;
    final input = usageAmount(rates['input']);
    final cachedInput = usageAmount(rates['cached_input']);
    final output = usageAmount(rates['output']);
    final verifiedOn = DateTime.tryParse('${value['verified_on']}');
    final source = Uri.tryParse('${value['source']}');
    if (input == null ||
        cachedInput == null ||
        output == null ||
        verifiedOn == null ||
        source == null ||
        source.scheme != 'https' ||
        source.host != 'developers.openai.com') {
      throw const FormatException('Incomplete model price');
    }
    return OpenAiModelPrice._(input, cachedInput, output);
  }
}

double? usageAmount(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

int? usageTokenCount(Object? value) =>
    value is num &&
        value.isFinite &&
        value >= 0 &&
        value <= 9007199254740991 &&
        value == value.truncateToDouble()
    ? value.toInt()
    : null;

enum UsageCostUnavailable { price, tokens, reportedCost }

/// Hermes analytics input is already uncached; output already includes reasoning.
/// These estimates intentionally exclude cache writes and request-level surcharges.
class ModelUsageCost {
  final String model;
  final bool isApiEquivalent;
  final List<int?> tokenCounts;
  final double? inputCost;
  final double? cachedInputCost;
  final double? outputCost;
  final double? amount;
  final UsageCostUnavailable? unavailable;

  ModelUsageCost._(
    Map<String, dynamic> usage,
    this.inputCost,
    this.cachedInputCost,
    this.outputCost,
    this.amount,
    this.unavailable,
  ) : model = usage['model'] is String
          ? usage['model'] as String
          : 'Unknown model',
      isApiEquivalent = usage['provider'] == 'openai-codex',
      tokenCounts = List.unmodifiable([
        usageTokenCount(usage['input_tokens']),
        usageTokenCount(usage['cache_read_tokens']),
        usageTokenCount(usage['output_tokens']),
      ]);

  factory ModelUsageCost.fromUsage(
    Map<String, dynamic> usage,
    OpenAiPricingCatalog? catalog,
  ) {
    if (usage['provider'] != 'openai-codex') {
      final amount = usageAmount(usage['estimated_cost']);
      return ModelUsageCost._(
        usage,
        null,
        null,
        null,
        amount,
        amount == null ? UsageCostUnavailable.reportedCost : null,
      );
    }
    final price = catalog?.priceFor('${usage['model']}');
    if (price == null) {
      return ModelUsageCost._(
        usage,
        null,
        null,
        null,
        null,
        UsageCostUnavailable.price,
      );
    }
    final input = usageTokenCount(usage['input_tokens']);
    final cached = usageTokenCount(usage['cache_read_tokens']);
    final output = usageTokenCount(usage['output_tokens']);
    if (input == null || cached == null || output == null) {
      return ModelUsageCost._(
        usage,
        null,
        null,
        null,
        null,
        UsageCostUnavailable.tokens,
      );
    }
    final inputCost = input / 1000000 * price.input;
    final cachedCost = cached / 1000000 * price.cachedInput;
    final outputCost = output / 1000000 * price.output;
    final amount = usageAmount(inputCost + cachedCost + outputCost);
    return ModelUsageCost._(
      usage,
      inputCost,
      cachedCost,
      outputCost,
      amount,
      amount == null ? UsageCostUnavailable.tokens : null,
    );
  }
}

class UsageCostSummary {
  final List<ModelUsageCost> models;
  UsageCostSummary(Iterable<ModelUsageCost> models)
    : models = List.unmodifiable(models);

  bool get hasSubscription => models.any((model) => model.isApiEquivalent);
  bool get hasReported => models.any((model) => !model.isApiEquivalent);
  bool get isMixed => hasSubscription && hasReported;
  int get pricedCount => models.where((model) => model.amount != null).length;
  bool get isPartial => pricedCount < models.length;
  double? get total => _sum(models);
  double? get apiEquivalent =>
      _sum(models.where((model) => model.isApiEquivalent));
  double? get reported => _sum(models.where((model) => !model.isApiEquivalent));

  static double? _sum(Iterable<ModelUsageCost> models) {
    final amounts = models.map((model) => model.amount).whereType<double>();
    return amounts.isEmpty
        ? null
        : usageAmount(amounts.fold<double>(0, (a, b) => a + b));
  }
}

String formatUsageUsd(double? amount) {
  if (amount == null || !amount.isFinite || amount < 0) return 'Unavailable';
  if (amount > 0 && amount < 0.01) return '< USD 0.01';
  return 'USD ${amount.toStringAsFixed(2)}';
}
