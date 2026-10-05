import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/usage_analytics.dart';
import 'package:wing/core/services/usage_analytics.dart';
import 'package:wing/core/services/usage_analytics_session.dart';

import 'support/administration_fixture.dart';

void main() {
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
