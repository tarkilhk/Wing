import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/administration_logs.dart';
import 'package:wing/core/services/administration_logs_session.dart';
import 'support/administration_fixture.dart';

void main() {
  test(
    'a newer submitted query owns the log observation after a held older read',
    () async {
      final fixture = AdministrationFixture();
      final session = AdministrationLogsSession(fixture.server);
      addTearDown(session.dispose);
      final older = Completer<Map<String, dynamic>>();
      final currentLines = ['ERROR Current log'];
      var malformed = false;
      fixture.override = (method, path, query, body) async {
        expect(method, 'GET');
        expect(path, 'logs');
        expect(body, isNull);
        expect(query.containsKey('profile'), isFalse);
        if (query['file'] == 'agent') return older.future;
        return {
          'file': malformed ? 'gateway' : query['file'],
          'lines': currentLines,
        };
      };
      final pending = session.refresh();
      await session.selectFile(AdministrationLogFile.errors);
      await session.selectLevel(AdministrationLogLevel.error);
      await session.search('  Timeout  ');
      expect(fixture.requests.last.$3, {
        'file': 'errors',
        'lines': '100',
        'level': 'ERROR',
        'search': '  Timeout  ',
      });
      final accepted = session.state;
      expect(accepted.snapshot!.lines, ['ERROR Current log']);
      currentLines.add('Later alias mutation');
      expect(accepted.snapshot!.lines, ['ERROR Current log']);
      expect(() => accepted.snapshot!.lines.clear(), throwsUnsupportedError);
      older.complete({
        'file': 'agent',
        'lines': [7],
      });
      await pending;
      expect(identical(session.state, accepted), isTrue);
      expect(session.state.loading, isFalse);
      expect(session.state.error, isNull);
      malformed = true;
      await session.refresh();
      expect(session.state.snapshot, isNull);
      expect(session.state.error, 'The server returned an invalid response.');
      expect(session.state.canRecoverRead, isFalse);
      malformed = false;
      currentLines.clear();
      await session.refresh();
      expect(session.state.snapshot!.lines, isEmpty);
      expect(session.state.error, isNull);
      expect(accepted.snapshot!.lines, ['ERROR Current log']);
    },
  );

  test(
    'listener retirement revokes unsent reads and held reads publish nothing after retirement',
    () async {
      final fixture = AdministrationFixture();
      final retired = AdministrationLogsSession(fixture.server);
      retired.addListener(retired.dispose);
      await retired.refresh();
      expect(fixture.requests, isEmpty);
      retired.dispose();

      final session = AdministrationLogsSession(fixture.server);
      final response = Completer<Map<String, dynamic>>();
      fixture.override = (_, _, _, _) => response.future;
      var publications = 0;
      session.addListener(() => publications++);
      final pending = session.refresh();
      expect(fixture.requests.single.$3, {'file': 'agent', 'lines': '100'});
      final before = publications;
      session.dispose();
      response.complete({
        'file': 'agent',
        'lines': ['Late result'],
      });
      await pending;
      await session.search('No dispatch');
      expect(publications, before);
      expect(fixture.requests, hasLength(1));
      // A consumer borrows the repository rather than closing it.
      fixture.override = (_, _, _, _) async => {'file': 'gateway', 'lines': []};
      final next = AdministrationLogsSession(fixture.server);
      addTearDown(next.dispose);
      await next.selectFile(AdministrationLogFile.gateway);
      expect(next.state.snapshot!.lines, isEmpty);
    },
  );
}
