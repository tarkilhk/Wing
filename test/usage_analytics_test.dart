import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/usage_analytics.dart';
import 'package:wing/core/models/model_catalog.dart';
import 'package:wing/core/models/models_dev_prices.dart';
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
  final prices = ModelCatalog.fromOptions(
    subscriptionModelOptions(),
    apiPrices: subscriptionApiPrices(),
  );
  test(
    'subscription valuation shares direct API rates with the picker',
    () async {
      final fixture = AdministrationFixture()
        ..apiPrices = subscriptionApiPrices(input: 20);
      addTearDown(fixture.server.close);
      fixture.override = withSubscriptionModelOptions(
        (_, path, _, _) async => path == 'analytics/usage'
            ? {'daily': []}
            : {
                'models': [row],
              },
      );
      final profile = fixture.server.profile('personal');
      final picker = await profile.modelCatalog.load();
      expect(
        picker
            .choice('openai-codex', 'gpt-6-astra')!
            .prices!
            .inputUsdPerMillion,
        20,
      );
      final result = await UsageAnalyticsReader(profile).load(7);
      expect(result.models!.costs.total, 7.5);
    },
  );
  test('missing registry rates preserve tokens and reported costs', () async {
    final fixture = AdministrationFixture()..apiPrices = ModelsDevPrices({});
    addTearDown(fixture.server.close);
    fixture.override = (_, path, _, _) async {
      if (path == 'model/options') {
        return {
          'providers': [
            {
              'slug': 'openai-codex',
              'name': 'Subscription',
              'models': ['gpt-6-astra'],
            },
          ],
        };
      }
      if (path == 'analytics/usage') return {'daily': []};
      return {
        'models': [
          row,
          {...row, 'provider': 'openai', 'estimated_cost': 7},
        ],
      };
    };
    final result = await UsageAnalyticsReader(
      fixture.server.profile('personal'),
    ).load(7);
    expect(result.models!.tokens.total, 2560000);
    expect(result.models!.costs.apiEquivalent, isNull);
    expect(result.models!.costs.reported, 7);
    expect(result.models!.costs.isPartial, isTrue);
    expect(result.modelsError, isNull);
  });

  test(
    'rate download failure keeps tokens, cached estimates and explicit retry state',
    () async {
      final fixture = AdministrationFixture()
        ..apiPrices = ModelsDevPrices(
          subscriptionApiPrices().models,
          unavailable: true,
        );
      addTearDown(fixture.server.close);
      fixture.override = withSubscriptionModelOptions(
        (_, path, _, _) async => path == 'analytics/usage'
            ? {'daily': []}
            : {
                'models': [row],
              },
      );
      final reader = UsageAnalyticsReader(fixture.server.profile('personal'));
      final stale = await reader.load(7);
      expect(stale.models!.costs.total, 5);
      expect(stale.models!.tokens.total, 1280000);
      expect(stale.modelsError, contains('cached rates'));
      expect(stale.modelsRetryable, isTrue);
      fixture.apiPrices = subscriptionApiPrices(input: 20);
      final recovered = await reader.load(7, retry: stale, refresh: true);
      expect(recovered.models!.costs.total, 7.5);
      expect(recovered.modelsError, isNull);
      expect(recovered.modelsRetryable, isFalse);
      expect(recovered.daily, same(stale.daily));
    },
  );

  test('initial public price failure never hides successful usage', () async {
    final fixture = AdministrationFixture()
      ..apiPrices = ModelsDevPrices({}, unavailable: true);
    addTearDown(fixture.server.close);
    fixture.override = withSubscriptionModelOptions(
      (_, path, _, _) async => path == 'analytics/usage'
          ? {'daily': []}
          : {
              'models': [row],
            },
    );
    final data = await UsageAnalyticsReader(
      fixture.server.profile('personal'),
    ).load(7);
    expect(data.models!.tokens.total, 1280000);
    expect(data.models!.costs.total, isNull);
    expect(data.modelsError, contains('unavailable'));
    expect(data.modelsRetryable, isTrue);
  });

  test(
    'pricing failure retains usage and retries the captured catalog',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      var offline = true;
      final priced = withSubscriptionModelOptions(
        (_, path, _, _) async => path == 'analytics/usage'
            ? {'daily': []}
            : {
                'models': [row],
              },
      );
      fixture.override = (method, path, query, body) async {
        if (path == 'model/options' && offline) {
          throw TimeoutException('Offline');
        }
        return priced(method, path, query, body);
      };
      final reader = UsageAnalyticsReader(
        fixture.server.profile('client-work'),
      );
      final partial = await reader.load(7);
      expect(partial.models!.tokens.total, 1280000);
      expect(partial.models!.costs.total, isNull);
      expect(partial.modelsError, contains('prices'));
      expect(partial.modelsRetryable, isTrue);
      offline = false;
      fixture.requests.clear();
      final complete = await reader.load(7, retry: partial);
      expect(complete.models!.costs.total, 5);
      expect(complete.modelsError, isNull);
      expect(complete.daily, same(partial.daily));
      expect(fixture.requests.map((r) => r.$2), [
        'analytics/models',
        'model/options',
      ]);
      expect(
        fixture.requests.every((r) => r.$3['profile'] == 'client-work'),
        isTrue,
      );
    },
  );

  test(
    'analytics and picker share an in-flight catalog and refresh API prices',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      final held = Completer<Map<String, dynamic>>();
      fixture.override = (method, path, query, body) => path == 'model/options'
          ? held.future
          : Future.value(
              path == 'analytics/usage'
                  ? {'daily': []}
                  : {
                      'models': [row],
                    },
            );
      final profile = fixture.server.profile('personal');
      final picker = profile.modelCatalog.load();
      final reader = UsageAnalyticsReader(profile);
      final pending = reader.load(7);
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.requests.where((r) => r.$2 == 'model/options'),
        hasLength(1),
      );
      held.complete(subscriptionModelOptions());
      await picker;
      expect((await pending).models!.costs.total, 5);
      final updated = subscriptionModelOptions();
      fixture.apiPrices = subscriptionApiPrices(input: 20);
      fixture.override = (_, path, _, _) async => path == 'model/options'
          ? updated
          : path == 'analytics/usage'
          ? {'daily': []}
          : {
              'models': [row],
            };
      final refreshed = await reader.load(7, refresh: true);
      expect(refreshed.models!.costs.total, 7.5);
      expect(
        fixture.requests
            .where((r) => r.$2 == 'model/options')
            .last
            .$3['refresh'],
        '1',
      );
    },
  );

  test(
    'failed yearly cache is evicted and only failed aggregate is retried',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      var fail = true;
      fixture.override = (_, path, _, _) async {
        if (path == 'analytics/models') return {'models': []};
        if (fail) throw TimeoutException('Offline');
        return {'daily': []};
      };
      final reader = UsageAnalyticsReader(fixture.server.profile('personal'));
      final partial = await reader.load(365);
      expect(partial.models, isNotNull);
      expect(partial.dailyRetryable, isTrue);
      fail = false;
      fixture.requests.clear();
      final complete = await reader.load(365, retry: partial);
      expect(complete.models, same(partial.models));
      expect(complete.daily, isNotNull);
      expect(complete.needsRecovery, isFalse);
      expect(fixture.requests.map((r) => r.$2), ['analytics/usage']);
      expect(await reader.loadYear(), same(complete.daily));
      expect(fixture.requests.length, 1);
    },
  );

  test(
    'returned server dates and unknown counts survive without inferred boundaries',
    () {
      final data = UsageDaily.fromJson({
        'daily': [
          {'day': '2026-09-17', ...row},
          {'day': '2026-09-18', 'input_tokens': 3, 'output_tokens': 2},
        ],
      }, period: 1);
      expect(data.days.map((d) => d.id), ['2026-09-17', '2026-09-18']);
      expect(data.days.first.tokens.total, 1280000);
      expect(data.days.last.tokens.total, isNull);
      final empty = UsageDaily.fromJson({'daily': []}, period: 365);
      expect(empty.days, isEmpty);
      expect(empty.calendarDays, isEmpty);
      expect(() => UsageDaily.fromJson({}, period: 7), throwsFormatException);
      expect(
        () => UsageDaily.fromJson({
          'daily': [
            {'day': '2026-02-30'},
          ],
        }, period: 7),
        throwsFormatException,
      );
    },
  );
  for (final (name, dates) in [
    ('positive offset at UTC year end', ['2026-12-31', '2027-01-01']),
    ('negative offset partial first date', ['2025-12-30', '2025-12-31']),
    ('spring DST', ['2026-03-08', '2026-03-09']),
    ('fall DST', ['2026-11-01', '2026-11-02']),
    ('month rollover', ['2026-09-30', '2026-10-01']),
  ]) {
    test('$name preserves every returned date and its tokens', () {
      final daily = UsageDaily.fromJson({
        'daily': [
          for (final date in dates.reversed)
            {
              'day': date,
              'input_tokens': 100,
              'cache_read_tokens': 0,
              'output_tokens': 50,
            },
        ],
      }, period: 1);
      expect(daily.days.map((d) => d.id), dates);
      expect(daily.reportedDates, dates.toSet());
      expect(UsageTokens.sum(daily.days.map((d) => d.tokens)).total, 300);
      expect(daily.days.every((d) => d.date.isUtc && !d.isPlaceholder), isTrue);
      expect(daily.calendarDays.last.id, dates.last);
      expect(daily.calendarDays.first.isPlaceholder, isTrue);
      expect(daily.calendarDays.first.tokens.total, isNull);
    });
  }
  test(
    'year view preserves adjacent-year rows and marks only padding unknown',
    () {
      final daily = UsageDaily.fromJson({
        'daily': [
          {
            'day': '2025-12-31',
            'input_tokens': 0,
            'cache_read_tokens': 0,
            'output_tokens': 0,
          },
          {
            'day': '2027-01-01',
            'input_tokens': 100,
            'cache_read_tokens': 0,
            'output_tokens': 50,
          },
        ],
      }, period: 365);
      expect(daily.calendarDays.first.id, '2025-12-31');
      expect(daily.calendarDays.last.id, '2027-01-01');
      expect(daily.calendarDays.where((d) => d.isPlaceholder), isEmpty);
      expect(daily.days.first.tokens.total, 0);
      expect(daily.days[1].tokens.total, 0);
      expect(daily.reportedDates, {'2025-12-31', '2027-01-01'});
      expect(UsageTokens.sum(daily.days.map((d) => d.tokens)).total, 150);
    },
  );
  test(
    'model totals combine providers and auxiliary usage without adding reasoning',
    () {
      final data = UsageModels.fromJson({
        'models': [
          row,
          row,
          {...row, 'provider': 'openai', 'estimated_cost': 7},
        ],
      }, prices);
      expect(data.groups.length, 1);
      expect(data.costs.total, 17);
      expect(data.tokens.total, 3840000);
      expect(data.groups.single.model, 'gpt-6-astra');
      expect(data.groups.single.costs.total, 17);
      expect(data.groups.single.tokens.total, 3840000);
      expect(data.groups.single.rows.length, 3);
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
      fixture.override = withSubscriptionModelOptions(
        (_, path, _, _) =>
            path == 'analytics/models' ? models.future : daily.future,
      );
      final reader = UsageAnalyticsReader(
        fixture.server.profile('client-work'),
        now: () => now,
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
  test(
    'year read is shared, period boundary counts stay independent, refresh retries',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      var offline = false;
      fixture.override = (_, path, query, _) async {
        if (path == 'analytics/models') return {'models': []};
        if (offline && query['days'] == '365') throw StateError('Offline');
        return {
          'daily': [
            {
              'day': '2026-09-18',
              'input_tokens': int.parse(query['days']!),
              'cache_read_tokens': 0,
              'output_tokens': 0,
            },
          ],
        };
      };
      final reader = UsageAnalyticsReader(
        fixture.server.profile('client-work'),
        now: () => now,
      );
      final year = reader.loadYear();
      final week = await reader.load(7);
      expect((await year).days.last.tokens.total, 365);
      expect(week.daily!.days.last.tokens.total, 7);
      expect(fixture.requests.length, 3);
      final full = await reader.load(365);
      expect(identical(full.daily, await year), isTrue);
      expect(fixture.requests.length, 4);
      await reader.load(30);
      expect(
        fixture.requests
            .where((r) => r.$2 == 'analytics/usage' && r.$3['days'] == '365')
            .length,
        1,
      );
      offline = true;
      await expectLater(reader.loadYear(refresh: true), throwsStateError);
      expect((await reader.load(7)).daily, isNotNull);
      offline = false;
      expect(
        (await reader.loadYear(refresh: true)).days.last.tokens.total,
        365,
      );
      expect(
        fixture.requests.every((r) => r.$3['profile'] == 'client-work'),
        isTrue,
      );
    },
  );
}
