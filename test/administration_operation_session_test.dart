import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/administration_operation.dart';
import 'package:wing/core/services/administration_operation_session.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'support/administration_fixture.dart';

void main() {
  testWidgets(
    'an outage keeps polling the captured run and cannot enable rerun',
    (tester) async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      var offline = false;
      var running = true;
      fixture.override = (_, _, _, _) async {
        if (offline) throw const SocketException('Offline');
        return {
          'name': 'doctor',
          'pid': 7,
          'running': running,
          'exit_code': running ? null : 0,
          'lines': [running ? 'Confirmed progress' : 'Completed output'],
        };
      };
      final operation = AdministrationOperationSession(
        fixture.server,
        const AdministrationAction('doctor', 7),
      );
      addTearDown(operation.dispose);
      await operation.refresh();
      final checkedAt = operation.state.observation.checkedAt;
      offline = true;
      final refresh = operation.refresh();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await refresh;
      expect(operation.state.observation.readError, isNotNull);
      expect(operation.state.observation.resultUnavailable, isFalse);
      expect(operation.state.observation.outcome, 'Running');
      expect(operation.state.canRunAgain, isFalse);
      expect(operation.state.observation.lines, ['Confirmed progress']);
      expect(operation.state.observation.checkedAt, checkedAt);
      offline = false;
      running = false;
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(operation.state.observation.readError, isNull);
      expect(operation.state.observation.outcome, 'Completed');
      expect(operation.state.canRunAgain, isTrue);
      expect(fixture.requests, hasLength(5));
      expect(
        fixture.requests.every(
          (request) =>
              request.$1 == 'GET' && request.$2 == 'actions/doctor/status',
        ),
        isTrue,
      );
    },
  );

  for (final invalid in [
    {'name': 'security-audit', 'pid': 8},
    {'pid': '8'},
    {'pid': null},
    {'pid': 8, 'running': 'false'},
    {
      'pid': 8,
      'lines': [1],
    },
    {'pid': 8, 'exit_code': 0},
  ]) {
    test(
      'malformed replacement $invalid cannot establish result loss',
      () async {
        final fixture = AdministrationFixture();
        addTearDown(fixture.server.close);
        fixture.override = (_, _, _, _) async => {
          'name': 'doctor',
          'pid': 7,
          'running': true,
          'exit_code': null,
          'lines': <String>[],
          ...invalid,
        };
        final operation = AdministrationOperationSession(
          fixture.server,
          const AdministrationAction('doctor', 7),
        );
        addTearDown(operation.dispose);
        await operation.refresh();
        expect(
          operation.state.observation.readError,
          contains('invalid operation result'),
        );
        expect(operation.state.observation.resultUnavailable, isFalse);
        expect(operation.state.canRunAgain, isFalse);
      },
    );
  }

  test(
    'retirement during loading notification revokes read and drains its lease',
    () async {
      final fixture = AdministrationFixture();
      final operation = AdministrationOperationSession(
        fixture.server,
        const AdministrationAction('doctor', 7),
      );
      operation.addListener(operation.dispose);
      await operation.refresh();
      expect(operation.state.retired, isTrue);
      expect(fixture.requests, isEmpty);
      fixture.server.close();
    },
  );

  test(
    'malformed status and replacement PID retain last confirmed output and time',
    () async {
      final fixture = AdministrationFixture();
      addTearDown(fixture.server.close);
      var status = <String, dynamic>{
        'name': 'doctor',
        'pid': 7,
        'running': false,
        'exit_code': 0,
        'lines': ['Own output'],
      };
      fixture.override = (_, _, _, _) async => status;
      final operation = AdministrationOperationSession(
        fixture.server,
        const AdministrationAction('doctor', 7),
      );
      addTearDown(operation.dispose);
      await operation.refresh();
      final checkedAt = operation.state.observation.checkedAt;
      status = {...status, 'running': 'false'};
      await operation.refresh();
      expect(operation.state.observation.readError, isNotNull);
      expect(operation.state.observation.checkedAt, checkedAt);
      expect(operation.state.observation.lines, ['Own output']);
      status = {
        ...status,
        'running': false,
        'pid': 8,
        'lines': ['Other run'],
      };
      await operation.refresh();
      expect(
        operation.state.observation.readError,
        contains('no longer available'),
      );
      expect(operation.state.observation.checkedAt, checkedAt);
      expect(operation.state.observation.lines, ['Own output']);
      expect(operation.action.pid, 7);
      expect(operation.state.observation.resultUnavailable, isTrue);
      expect(operation.state.observation.outcome, 'Completed');
    },
  );

  test('unacknowledged receipt cannot grant operation tracking authority', () {
    final fixture = AdministrationFixture();
    addTearDown(fixture.server.close);
    expect(
      () => AdministrationOperationSession.fromReceipt(fixture.server, {
        'ok': false,
        'name': 'skills-install',
        'pid': 7,
      }),
      throwsA(isA<AdministrationFailure>()),
    );
  });
}
