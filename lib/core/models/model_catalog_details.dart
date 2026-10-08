/// Optional observations supplied by stock model/options. Absence stays absent.
class ModelPrices {
  const ModelPrices({this.input, this.output, this.cache, required this.free});
  final String? input;
  final String? output;
  final String? cache;
  final bool free;
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
