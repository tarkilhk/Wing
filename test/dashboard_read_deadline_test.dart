import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';

void main() {
  for (final stage in ['headers', 'body', 'authentication']) {
    test('stalled $stage times out and closes the actual socket', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<void>();
      final disconnected = Completer<void>();
      Socket? peer;
      final serverSub = server.listen((socket) {
        peer = socket;
        var responded = false;
        socket.listen(
          (_) {
            if (!accepted.isCompleted) accepted.complete();
            if (stage == 'body' && !responded) {
              responded = true;
              socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nx');
            }
          },
          onDone: () {
            if (!disconnected.isCompleted) disconnected.complete();
          },
          onError: (Object _) {
            if (!disconnected.isCompleted) disconnected.complete();
          },
        );
      });
      final client = DashboardClient(
        host: '127.0.0.1',
        port: server.port,
        proxied: stage != 'authentication',
        readTimeout: const Duration(milliseconds: 150),
      );
      addTearDown(() async {
        client.close();
        peer?.destroy();
        await serverSub.cancel();
        await server.close();
      });
      final request = client.apiGetBytes('fs/download', maxBytes: 1024);
      final assertion = expectLater(request, throwsA(isA<TimeoutException>()));
      await accepted.future.timeout(const Duration(seconds: 2));
      await assertion;
      await disconnected.future.timeout(const Duration(seconds: 2));
    });
  }

  test(
    'closing the owner cancels a pending download before its deadline',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<void>();
      final serverSub = server.listen((request) {
        accepted.complete();
      });
      final client = DashboardClient(
        host: '127.0.0.1',
        port: server.port,
        proxied: true,
        readTimeout: const Duration(seconds: 30),
      );
      addTearDown(() async {
        client.close();
        await server.close(force: true);
        await serverSub.cancel();
      });
      final assertion = expectLater(
        client.apiGetBytes('fs/download'),
        throwsA(isA<Exception>()),
      );
      await accepted.future.timeout(const Duration(seconds: 2));
      client.close();
      await assertion.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'a successful response and one authentication retry remain supported',
    () async {
      var tokens = 0;
      var reads = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSub = server.listen((request) async {
        if (request.uri.path == '/') {
          tokens++;
          request.response.write(
            'window.__HERMES_SESSION_TOKEN__="token-$tokens";',
          );
        } else {
          reads++;
          expect(
            request.headers.value('x-hermes-session-token'),
            'token-$tokens',
          );
          if (reads == 1) {
            request.response.statusCode = HttpStatus.unauthorized;
          } else {
            request.response.add(utf8.encode('report'));
          }
        }
        await request.response.close();
      });
      final client = DashboardClient(host: '127.0.0.1', port: server.port);
      addTearDown(() async {
        client.close();
        await server.close(force: true);
        await serverSub.cancel();
      });
      final response = await client.apiGetBytes('fs/download', maxBytes: 6);
      expect(response.body, 'report');
      expect(tokens, 2);
      expect(reads, 2);
    },
  );
}
