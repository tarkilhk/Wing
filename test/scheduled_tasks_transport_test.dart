import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wing/core/services/connection_manager.dart';

void main() {
  testWidgets(
    'synchronous trigger stays pending beyond ordinary 45-second timeout',
    (tester) async {
      final response = Completer<http.Response>();
      final client = DashboardClient(
        host: 'hermes.test',
        port: 1,
        proxied: true,
        httpClient: MockClient((_) => response.future),
      );
      var completed = false;
      final pending = client
          .cronRequest('POST', 'cron/jobs/job/trigger', {
            'profile': 'personal',
          }, {})
          .then((v) {
            completed = true;
            return v;
          });
      await tester.pump();
      await tester.pump(const Duration(seconds: 46));
      expect(completed, false);
      response.complete(http.Response('{"id":"job"}', 200));
      await tester.pump();
      expect((await pending)['id'], 'job');
      client.close();
    },
  );
  test(
    'cron requests preserve prefix, encoded IDs, scope and structured errors',
    () async {
      final requests = <http.Request>[];
      final client = DashboardClient(
        host: 'hermes.test',
        port: 443,
        useHttps: true,
        pathPrefix: '/dashboard',
        proxied: true,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response('[{"id":"job"}]', 200);
          }
          return http.Response(
            jsonEncode({
              'detail': {'job_id': 'saved-job', 'error': 'registration failed'},
            }),
            424,
          );
        }),
      );
      addTearDown(client.close);
      final list = await client.cronRequest('GET', 'cron/jobs', {
        'profile': 'personal',
      }, null);
      expect(list['data'], [
        {'id': 'job'},
      ]);
      try {
        await client.cronRequest(
          'PUT',
          'cron/jobs/a%2Fb',
          {'profile': 'personal'},
          {
            'updates': {'name': 'New name'},
          },
        );
        fail('expected partial failure');
      } on CronHttpException catch (e) {
        expect(e.statusCode, 424);
        expect((e.detail as Map)['job_id'], 'saved-job');
      }
      expect(requests.last.url.path, '/dashboard/api/cron/jobs/a%2Fb');
      expect(requests.last.url.queryParameters, {'profile': 'personal'});
      expect(jsonDecode(requests.last.body), {
        'updates': {'name': 'New name'},
      });
    },
  );
  test(
    '401 refresh retries auth once without losing scope or payload',
    () async {
      var calls = 0;
      final client = DashboardClient(
        host: 'hermes.test',
        port: 1,
        proxied: true,
        httpClient: MockClient((r) async {
          calls++;
          expect(r.url.queryParameters['profile'], 'work');
          expect(jsonDecode(r.body), {'name': 'Weekly'});
          return http.Response(
            calls == 1 ? '{}' : '{"id":"new"}',
            calls == 1 ? 401 : 200,
          );
        }),
      );
      addTearDown(client.close);
      expect(
        (await client.cronRequest(
          'POST',
          'cron/jobs',
          {'profile': 'work'},
          {'name': 'Weekly'},
        ))['id'],
        'new',
      );
      expect(calls, 2);
    },
  );
}
