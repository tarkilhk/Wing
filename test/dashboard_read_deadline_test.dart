import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/models/hermes_profile.dart';

void main() {
  test('closing an image reader preserves shared in-flight login', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final loginStarted = Completer<void>();
    final finishLogin = Completer<void>();
    var logins = 0;
    final subscription = server.listen((request) async {
      if (request.uri.path == '/auth/password-login') {
        logins++;
        await utf8.decoder.bind(request).join();
        loginStarted.complete();
        await finishLogin.future;
        request.response.headers.add(
          'set-cookie',
          'hermes_session_at=shared; Path=/',
        );
        request.response.write('{}');
      } else {
        expect(request.headers.value('cookie'), 'hermes_session_at=shared');
        request.response.add(utf8.encode('image'));
      }
      await request.response.close();
    });
    final connection = DashboardClient(
      host: '127.0.0.1',
      port: server.port,
      username: 'fixture',
      password: 'fixture',
    );
    final first = connection.forkReads();
    final second = connection.forkReads();
    addTearDown(() async {
      if (!finishLogin.isCompleted) finishLogin.complete();
      first.close();
      second.close();
      connection.close();
      await server.close(force: true);
      await subscription.cancel();
    });
    final cancelled = expectLater(
      first.apiGetBytes('fs/download'),
      throwsA(isA<DashboardRequestNotSentException>()),
    );
    final surviving = second.apiGetBytes('fs/download');
    await loginStarted.future.timeout(const Duration(seconds: 2));
    first.close();
    finishLogin.complete();
    await cancelled;
    expect((await surviving).body, 'image');
    expect(logins, 1);
  });

  test(
    'image readers share renewal and retain newer cookies after a late 401',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var logins = 0;
      var rejected = 0;
      final renewedRead = Completer<void>();
      final subscription = server.listen((request) async {
        if (request.uri.path == '/auth/password-login') {
          logins++;
          await utf8.decoder.bind(request).join();
          request.response.headers.add(
            'set-cookie',
            'hermes_session_at=cookie-$logins; Path=/',
          );
          request.response.write('{}');
        } else if (request.headers.value('cookie') ==
            'hermes_session_at=cookie-1') {
          rejected++;
          if (rejected == 2) await renewedRead.future;
          request.response.statusCode = HttpStatus.unauthorized;
        } else {
          expect(request.headers.value('cookie'), 'hermes_session_at=cookie-2');
          if (!renewedRead.isCompleted) renewedRead.complete();
          request.response.add(utf8.encode('image'));
        }
        await request.response.close();
      });
      final connection = DashboardClient(
        host: '127.0.0.1',
        port: server.port,
        username: 'fixture',
        password: 'fixture',
      );
      final first = connection.forkReads();
      final second = connection.forkReads();
      addTearDown(() async {
        if (!renewedRead.isCompleted) renewedRead.complete();
        first.close();
        second.close();
        connection.close();
        await server.close(force: true);
        await subscription.cancel();
      });
      final responses = await Future.wait([
        first.apiGetBytes('fs/download'),
        second.apiGetBytes('fs/download'),
      ]).timeout(const Duration(seconds: 3));
      expect(responses.map((response) => response.body), ['image', 'image']);
      expect(rejected, 2);
      expect(logins, 2);
      expect((await first.apiGetBytes('fs/download')).body, 'image');
      expect(logins, 2);
    },
  );

  test(
    'an explicitly distinct file origin never receives workspace cookies',
    () async {
      final primary = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final files = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var primaryLogins = 0;
      var fileLogins = 0;
      final primarySubscription = primary.listen((request) async {
        if (request.uri.path == '/auth/password-login') {
          primaryLogins++;
          await utf8.decoder.bind(request).join();
          request.response.headers.add(
            'set-cookie',
            'hermes_session_at=primary; Path=/',
          );
        } else {
          expect(request.headers.value('cookie'), 'hermes_session_at=primary');
        }
        request.response.write('{}');
        await request.response.close();
      });
      final filesSubscription = files.listen((request) async {
        if (request.uri.path == '/auth/password-login') {
          fileLogins++;
          expect(request.headers.value('cookie'), isNull);
          await utf8.decoder.bind(request).join();
          request.response.headers.add(
            'set-cookie',
            'hermes_session_at=files; Path=/',
          );
          request.response.write('{}');
        } else {
          expect(request.headers.value('cookie'), 'hermes_session_at=files');
          request.response.add([1, 2, 3]);
        }
        await request.response.close();
      });
      final owner = ProfileGatewayConnection(
        ConnectionAccess(
          connection: SavedConnection(
            id: 'origins',
            label: 'Origins',
            host: '127.0.0.1',
            port: 1,
            apiKey: '',
            dashboardPortOverride: primary.port,
            dashboardUsername: 'fixture',
            dashboardPassword: 'fixture',
            desktopGatewayUrl: 'http://localhost:${files.port}',
          ),
          dashboardOAuth: null,
        ),
      );
      final gateway = owner.create(
        WorkspaceScope(connectionId: 'origins', profileName: 'default'),
      );
      addTearDown(() async {
        gateway.close();
        owner.close();
        await primary.close(force: true);
        await files.close(force: true);
        await primarySubscription.cancel();
        await filesSubscription.cancel();
      });
      await gateway.read('profiles');
      for (var i = 0; i < 3; i++) {
        final reader = owner.createFileReadClient();
        try {
          expect((await reader.apiGetBytes('fs/download')).bodyBytes, [
            1,
            2,
            3,
          ]);
        } finally {
          reader.close();
        }
      }
      expect(primaryLogins, 1);
      expect(fileLogins, 1);
    },
  );

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
