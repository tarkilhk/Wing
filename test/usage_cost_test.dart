import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/usage_cost.dart';

void main() {
  final catalogueJson = {
    'version': 1,
    'currency': 'USD',
    'models': {
      'example': {
        'usd_per_million': {'input': 2, 'cached_input': 0.25, 'output': 10},
        'verified_on': '2026-09-18',
        'source': 'https://developers.openai.com/api/docs/pricing',
      },
    },
  };
  final prices = OpenAiPricingCatalog.fromJson(jsonEncode(catalogueJson));
  Map<String, dynamic> usage() => {
    'model': 'example',
    'provider': 'openai-codex',
    'input_tokens': 1000000,
    'cache_read_tokens': 2000000,
    'output_tokens': 100000,
    'reasoning_tokens': 75000,
    'estimated_cost': 0,
  };

  test(
    'prices disjoint buckets without subtracting cache or adding reasoning',
    () {
      final input = usage();
      final cost = ModelUsageCost.fromUsage(input, prices);
      expect(cost.inputCost, 2);
      expect(cost.cachedInputCost, 0.5);
      expect(cost.outputCost, 1);
      expect(cost.amount, 3.5);
      expect(cost.unavailable, isNull);
      expect(input['estimated_cost'], 0);
    },
  );

  test('uses provider identity, never zero cost or an OpenAI model name', () {
    for (final provider in [
      'openai',
      'openai-api',
      'openrouter',
      'local',
      null,
    ]) {
      for (final reported in [0, 19.5]) {
        final cost = ModelUsageCost.fromUsage(
          usage()..addAll({'provider': provider, 'estimated_cost': reported}),
          prices,
        );
        expect(cost.isApiEquivalent, isFalse);
        expect(cost.amount, reported);
        expect(cost.price, isNull);
      }
    }
    expect(
      ModelUsageCost.fromUsage(usage()..['estimated_cost'] = 99, prices).amount,
      3.5,
    );
  });

  test(
    'unknown IDs never inherit another model price or the included zero',
    () {
      for (final id in [
        'unknown',
        'example-pro',
        'example-900k',
        'openai/example',
      ]) {
        final cost = ModelUsageCost.fromUsage(usage()..['model'] = id, prices);
        expect(cost.amount, isNull);
        expect(cost.unavailable, UsageCostUnavailable.price);
      }
    },
  );

  test('requires all three valid counters, with explicit zero accepted', () {
    for (final key in ['input_tokens', 'cache_read_tokens', 'output_tokens']) {
      for (final invalid in [
        null,
        -1,
        0.5,
        '100',
        true,
        double.nan,
        double.infinity,
        1e100,
      ]) {
        final cost = ModelUsageCost.fromUsage(usage()..[key] = invalid, prices);
        expect(cost.amount, isNull, reason: '$key=$invalid');
        expect(cost.unavailable, UsageCostUnavailable.tokens);
      }
    }
    final zero = ModelUsageCost.fromUsage(
      usage()..addAll({
        'input_tokens': 0,
        'cache_read_tokens': 0,
        'output_tokens': 0,
      }),
      prices,
    );
    expect(zero.amount, 0);
    expect(zero.unavailable, isNull);
  });

  test('mixed subtotals and partial coverage count each supplied row once', () {
    final summary = UsageCostSummary([
      ModelUsageCost.fromUsage(usage(), prices),
      ModelUsageCost.fromUsage(usage(), prices), // separate auxiliary row
      ModelUsageCost.fromUsage({
        'provider': 'openai',
        'estimated_cost': 2,
      }, prices),
      ModelUsageCost.fromUsage(usage()..['model'] = 'unknown', prices),
    ]);
    expect(summary.isMixed, isTrue);
    expect(summary.isPartial, isTrue);
    expect(summary.pricedCount, 3);
    expect(summary.apiEquivalent, 7);
    expect(summary.reported, 2);
    expect(summary.total, 9);
    final unknown = UsageCostSummary([
      ModelUsageCost.fromUsage(usage()..['model'] = 'unknown', prices),
    ]);
    expect(unknown.total, isNull);
    expect(unknown.apiEquivalent, isNull);
    expect(UsageCostSummary([]).total, isNull);
  });

  test('small positive costs remain visibly different from zero', () {
    expect(formatUsageUsd(0), 'USD 0.00');
    expect(formatUsageUsd(0.000001), '< USD 0.01');
    expect(formatUsageUsd(0.00999), '< USD 0.01');
    expect(formatUsageUsd(0.01), 'USD 0.01');
    for (final invalid in [null, -1.0, double.nan, double.infinity]) {
      expect(formatUsageUsd(invalid), 'Unavailable');
    }
  });

  test(
    'bundled catalogue supplies documented rates for current supported models',
    () {
      final json = File('assets/pricing/openai.json').readAsStringSync();
      final catalogue = OpenAiPricingCatalog.fromJson(json);
      for (final id in (jsonDecode(json)['models'] as Map).keys) {
        final price = catalogue.priceFor(id)!;
        expect(price.input, greaterThan(0));
        expect(price.cachedInput, lessThan(price.input));
        expect(price.output, greaterThan(0));
        expect(price.source.path, endsWith('/$id'));
      }
      expect(catalogue.priceFor('gpt-6-astra'), isNotNull);
      expect(catalogue.priceFor('gpt-5.6-sol'), isNotNull);
      expect(catalogue.priceFor('gpt-5.3-codex-spark'), isNull);
    },
  );

  test(
    'rejects unsupported catalogue metadata and incomplete price entries',
    () {
      expect(
        () => OpenAiPricingCatalog.fromJson(
          jsonEncode({...catalogueJson, 'version': 2}),
        ),
        throwsFormatException,
      );
      expect(
        () => OpenAiPricingCatalog.fromJson(
          jsonEncode({...catalogueJson, 'currency': 'EUR'}),
        ),
        throwsFormatException,
      );
      final broken = jsonDecode(jsonEncode(catalogueJson));
      broken['models']['example']['usd_per_million'].remove('cached_input');
      expect(
        () => OpenAiPricingCatalog.fromJson(jsonEncode(broken)),
        throwsFormatException,
      );
    },
  );
}
