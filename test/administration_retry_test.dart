import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/administration_health.dart';
import 'support/administration_fixture.dart';

void main() {
  testWidgets(
    'transient dashboard authentication failure retries before starting once',
    (tester) async {
      var logins = 0;
      var posts = 0;
      final client = DashboardClient(
        host: 'server',
        httpClient: MockClient((request) async {
          if (request.url.path == '/') {
            if (++logins == 1) return http.Response('', 503);
            return http.Response(
              'window.__HERMES_SESSION_TOKEN__="test";',
              200,
            );
          }
          posts++;
          return http.Response('{"name":"doctor","pid":7}', 200);
        }),
      );
      final server = AdministrationRepository(
        connectionId: 'server',
        connectionIdentity: 'server',
        connectionLabel: 'Server',
        gateway: (_) => throw UnimplementedError(),
        request: (_, endpoint, _, body) => client.apiPost(endpoint, body: body),
        close: client.close,
      );
      addTearDown(server.close);
      final result = server.startDiagnostic('ops/doctor');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect((await result)['pid'], 7);
      expect(logins, 2);
      expect(posts, 1);
    },
  );

  testWidgets('timed-out authentication cannot send a diagnostic later', (
    tester,
  ) async {
    final login = Completer<http.Response>();
    var posts = 0;
    final client = DashboardClient(
      host: 'server',
      httpClient: MockClient((request) async {
        if (request.url.path == '/') return login.future;
        posts++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    final result = expectLater(
      client.apiPost('ops/doctor'),
      throwsA(isA<DashboardRequestNotSentException>()),
    );
    await tester.pump(const Duration(seconds: 15));
    await result;
    login.complete(
      http.Response('window.__HERMES_SESSION_TOKEN__="test";', 200),
    );
    await tester.pump();
    expect(posts, 0);
  });

  for (final error in [
    TimeoutException('Response lost'),
    const SocketException('Connection reset', osError: OSError('reset', 104)),
    const DashboardHttpException(503, 'ops/security-audit'),
    const DashboardHttpException(403, 'ops/security-audit'),
  ]) {
    test(
      'does not replay an uncertain or rejected diagnostic: $error',
      () async {
        final fixture = AdministrationFixture();
        addTearDown(fixture.server.close);
        fixture.override = (_, _, _, _) async => throw error;
        await expectLater(
          fixture.server.startDiagnostic('ops/security-audit'),
          throwsA(same(error)),
        );
        expect(fixture.requests, hasLength(1));
      },
    );
  }

  testWidgets('profile reads retry transient errors and keep their scope', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    addTearDown(fixture.server.close);
    var attempts = 0;
    fixture.override = (_, _, _, _) async {
      if (++attempts < 3) throw TimeoutException('Offline');
      return {'model': 'ready'};
    };
    final result = fixture.server.profile('work').read('model/info');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect((await result)['model'], 'ready');
    expect(attempts, 3);
    expect(fixture.requests.every((r) => r.$3['profile'] == 'work'), isTrue);
  });

  testWidgets('diagnostic retries stop after three unsent attempts', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    addTearDown(fixture.server.close);
    fixture.override = (_, _, _, _) async => throw const SocketException(
      'Connection refused',
      osError: OSError('Connection refused', 111),
    );
    final result = expectLater(
      fixture.server.startDiagnostic('ops/doctor'),
      throwsA(isA<SocketException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await result;
    expect(fixture.requests, hasLength(3));
  });

  testWidgets('closing a connection cancels a pending retry', (tester) async {
    final fixture = AdministrationFixture();
    fixture.override = (_, _, _, _) async => throw TimeoutException('offline');
    final result = expectLater(
      fixture.server.read('model/info'),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    fixture.server.close();
    await tester.pump(const Duration(seconds: 1));
    await result;
    expect(fixture.requests, hasLength(1));
  });

  testWidgets('known diagnostic resumes polling after a longer outage', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    final health = AdministrationHealth(fixture.server);
    addTearDown(health.dispose);
    addTearDown(fixture.server.close);
    var online = false;
    fixture.override = (_, _, _, _) async {
      if (!online) throw TimeoutException('offline');
      return {
        'pid': 7,
        'running': false,
        'exit_code': 0,
        'lines': ['Done'],
      };
    };
    final generation = health.beginDiagnostic('ops/doctor')!;
    health.trackDiagnostic(
      'ops/doctor',
      const AdministrationAction('doctor', 7),
      generation: generation,
    );
    health.finishDiagnostic('ops/doctor', generation);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(health.diagnostics['ops/doctor']!.readError, isNotNull);
    online = true;
    await tester.pump(const Duration(seconds: 15));
    expect(health.diagnostics['ops/doctor']!.outcome, 'Completed');
    expect(health.diagnostics['ops/doctor']!.readError, isNull);
    expect(fixture.requests.every((r) => r.$1 == 'GET'), isTrue);
  });
}
