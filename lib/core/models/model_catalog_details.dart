/// Optional route prices or direct API-equivalent rates. Absence stays absent.
class ModelPrices {
  const ModelPrices({this.input, this.output, this.cache, required this.free})
    : _apiInput = null,
      _apiOutput = null,
      _apiCache = null,
      apiEquivalent = false;
  final String? input;
  final String? output;
  final String? cache;
  final bool free;
  final double? _apiInput;
  final double? _apiOutput;
  final double? _apiCache;
  final bool apiEquivalent;

  ModelPrices.api({
    required double input,
    required double output,
    double? cache,
  }) : input = _apiLabel(input),
       output = _apiLabel(output),
       cache = cache == null ? null : _apiLabel(cache),
       free = input == 0 && output == 0 && cache == 0,
       _apiInput = input,
       _apiOutput = output,
       _apiCache = cache,
       apiEquivalent = true;

  static String _apiLabel(double value) {
    final exact = value.toString();
    final fraction = exact.split('.').last;
    return '\$${!exact.contains('e') && fraction.length <= 2 ? value.toStringAsFixed(2) : exact}';
  }

  String get units =>
      apiEquivalent ? 'API equivalent · per 1M tokens' : 'Per 1M tokens';

  /// Stock model/options prices are USD per million tokens, formatted as
  /// "$2.50" or "free". Unknown/missing prices are never guessed.
  double? get inputUsdPerMillion =>
      apiEquivalent ? _apiInput : _usdPerMillion(input);
  double? get outputUsdPerMillion =>
      apiEquivalent ? _apiOutput : _usdPerMillion(output);
  double? get cacheUsdPerMillion =>
      apiEquivalent ? _apiCache : _usdPerMillion(cache);

  static ModelPrices fromJson(Map<dynamic, dynamic> price) => ModelPrices(
    input: _text(price['input']),
    output: _text(price['output']),
    cache: _text(price['cache']),
    free: price['free'] == true,
  );

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static double? _usdPerMillion(String? value) {
    if (value == 'free') return 0;
    if (value == null || !RegExp(r'^\$\d+(?:\.\d+)?$').hasMatch(value)) {
      return null;
    }
    final amount = double.tryParse(value.substring(1));
    return amount != null && amount.isFinite && amount >= 0 ? amount : null;
  }
}

/// Picker control availability, not inferred model capabilities.
class ModelControls {
  const ModelControls({
    required this.reasoning,
    required this.fast,
    required this.ultrafast,
    required this.canDisableReasoning,
  });
  final bool reasoning;
  final bool fast;
  final bool ultrafast;
  final bool canDisableReasoning;
}

class AccountUsageWindow {
  const AccountUsageWindow({
    required this.label,
    required this.usedPercent,
    required this.scope,
    this.resetsAt,
  });
  final String label;
  final double usedPercent;
  final String scope;
  final DateTime? resetsAt;
}

enum AccountUsageState { ready, limited, unknown, unavailable }

class SubscriptionAccount {
  SubscriptionAccount({
    required this.id,
    required this.label,
    required this.state,
    required Iterable<AccountUsageWindow> windows,
    this.resetsAt,
  }) : windows = List.unmodifiable(windows);
  final String id;
  final String label;
  final AccountUsageState state;
  final List<AccountUsageWindow> windows;
  final DateTime? resetsAt;
}

/// Single-account windows and pooled accounts are distinct observations.
/// No cross-account percentage or recovery time is manufactured.
class ProviderAccountUsage {
  ProviderAccountUsage({
    required Iterable<AccountUsageWindow> windows,
    required Iterable<SubscriptionAccount> accounts,
  }) : windows = List.unmodifiable(windows),
       accounts = List.unmodifiable(accounts);
  final List<AccountUsageWindow> windows;
  final List<SubscriptionAccount> accounts;
}

class ModelProvider {
  const ModelProvider({
    required this.slug,
    required this.name,
    this.authType,
    this.authenticated,
    this.warning,
    this.usage,
  });
  final String slug;
  final String name;
  final String? authType;
  final bool? authenticated;
  final String? warning;
  final ProviderAccountUsage? usage;
}
