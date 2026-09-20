import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'support/gateway_application_requests.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/connection_setup_probe.dart';

void main() {
  for (final cancelOpening in [false, true]) {
    test(
      cancelOpening
          ? 'cancel closes a socket still waiting for gateway.ready'
          : 'real HTTP and WebSocket probe accepts empty history without sending a message',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final opened = Completer<void>();
        final closed = Completer<void>();
        final paths = <String>[];
        final socketMessages = <Object?>[];
        WebSocket? socket;
        final subscription = server.listen((request) async {
          paths.add(request.uri.path);
          if (request.uri.path == '/agent/api/ws') {
            expect(request.uri.queryParameters['ticket'], 'test-ticket');
            final active = await WebSocketTransformer.upgrade(request);
            socket = active;
            gatewayApplicationRequests(active).listen(
              socketMessages.add,
              onDone: () {
                if (!closed.isCompleted) closed.complete();
              },
            );
            opened.complete();
            if (!cancelOpening) {
              active.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'event',
                  'params': {'type': 'gateway.ready', 'payload': {}},
                }),
              );
            }
            return;
          }
          Object response;
          if (request.uri.path == '/agent/auth/password-login') {
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            expect(body['password'], ' exact password ');
            request.response.headers.add(
              'set-cookie',
              'hermes_session_at=test-session; Path=/',
            );
            response = <String, Object>{};
          } else {
            expect(
              request.headers.value('cookie'),
              'hermes_session_at=test-session',
            );
            response = switch (request.uri.path) {
              '/agent/api/profiles' => {
                'profiles': [
                  {'name': 'work'},
                ],
              },
              '/agent/api/profiles/active' => {
                'current': 'work',
                'active': 'work',
              },
              '/agent/api/auth/ws-ticket' => {'ticket': 'test-ticket'},
              '/agent/api/sessions' => {
                'sessions': <Object>[],
                'offset': int.parse(request.uri.queryParameters['offset']!),
                'limit': int.parse(request.uri.queryParameters['limit']!),
                'total': 0,
              },
              _ => throw StateError('Unexpected request ${request.uri.path}'),
            };
            if (request.uri.path == '/agent/api/sessions') {
              expect(request.uri.queryParameters['profile'], 'work');
            }
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
          await request.response.close();
        });
        final probe = ConnectionSetupProbe();
        try {
          final checking = probe.check(
            SavedConnection(
              id: 'transport-test',
              label: 'test',
              host: '127.0.0.1',
              port: server.port,
              apiKey: '',
              dashboardPortOverride: server.port,
              dashboardPrefix: '/agent',
              dashboardUsername: 'alex',
              dashboardPassword: ' exact password ',
            ),
          );
          await opened.future.timeout(const Duration(seconds: 5));
          if (cancelOpening) probe.cancel();
          await checking.timeout(const Duration(seconds: 5));
          await closed.future.timeout(const Duration(seconds: 5));
          expect(probe.verified, !cancelOpening);
          expect(socketMessages, isEmpty);
          expect(paths.contains('/agent/api/sessions'), !cancelOpening);
        } finally {
          probe.dispose();
          await socket?.close();
          await subscription.cancel();
          await server.close(force: true);
        }
      },
    );
  }
}
