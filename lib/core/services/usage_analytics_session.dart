import 'package:flutter/foundation.dart';

import '../models/usage_analytics.dart';
import 'usage_analytics.dart';
import 'workspace_connection_failure.dart';

/// Immutable observation of one captured profile's analytics.
class UsageAnalyticsState {
  const UsageAnalyticsState({
    required this.days,
    required this.data,
    required this.periodLoading,
    required this.year,
    required this.yearLoading,
    required this.yearError,
    required this.yearRetryable,
  });

  final int days;
  final UsageAnalyticsResult? data;
  final bool periodLoading;
  final UsageDaily? year;
  final bool yearLoading;
  final String? yearError;
  final bool yearRetryable;

  bool get loading => periodLoading || yearLoading;
  bool get needsRecovery =>
      yearRetryable && !yearLoading ||
      data?.needsRecovery == true && !periodLoading;
}

/// Period admission, retained partial results and recovery have one writer.
/// The existing reader owns stock I/O and shared year-read deduplication.
class UsageAnalyticsSession extends ChangeNotifier {
  UsageAnalyticsSession(UsageAnalyticsReader reader) : _reader = reader;

  final UsageAnalyticsReader _reader;
  final _periods = <int, UsageAnalyticsResult>{};
  final _pending = <int>{};
  int _days = 7;
  UsageDaily? _year;
  bool _yearLoading = false;
  bool _yearRetryable = false;
  String? _yearError;
  bool _closed = false;
  int _publicationDepth = 0;

  UsageAnalyticsState get state => UsageAnalyticsState(
    days: _days,
    data: _periods[_days],
    periodLoading: _pending.contains(_days),
    year: _year,
    yearLoading: _yearLoading,
    yearError: _yearError,
    yearRetryable: _yearRetryable,
  );

  Future<void> load() => Future.wait([_loadYear(), _loadPeriod()]);

  Future<void> refresh() =>
      Future.wait([_loadYear(refresh: true), _loadPeriod()]);

  Future<void> selectPeriod(int days) async {
    if (_closed) return;
    if (!usagePeriods.contains(days)) throw ArgumentError.value(days, 'days');
    _days = days;
    _publish();
    if (_closed) return;
    if (!_periods.containsKey(days)) {
      await _loadPeriod();
    } else if (_periods[days]!.needsRecovery) {
      await _loadPeriod(failedOnly: true);
    }
  }

  Future<void> recover() => Future.wait([
    if (_yearRetryable && !_yearLoading) _loadYear(),
    if (_periods[_days]?.needsRecovery == true && !_pending.contains(_days))
      _loadPeriod(failedOnly: true),
  ]);

  Future<void> _loadYear({bool refresh = false}) async {
    if (_closed || _yearLoading) return;
    _yearLoading = true;
    _publish();
    if (_closed) return;
    try {
      final year = await _reader.loadYear(refresh: refresh);
      if (_closed) return;
      _year = year;
      _yearError = null;
      _yearRetryable = false;
    } catch (error) {
      if (_closed) return;
      _yearRetryable = isTemporaryWorkspaceFailure(error);
      _yearError = _year == null
          ? 'Could not load the activity year. Use Refresh to retry.'
          : 'Could not refresh the activity year. Showing retained activity; use Refresh to retry.';
    } finally {
      if (!_closed) {
        _yearLoading = false;
        _publish();
      }
    }
  }

  Future<void> _loadPeriod({bool failedOnly = false}) async {
    final days = _days;
    if (_closed || _pending.contains(days)) return;
    _pending.add(days);
    _publish();
    if (_closed) return;
    final result = await _reader.load(
      days,
      retry: failedOnly ? _periods[days] : null,
    );
    if (_closed) return;
    final old = _periods[days];
    _pending.remove(days);
    _periods[days] = UsageAnalyticsResult(
      models: result.models ?? old?.models,
      daily: result.daily ?? old?.daily,
      modelsError: result.modelsError,
      dailyError: result.dailyError,
      modelsRetryable: result.modelsRetryable,
      dailyRetryable: result.dailyRetryable,
      loadedAt: result.modelsError != null || result.dailyError != null
          ? old?.loadedAt ?? result.loadedAt
          : result.loadedAt,
    );
    _publish();
  }

  void _publish() {
    if (_closed) return;
    _publicationDepth++;
    try {
      notifyListeners();
    } finally {
      _publicationDepth--;
      if (_closed && _publicationDepth == 0) super.dispose();
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    if (_publicationDepth == 0) super.dispose();
  }
}
