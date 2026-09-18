import 'package:flutter/services.dart';
import '../models/usage_analytics.dart';
import '../models/usage_cost.dart';
import 'administration_repository.dart';

/// The two stock aggregate reads are independent: either can remain usable
/// when the other fails. No session fan-out or per-day pricing inference.
class UsageAnalyticsResult {
  final UsageModels? models;
  final UsageDaily? daily;
  final String? modelsError;
  final String? dailyError;
  final DateTime loadedAt;
  const UsageAnalyticsResult({
    this.models,
    this.daily,
    this.modelsError,
    this.dailyError,
    required this.loadedAt,
  });
}

class UsageAnalyticsReader {
  final ProfileAdministration profile;
  final Future<String> Function() loadPrices;
  final DateTime Function() now;
  OpenAiPricingCatalog? _prices;
  UsageAnalyticsReader(
    this.profile, {
    Future<String> Function()? loadPrices,
    DateTime Function()? now,
  }) : loadPrices =
           loadPrices ??
           (() => rootBundle.loadString('assets/pricing/openai.json')),
       now = now ?? DateTime.now;

  Future<UsageDaily>? _year;

  /// Shared by the persistent calendar and the 365D trend. Period changes do
  /// not refetch the year; explicit refresh replaces this scope-local cache.
  Future<UsageDaily> loadYear({bool refresh = false}) {
    if (refresh || _year == null) _year = _readDaily(365);
    return _year!;
  }

  Future<UsageDaily> _readDaily(int days) async {
    final loadedAt = now().toUtc();
    return UsageDaily.fromJson(
      await profile.read('analytics/usage', {'days': '$days'}),
      period: days,
      loadedAt: loadedAt,
    );
  }

  Future<UsageAnalyticsResult> load(int days) async {
    if (!usagePeriods.contains(days)) throw ArgumentError.value(days, 'days');
    final loadedAt = now().toUtc();
    UsageModels? models;
    UsageDaily? daily;
    String? modelsError;
    String? dailyError;
    await Future.wait([
      (() async {
        try {
          final data = await profile.read('analytics/models', {
            'days': '$days',
          });
          if (_prices == null &&
              data['models'] is List &&
              (data['models'] as List).any(
                (r) => r is Map && r['provider'] == 'openai-codex',
              )) {
            _prices = OpenAiPricingCatalog.fromJson(await loadPrices());
          }
          models = UsageModels.fromJson(data, _prices);
        } catch (_) {
          modelsError = 'Could not load model totals.';
        }
      })(),
      (() async {
        try {
          daily = await (days == 365 ? loadYear() : _readDaily(days));
        } catch (_) {
          dailyError = 'Could not load daily usage.';
        }
      })(),
    ]);
    return UsageAnalyticsResult(
      models: models,
      daily: daily,
      modelsError: modelsError,
      dailyError: dailyError,
      loadedAt: loadedAt,
    );
  }
}
