import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/administration_operation.dart';
import 'package:wing/core/services/administration_operation_session.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'support/administration_fixture.dart';

void main() {
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
