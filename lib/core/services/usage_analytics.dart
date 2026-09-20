import 'package:flutter/services.dart';
import '../models/usage_analytics.dart';
import '../models/usage_cost.dart';
import 'administration_repository.dart';
import 'workspace_connection_failure.dart';

/// The two stock aggregate reads are independent: either can remain usable
/// when the other fails. No session fan-out or per-day pricing inference.
class UsageAnalyticsResult {
  final UsageModels? models;
  final UsageDaily? daily;
  final String? modelsError;
  final String? dailyError;
  final DateTime loadedAt;
  final bool modelsRetryable;
  final bool dailyRetryable;
  bool get needsRecovery => modelsRetryable || dailyRetryable;
  const UsageAnalyticsResult({
    this.models,
    this.daily,
    this.modelsError,
    this.dailyError,
    required this.loadedAt,
    this.modelsRetryable = false,
    this.dailyRetryable = false,
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

  /// Successful years are shared by the calendar and 365D trend. Failed
  /// futures are evicted so recovery can read again; explicit refresh replaces
  /// a successful scope-local cache.
  Future<UsageDaily> loadYear({bool refresh = false}) {
    if (refresh || _year == null) {
      late final Future<UsageDaily> pending;
      pending = _readDaily(365).catchError((Object error, StackTrace stack) {
        if (identical(_year, pending)) _year = null;
        Error.throwWithStackTrace(error, stack);
      });
      _year = pending;
    }
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

  /// With [retry], retain successful sections from that period's observation
  /// and read only its temporarily failed sections.
  Future<UsageAnalyticsResult> load(
    int days, {
    UsageAnalyticsResult? retry,
  }) async {
    if (!usagePeriods.contains(days)) throw ArgumentError.value(days, 'days');
    final loadedAt = now().toUtc();
    UsageModels? models = retry?.models;
    UsageDaily? daily = retry?.daily;
    String? modelsError = retry?.modelsError;
    String? dailyError = retry?.dailyError;
    var modelsRetryable = retry?.modelsRetryable ?? false;
    var dailyRetryable = retry?.dailyRetryable ?? false;
    await Future.wait([
      if (retry == null || retry.modelsRetryable)
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
            modelsError = null;
            modelsRetryable = false;
          } catch (error) {
            modelsRetryable = isTemporaryWorkspaceFailure(error);
            modelsError = 'Could not load model totals.';
          }
        })(),
      if (retry == null || retry.dailyRetryable)
        (() async {
          try {
            daily = await (days == 365 ? loadYear() : _readDaily(days));
            dailyError = null;
            dailyRetryable = false;
          } catch (error) {
            dailyRetryable = isTemporaryWorkspaceFailure(error);
            dailyError = 'Could not load daily usage.';
          }
        })(),
    ]);
    return UsageAnalyticsResult(
      models: models,
      daily: daily,
      modelsError: modelsError,
      dailyError: dailyError,
      modelsRetryable: modelsRetryable,
      dailyRetryable: dailyRetryable,
      loadedAt: loadedAt,
    );
  }
}
