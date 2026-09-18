import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/usage_analytics.dart';
import 'package:wing/core/models/usage_cost.dart';
import 'package:wing/core/services/usage_analytics.dart';
import 'support/administration_fixture.dart';

void main() {
  final now = DateTime.utc(2026, 9, 18, 12);
  final row = <String, dynamic>{
    'model': 'gpt-6-astra',
    'provider': 'openai-codex',
    'input_tokens': 250000,
    'cache_read_tokens': 1000000,
    'output_tokens': 30000,
    'reasoning_tokens': 20000,
    'estimated_cost': 0,
  };
  final prices = OpenAiPricingCatalog.fromJson(
    File('assets/pricing/openai.json').readAsStringSync(),
  );
  test(
    'rolling day includes both partial UTC dates, fills only absent days',
    () {
      final data = UsageDaily.fromJson(
        {
          'daily': [
            {'day': '2026-09-17', ...row},
            {'day': '2026-09-18', 'input_tokens': 3, 'output_tokens': 2},
          ],
        },
        period: 1,
        loadedAt: now,
      );
      expect(data.days.map((d) => d.id), ['2026-09-17', '2026-09-18']);
      expect(data.days.first.tokens.total, 1280000);
      expect(data.days.last.tokens.total, isNull);
      final empty = UsageDaily.fromJson(
        {'daily': []},
        period: 365,
        loadedAt: now,
      );
      expect(empty.days.length, 366);
      expect(empty.days.every((d) => d.tokens.total == 0), isTrue);
      expect(
        () => UsageDaily.fromJson({}, period: 7, loadedAt: now),
        throwsFormatException,
      );
      expect(
        () => UsageDaily.fromJson(
          {
            'daily': [
              {'day': '2026-02-30'},
            ],
          },
          period: 7,
          loadedAt: now,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'auxiliary duplicates combine, providers remain distinct, reasoning is not added',
    () {
      final data = UsageModels.fromJson({
        'models': [
          row,
          row,
          {...row, 'provider': 'openai', 'estimated_cost': 7},
        ],
      }, prices);
      expect(data.groups.length, 2);
      expect(data.costs.total, 17);
      expect(data.tokens.total, 3840000);
      expect(
        data.groups
            .singleWhere((g) => g.provider == 'openai-codex')
            .costs
            .total,
        10,
      );
      expect(data.tokenCosts, isNull);
      expect(
        UsageModels.fromJson({
          'models': [row],
        }, prices).tokenCosts,
        [2.5, 1, 1.5],
      );
    },
  );
  test('missing tokens and unknown prices stay unavailable in aggregates', () {
    final data = UsageModels.fromJson({
      'models': [
        row,
        {...row, 'model': 'unknown', 'cache_read_tokens': null},
      ],
    }, prices);
    expect(data.tokens.total, isNull);
    expect(data.tokens.values[0], 500000);
    expect(data.costs.total, 5);
    expect(data.costs.isPartial, isTrue);
    expect(data.tokenCosts, isNull);
    expect(
      UsageTokens.fromJson({
        'input_tokens': 1.5,
        'cache_read_tokens': -1,
        'output_tokens': double.infinity,
      }).values,
      [null, null, null],
    );
  });
  test(
    'parallel bounded reads retain profile and independent successes',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      final models = Completer<Map<String, dynamic>>();
      final daily = Completer<Map<String, dynamic>>();
      fixture.override = (_, path, _, _) =>
          path == 'analytics/models' ? models.future : daily.future;
      final reader = UsageAnalyticsReader(
        fixture.server.profile('client-work'),
        now: () => now,
        loadPrices: () async =>
            File('assets/pricing/openai.json').readAsStringSync(),
      );
      final result = reader.load(365);
      expect(fixture.requests.map((r) => r.$2).toSet(), {
        'analytics/models',
        'analytics/usage',
      });
      expect(
        fixture.requests.every(
          (r) =>
              r.$1 == 'GET' &&
              r.$3['profile'] == 'client-work' &&
              r.$3['days'] == '365',
        ),
        isTrue,
      );
      models.complete({
        'models': [row],
      });
      daily.completeError(StateError('Offline'));
      final loaded = await result;
      expect(loaded.models!.costs.total, 5);
      expect(loaded.daily, isNull);
      expect(loaded.dailyError, isNotNull);
      expect(loaded.modelsError, isNull);
    },
  );
}
