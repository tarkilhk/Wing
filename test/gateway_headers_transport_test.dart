import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'dashboard sends headers through login with managed auth precedence',
    () async {
      final requests = <http.Request>[];
      final client = DashboardClient(
        host: 'gateway.example',
        useHttps: true,
        username: 'user',
        password: 'password',
        gatewayHeaders: const {
          'CF-Access-Client-Id': 'client-id',
          'CF-Access-Client-Secret': 'client-secret',
        },
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/auth/password-login')) {
            return _response(
              {},
              headers: {'set-cookie': 'hermes_session_at=session; Path=/'},
            );
          }
          if (request.url.path.endsWith('/api/auth/ws-ticket')) {
            return _response({'ticket': 'ticket'});
          }
          return _response({'profiles': <Object>[]});
        }),
      );
      addTearDown(client.close);

      await client.apiGet('profiles');
      expect(await client.mintWebSocketTicket(), 'ticket');

      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.followRedirects, isFalse);
        expect(request.headers['cf-access-client-id'], 'client-id');
        expect(request.headers['cf-access-client-secret'], 'client-secret');
        expect(request.headers['content-type'], 'application/json');
      }
      expect(requests.first.headers, isNot(contains('cookie')));
      expect(requests[1].headers['cookie'], 'hermes_session_at=session');
      expect(requests.last.headers['cookie'], 'hermes_session_at=session');
    },
  );

  test(
    'dashboard sends headers through token fetch and proxied APIs',
    () async {
      final tokenRequests = <http.Request>[];
      final tokenClient = DashboardClient(
        host: 'gateway.example',
        useHttps: true,
        gatewayHeaders: const {'X-Access-Secret': 'secret'},
        httpClient: MockClient((request) async {
          tokenRequests.add(request);
          if (request.url.path == '/') {
            return http.Response(
              'window.__HERMES_SESSION_TOKEN__="session-token";',
              200,
            );
          }
          return _response({'profiles': <Object>[]});
        }),
      );
      addTearDown(tokenClient.close);
      await tokenClient.apiGet('profiles');

      expect(tokenRequests, hasLength(2));
      expect(tokenRequests.first.headers['x-access-secret'], 'secret');
      expect(
        tokenRequests.first.headers,
        isNot(contains('x-hermes-session-token')),
      );
      expect(
        tokenRequests.last.headers['x-hermes-session-token'],
        'session-token',
      );

      late http.Request proxiedRequest;
      final proxiedClient = DashboardClient(
        host: 'gateway.example',
        useHttps: true,
        proxied: true,
        gatewayHeaders: const {'X-Access-Secret': 'secret'},
        httpClient: MockClient((request) async {
          proxiedRequest = request;
          return _response({'profiles': <Object>[]});
        }),
      );
      addTearDown(proxiedClient.close);
      await proxiedClient.apiGet('profiles');

      expect(proxiedRequest.headers['x-access-secret'], 'secret');
      expect(proxiedRequest.headers, isNot(contains('cookie')));
      expect(proxiedRequest.headers, isNot(contains('x-hermes-session-token')));
    },
  );

  test('dashboard does not forward custom headers across a redirect', () async {
    var redirectedRequests = 0;
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final destinationSub = destination.listen((request) async {
      redirectedRequests++;
      await request.response.close();
    });
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sourceSub = source.listen((request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${destination.port}/stolen',
        );
      await request.response.close();
    });
    addTearDown(() async {
      await source.close(force: true);
      await destination.close(force: true);
      await sourceSub.cancel();
      await destinationSub.cancel();
    });
    final client = DashboardClient(
      host: '127.0.0.1',
      port: source.port,
      proxied: true,
      gatewayHeaders: const {'X-Access-Secret': 'secret'},
    );
    addTearDown(client.close);

    await expectLater(
      client.apiGet('profiles'),
      throwsA(
        isA<DashboardHttpException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.found,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(redirectedRequests, 0);
  });

  test('websocket sends headers on its direct handshake', () async {
    final requestSeen = Completer<HttpRequest>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      requestSeen.complete(request);
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.done;
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });
    final client = WsClient(
      'http://127.0.0.1:${server.port}',
      ticket: 'ticket',
      gatewayHeaders: const {'X-Access-Secret': 'secret'},
    );
    addTearDown(client.close);

    await client.connect();
    final request = await requestSeen.future;
    expect(request.uri.path, '/api/ws');
    expect(request.uri.queryParameters['ticket'], 'ticket');
    expect(request.headers.value('x-access-secret'), 'secret');
  });

  test('websocket does not forward headers across a redirect', () async {
    var redirectedRequests = 0;
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final destinationSub = destination.listen((request) async {
      redirectedRequests++;
      await request.response.close();
    });
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sourceSub = source.listen((request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${destination.port}/api/ws',
        );
      await request.response.close();
    });
    addTearDown(() async {
      await source.close(force: true);
      await destination.close(force: true);
      await sourceSub.cancel();
      await destinationSub.cancel();
    });
    final client = WsClient(
      'http://127.0.0.1:${source.port}',
      gatewayHeaders: const {'X-Access-Secret': 'secret'},
    );
    addTearDown(client.close);

    await expectLater(client.connect(), throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    expect(redirectedRequests, 0);
  });
}

http.Response _response(
  Map<String, dynamic> body, {
  Map<String, String> headers = const {},
}) => http.Response(jsonEncode(body), 200, headers: headers);
