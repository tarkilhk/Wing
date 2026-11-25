import 'support/wing_client_identity_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/server_connection_status.dart';

import 'support/loopback_http_fixtures.dart';

void main() {
  useRealHttpClientsForLoopbackFixtures();
  for (final outcome in [
    'auth retry then success',
    'Hub timeout',
    'ordinary timeout',
  ]) {
    testWidgets('production administration deadline: $outcome', (tester) async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final started = Completer<void>();
      final release = Completer<void>();
      final endpoint = outcome == 'ordinary timeout'
          ? 'skills/hub/official'
          : 'skills/hub/updates';
      var logins = 0, calls = 0;
      late HttpServer http;
      await tester.runAsync(() async {
        http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        http.listen((request) async {
          try {
            if (request.uri.path == '/') {
              logins++;
              request.response.write(
                'window.__HERMES_SESSION_TOKEN__="fixture$logins";',
              );
            } else {
              expect(request.uri.path, '/api/$endpoint');
              expect(request.uri.queryParameters, {'profile': 'personal'});
              calls++;
              if (outcome == 'auth retry then success' && calls == 1) {
                request.response.statusCode = 401;
              } else {
                started.complete();
                await release.future;
                request.response.headers.contentType = ContentType.json;
                request.response.write(jsonEncode({'updates': []}));
              }
            }
            await request.response.close();
          } on SocketException {
            // A timed-out physical read aborts its socket before fixture release.
          }
        });
      });
      final status = ServerConnectionStatus('Deadline fixture');
      final server = AdministrationRepository.forConnection(
        ConnectionAccess(
          connection: SavedConnection(
            id: 'deadline',
            label: 'Deadline fixture',
            host: '127.0.0.1',
            port: http.port,
            dashboardPortOverride: http.port,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        'deadline-identity',
        connectionStatus: status,

        loadClientIdentity: loadTestWingClientIdentity,
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        server.close();
        status.dispose();
        await tester.runAsync(() => http.close(force: true));
        HttpOverrides.global = previous;
      });
      Object? failure;
      Map<String, dynamic>? result;
      server
          .request('GET', endpoint, {'profile': 'personal'}, null)
          .then<void>(
            (value) => result = value,
            onError: (Object error) => failure = error,
          );
      for (var i = 0; i < 100 && !started.isCompleted; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(started.isCompleted, isTrue);
      await tester.pump(const Duration(seconds: 46));
      if (outcome == 'ordinary timeout') {
        expect(failure, isA<TimeoutException>());
      } else {
        expect(
          failure,
          isNull,
          reason:
              'Both transport layers must permit a Hub check beyond 45 seconds',
        );
        expect(result, isNull);
        if (outcome == 'Hub timeout') {
          await tester.pump(const Duration(seconds: 75));
          expect(failure, isA<TimeoutException>());
        } else {
          release.complete();
          for (var i = 0; i < 100 && result == null && failure == null; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(failure, isNull);
          expect(result, {'updates': []});
          expect(logins, 2);
          expect(calls, 2);
        }
      }
      if (!release.isCompleted) release.complete();
      server.close();
      await tester.pump(const Duration(seconds: 15));
    });
  }
}
