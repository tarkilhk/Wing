import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';

void main() {
  for (final download in [false, true]) {
    test(
      'dashboard ${download ? 'download' : 'API'} keeps token on its origin',
      () async {
        var redirectedRequests = 0;
        final destination = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final destinationSub = destination.listen((request) async {
          redirectedRequests++;
          request.response.write('{}');
          await request.response.close();
        });
        final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sourceSub = source.listen((request) async {
          if (request.uri.path == '/') {
            request.response.write(
              'window.__HERMES_SESSION_TOKEN__="synthetic-token";',
            );
          } else {
            expect(
              request.headers.value('x-hermes-session-token'),
              'synthetic-token',
            );
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(
              HttpHeaders.locationHeader,
              'http://localhost:${destination.port}/destination',
            );
          }
          await request.response.close();
        });
        final client = DashboardClient(host: '127.0.0.1', port: source.port);
        addTearDown(() async {
          client.close();
          await source.close(force: true);
          await destination.close(force: true);
          await sourceSub.cancel();
          await destinationSub.cancel();
        });
        await expectLater(
          download
              ? client.apiGetBytes('fs/download')
              : client.apiGet('profiles'),
          throwsA(
            isA<DashboardHttpException>().having(
              (error) => error.statusCode,
              'status',
              HttpStatus.found,
            ),
          ),
        );
        expect(redirectedRequests, 0);
      },
    );
  }
}
