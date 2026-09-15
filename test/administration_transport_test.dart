import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wing/core/services/connection_manager.dart';

void main() {
  test(
    'DELETE keeps scoped body across authentication retry and preserves rejected result',
    () async {
      var logins = 0;
      var deletes = 0;
      final client = DashboardClient(
        host: 'hermes.test',
        port: 9119,
        username: 'owner',
        password: 'fixture',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            logins++;
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie': 'hermes_session_at=fixture$logins; Path=/',
              },
            );
          }
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/env');
          expect(request.url.queryParameters['profile'], 'personal');
          expect(jsonDecode(request.body), {
            'key': 'SERVICE_KEY',
            'profile': 'personal',
          });
          deletes++;
          return deletes == 1
              ? http.Response('expired', 401)
              : http.Response('{"ok":false}', 200);
        }),
      );
      addTearDown(client.close);
      final result = await client.apiDeleteResult(
        'env?profile=personal',
        body: {'key': 'SERVICE_KEY', 'profile': 'personal'},
      );
      expect(result['ok'], false);
      expect(deletes, 2);
      expect(logins, 2);
    },
  );
}
