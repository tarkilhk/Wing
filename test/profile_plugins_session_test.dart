import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/administration/admin_plugins_page.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_plugins_session.dart';
import 'support/administration_fixture.dart';

class _PluginsFixture {
  final http = AdministrationFixture();
  final calls = <Map<String, dynamic>>[];
  final row = <String, dynamic>{
    'key': 'tools/review',
    'name': 'Review',
    'source': 'user',
    'description': 'Review tools',
    'status': 'disabled',
  };
  bool loseReadback = false, unknownReceipt = false, invalid = false;
  int connects = 0;
  Completer<void>? connected, release;
  late final AdministrationRepository server = AdministrationRepository(
    connectionId: http.id,
    connectionIdentity: '${http.id}-endpoint',
    connectionLabel: http.id,
    request: http.send,
    settingsWrite: (_, _, _, _) async =>
        throw StateError('Unexpected config write'),
    ownedMutation: (_, _, _, _, _, _) async =>
        throw StateError('Unexpected HTTP write'),
    gateway: (_) => gateway,
  );
  late final ProfileGateway gateway = ProfileGateway(
    scope: WorkspaceScope(connectionId: http.id, profileName: 'work'),
    get: (_, _) async => throw StateError('Unexpected gateway HTTP read'),
    discover: () => server.discover(),
    connect: () async {
      connects++;
      if (connects == 3 && release != null) {
        connected!.complete();
        await release!.future;
      }
    },
    rpc: (method, params) async {
      expect(method, 'plugins.manage');
      calls.add({...params});
      if (params['action'] == 'list') {
        if (loseReadback && calls.any((call) => call['action'] == 'toggle')) {
          throw StateError('Readback unavailable');
        }
        return {
          'plugins': [
            invalid ? {...row, 'status': 7} : row,
          ],
        };
      }
      expect(params, {
        'profile': 'work',
        'action': 'toggle',
        'key': 'tools/review',
        'enable': true,
      });
      row['status'] = 'enabled';
      if (unknownReceipt) {
        return {'name': 'tools/review'};
      }
      return {
        'ok': true,
        'name': 'tools/review',
        'unchanged': false,
        'restart_required': false,
        'gateway_reloaded': true,
        'plugin': row,
      };
    },
  );
}

void main() {
  test(
    'immutable captured inventory and ACK survive unavailable readback without replay',
    () async {
      final fixture = _PluginsFixture();
      final session = ProfilePluginsSession(fixture.server.profile('work'));
      addTearDown(session.dispose);
      await session.refresh();
      final original = session.state;
      expect(() => original.rows.clear(), throwsUnsupportedError);
      fixture.row['description'] = 'Changed outside the snapshot';
      expect(original.rows.single.description, 'Review tools');
      fixture.loseReadback = true;
      await session.toggle(original.rows.single, true);
      expect(fixture.row['status'], 'enabled');
      expect(session.state.acknowledgement!.key, 'tools/review');
      expect(session.state.acknowledgement!.enabled, isTrue);
      expect(session.state.error, contains('saved'));
      expect(session.state.verified, isFalse);
      final count = fixture.calls.length;
      await session.toggle(session.state.rows.single, true);
      expect(fixture.calls, hasLength(count));
      fixture.loseReadback = false;
      await session.refresh();
      expect(session.state.rows.single.enabled, isTrue);
      expect(session.state.error, isNull);
      expect(original.rows.single.enabled, isFalse);
      expect(
        fixture.calls.where((call) => call['action'] == 'toggle'),
        hasLength(1),
      );
      expect(fixture.calls.every((call) => call['profile'] == 'work'), isTrue);
    },
  );

  test(
    'malformed observation and an unknown dispatched result require a fresh read',
    () async {
      final fixture = _PluginsFixture()..invalid = true;
      final session = ProfilePluginsSession(fixture.server.profile('work'));
      addTearDown(session.dispose);
      await session.refresh();
      expect(session.state.verified, isFalse);
      expect(session.state.rows, isEmpty);
      expect(session.state.error, contains('invalid response'));
      fixture.invalid = false;
      await session.refresh();
      fixture.unknownReceipt = true;
      await session.toggle(session.state.rows.single, true);
      expect(fixture.row['status'], 'enabled');
      expect(session.state.acknowledgement, isNull);
      expect(session.state.error, contains('could not be confirmed'));
      expect(session.state.canToggle, isFalse);
      await session.toggle(session.state.rows.single, true);
      expect(
        fixture.calls.where((call) => call['action'] == 'toggle'),
        hasLength(1),
      );
      await session.refresh();
      expect(session.state.verified, isTrue);
      expect(session.state.rows.single.enabled, isTrue);
      expect(session.state.acknowledgement, isNull);
    },
  );

  test(
    'retirement during connection admission prevents physical plugin mutation',
    () async {
      final fixture = _PluginsFixture();
      final session = ProfilePluginsSession(fixture.server.profile('work'));
      await session.refresh();
      fixture.connected = Completer<void>();
      fixture.release = Completer<void>();
      final pending = session.toggle(session.state.rows.single, true);
      await fixture.connected!.future;
      final published = session.state;
      session.dispose();
      fixture.server.close();
      fixture.release!.complete();
      await pending;
      expect(
        fixture.calls.where((call) => call['action'] == 'toggle'),
        isEmpty,
      );
      expect(fixture.row['status'], 'disabled');
      expect(identical(session.state, published), isTrue);
    },
  );

  testWidgets(
    'plugin route mounts, toggles and refreshes its captured profile',
    (tester) async {
      final fixture = _PluginsFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AdminPluginsPage(
                      createSession: () =>
                          ProfilePluginsSession(fixture.server.profile('work')),
                    ),
                  ),
                ),
                child: const Text('Open plugins'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open plugins'));
      await tester.pumpAndSettle();
      expect(find.text('Review'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(
        fixture.calls.where((call) => call['action'] == 'toggle'),
        hasLength(1),
      );
      expect(fixture.calls.every((call) => call['profile'] == 'work'), isTrue);
      expect(
        fixture.http.requests.where((request) => request.$1 != 'GET'),
        isEmpty,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      final before = fixture.calls.length;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(fixture.calls, hasLength(before));
      expect(tester.takeException(), isNull);
      fixture.server.close();
    },
  );
}
