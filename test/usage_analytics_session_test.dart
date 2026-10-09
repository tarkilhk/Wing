import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/usage_analytics.dart';
import 'package:wing/core/services/usage_analytics.dart';
import 'package:wing/core/services/usage_analytics_session.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/server_connection_status.dart';

import 'support/administration_fixture.dart';

void main() {
  test(
    'Refresh reloads all unavailable analytics sections through real HTTP',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      var unavailable = true;
      final subscription = server.listen((request) async {
        requests.add(request.uri);
        request.response.headers.contentType = ContentType.json;
        if (unavailable) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'detail': 'Unavailable'}));
        } else {
          request.response.write(
            jsonEncode({
              if (request.uri.path == '/api/analytics/models')
                'models': [
                  {
                    'model': 'example',
                    'provider': 'example',
                    'estimated_cost': 2,
                    'input_tokens': 100,
                    'cache_read_tokens': 0,
                    'output_tokens': 10,
                  },
                ]
              else
                'daily': [
                  {
                    'day': '2026-10-09',
                    'input_tokens': 100,
                    'cache_read_tokens': 0,
                    'output_tokens': 10,
                  },
                ],
            }),
          );
        }
        await request.response.close();
      });
      final status = ServerConnectionStatus('Test');
      final repository = AdministrationRepository.forConnection(
        ConnectionAccess(
          connection: SavedConnection(
            id: 'analytics-recovery',
            label: 'Test',
            host: '127.0.0.1',
            port: server.port,
            dashboardPortOverride: server.port,
            dashboardProxied: true,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        'analytics-recovery-http',
        connectionStatus: status,
      );
      final owner = UsageAnalyticsSession(
        UsageAnalyticsReader(repository.profile('default')),
      );
      addTearDown(() async {
        owner.dispose();
        repository.close();
        status.dispose();
        await server.close(force: true);
        await subscription.cancel();
      });
      await owner.load();
      expect(owner.state.data!.models, isNull);
      expect(owner.state.data!.daily, isNull);
      expect(owner.state.data!.modelsError, 'Could not load model totals.');
      expect(owner.state.data!.dailyError, 'Could not load daily usage.');
      expect(owner.state.year, isNull);
      expect(owner.state.yearError, isNotNull);
      expect(owner.state.loading, isFalse);
      final failedCount = requests.length;
      unavailable = false;
      await owner.refresh();
      expect(owner.state.data!.models!.tokens.total, 110);
      expect(owner.state.data!.daily!.reportedDates, {'2026-10-09'});
      expect(owner.state.year!.reportedDates, {'2026-10-09'});
      expect(owner.state.data!.modelsError, isNull);
      expect(owner.state.data!.dailyError, isNull);
      expect(owner.state.yearError, isNull);
      expect(owner.state.loading, isFalse);
      expect(requests.skip(failedCount), hasLength(3));
      final retainedModels = owner.state.data!.models;
      final retainedDaily = owner.state.data!.daily;
      final retainedYear = owner.state.year;
      unavailable = true;
      await owner.refresh();
      expect(owner.state.data!.models, same(retainedModels));
      expect(owner.state.data!.daily, same(retainedDaily));
      expect(owner.state.year, same(retainedYear));
      expect(owner.state.data!.modelsError, isNotNull);
      expect(owner.state.data!.dailyError, isNotNull);
      expect(owner.state.yearError, contains('Showing retained activity'));
      expect(owner.state.loading, isFalse);
      unavailable = false;
      await owner.refresh();
      expect(owner.state.data!.modelsError, isNull);
      expect(owner.state.data!.dailyError, isNull);
      expect(owner.state.yearError, isNull);
      expect(
        requests.every((uri) => uri.queryParameters['profile'] == 'default'),
        isTrue,
      );
    },
  );

  for (final (name, ages, expected) in [
    (
      '30, 90 and 365 day totals remain distinct through real HTTP',
      [10, 60, 180],
      [(30, 1000, 1), (90, 7000, 2), (365, 25000, 3)],
    ),
    (
      'recent-only history has equal totals across correctly requested ranges',
      [10],
      [(30, 1000, 1), (90, 1000, 1), (365, 1000, 1)],
    ),
  ]) {
    test(name, () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      final now = DateTime.utc(2026, 10, 7, 12);
      final records = [
        for (final age in ages)
          (date: now.subtract(Duration(days: age)), tokens: age * 100),
      ];
      final subscription = server.listen((request) async {
        requests.add(request.uri);
        final days = int.parse(request.uri.queryParameters['days'] ?? '30');
        final selected = records.where(
          (record) => record.date.isAfter(now.subtract(Duration(days: days))),
        );
        final tokens = selected.fold(0, (sum, record) => sum + record.tokens);
        Map<String, dynamic> counts(int tokens) => {
          'input_tokens': tokens,
          'cache_read_tokens': 0,
          'output_tokens': 0,
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'period_days': days,
            if (request.uri.path == '/api/analytics/models')
              'models': [
                {
                  'model': 'example',
                  'provider': 'example',
                  'estimated_cost': tokens / 1000,
                  ...counts(tokens),
                },
              ]
            else
              'daily': [
                for (final record in selected)
                  {
                    'day': record.date.toIso8601String().substring(0, 10),
                    ...counts(record.tokens),
                  },
              ],
          }),
        );
        await request.response.close();
      });
      final status = ServerConnectionStatus('Test');
      final repository = AdministrationRepository.forConnection(
        ConnectionAccess(
          connection: SavedConnection(
            id: 'analytics',
            label: 'Test',
            host: '127.0.0.1',
            port: server.port,
            dashboardPortOverride: server.port,
            dashboardProxied: true,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        'analytics-http',
        connectionStatus: status,
      );
      final owner = UsageAnalyticsSession(
        UsageAnalyticsReader(repository.profile('butler'), now: () => now),
      );
      addTearDown(() async {
        owner.dispose();
        repository.close();
        status.dispose();
        await server.close(force: true);
        await subscription.cancel();
      });
      await owner.load();
      for (final (days, tokens, dates) in expected) {
        await owner.selectPeriod(days);
        expect(owner.state.data!.models!.tokens.total, tokens);
        expect(owner.state.data!.models!.costs.total, tokens / 1000);
        expect(owner.state.data!.daily!.reportedDates, hasLength(dates));
      }
      expect(
        requests.every((uri) => uri.queryParameters['profile'] == 'butler'),
        isTrue,
      );
      expect(
        requests
            .where((uri) => uri.path == '/api/analytics/models')
            .map((uri) => uri.queryParameters['days']),
        ['7', '30', '90', '365'],
      );
      final count = requests.length;
      await owner.selectPeriod(30);
      expect(owner.state.data!.models!.tokens.total, 1000);
      expect(requests, hasLength(count));
    });
  }

  test(
    'held previous period cannot replace the currently selected period',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      final held = Completer<Map<String, dynamic>>();
      final issued = Completer<void>();
      fixture.override = (_, path, query, _) async {
        if (path == 'analytics/usage') return {'daily': []};
        if (query['days'] == '7') {
          issued.complete();
          return held.future;
        }
        return {
          'models': [
            {'model': 'Current', 'provider': 'example', 'estimated_cost': 3},
          ],
        };
      };
      final owner = UsageAnalyticsSession(
        UsageAnalyticsReader(fixture.server.profile('personal')),
      );
      addTearDown(owner.dispose);
      final loading = owner.load();
      await issued.future;
      await owner.selectPeriod(30);
      final current = owner.state.data!;
      held.complete({'models': []});
      await loading;
      expect(owner.state.days, 30);
      expect(owner.state.data, same(current));
      expect(owner.state.data!.models!.rows.single.model, 'Current');
      await owner.selectPeriod(7);
      expect(owner.state.data!.models!.rows, isEmpty);
      expect(fixture.requests.where((r) => r.$3['days'] == '7'), hasLength(2));
      expect(
        fixture.requests.every((r) => r.$3['profile'] == 'personal'),
        isTrue,
      );
    },
  );

  test(
    'retired owner publishes no held result and starts no reentrant read',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      final held = Completer<Map<String, dynamic>>();
      fixture.override = (_, _, _, _) => held.future;
      final owner = UsageAnalyticsSession(
        UsageAnalyticsReader(fixture.server.profile('personal')),
      );
      var publications = 0;
      owner.addListener(() => publications++);
      final loading = owner.load();
      final published = publications;
      owner.dispose();
      held.complete({'models': [], 'daily': []});
      await loading;
      await owner.refresh();
      expect(publications, published);
      expect(owner.state.data, isNull);
      final before = fixture.requests.length;
      final reentrant = UsageAnalyticsSession(
        UsageAnalyticsReader(fixture.server.profile('personal')),
      );
      reentrant.addListener(reentrant.dispose);
      await reentrant.load();
      expect(fixture.requests.length, before);
    },
  );

  test(
    'Refresh forwards catalog refresh and publishes changed backend rates',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      final catalog = subscriptionModelOptions();
      fixture.override = (_, path, _, _) async => path == 'model/options'
          ? catalog
          : path == 'analytics/usage'
          ? {'daily': []}
          : {
              'models': [
                {
                  'provider': 'openai-codex',
                  'model': 'gpt-6-astra',
                  'input_tokens': 1000000,
                  'cache_read_tokens': 0,
                  'output_tokens': 0,
                },
              ],
            };
      final owner = UsageAnalyticsSession(
        UsageAnalyticsReader(fixture.server.profile('personal')),
      );
      addTearDown(owner.dispose);
      await owner.load();
      expect(owner.state.data!.models!.costs.total, 10);
      catalog['providers'][0]['pricing']['gpt-6-astra']['input'] = r'$20.00';
      await owner.refresh();
      expect(owner.state.data!.models!.costs.total, 20);
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
    'retirement cannot start a catalog read after held usage settles',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      final held = Completer<Map<String, dynamic>>();
      fixture.override = (_, path, _, _) => path == 'analytics/models'
          ? held.future
          : Future.value({'daily': []});
      final owner = UsageAnalyticsSession(
        UsageAnalyticsReader(fixture.server.profile('personal')),
      );
      final pending = owner.load();
      owner.dispose();
      held.complete({
        'models': [
          {'provider': 'openai-codex', 'model': 'gpt-6-astra'},
        ],
      });
      await pending;
      expect(fixture.requests.where((r) => r.$2 == 'model/options'), isEmpty);
    },
  );

  test(
    'issued usage facts detach producer data and reject consumer mutation',
    () {
      final raw = <String, dynamic>{
        'model': 'Original',
        'provider': 'example',
        'estimated_cost': 2,
        'input_tokens': 10,
        'cache_read_tokens': 2,
        'output_tokens': 3,
      };
      final models = UsageModels.fromJson({
        'models': [raw],
      }, null);
      raw['model'] = 'Changed';
      raw['input_tokens'] = 999;
      expect(models.rows.single.model, 'Original');
      expect(models.tokens.total, 15);
      expect(() => models.rows.clear(), throwsUnsupportedError);
      expect(() => models.groups.clear(), throwsUnsupportedError);
      expect(() => models.groups.single.rows.clear(), throwsUnsupportedError);
      expect(
        () => models.rows.single.tokenCounts.clear(),
        throwsUnsupportedError,
      );
      expect(() => models.tokens.values.clear(), throwsUnsupportedError);
      final daily = UsageDaily.fromJson({
        'daily': [
          {'day': '2026-10-05', ...raw},
        ],
      }, period: 7);
      expect(() => daily.days.clear(), throwsUnsupportedError);
      expect(
        () => daily.days.single.tokens.values.clear(),
        throwsUnsupportedError,
      );
    },
  );
}
