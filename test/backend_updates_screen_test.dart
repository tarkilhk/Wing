import 'package:wing/core/widgets/studio_selection_tile.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/connection.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/backend_updates_screen.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';

const _available = <String, dynamic>{
  'current_version': '1.0.0',
  'install_method': 'git',
  'behind': 2,
  'update_available': true,
  'can_apply': true,
};

class _Host {
  Map<String, dynamic> check = _available;
  Map<String, dynamic> status = {
    'running': true,
    'pid': 41,
    'exit_code': null,
    'lines': <String>[],
  };
  Map<String, dynamic> receipt = {
    'receipt': {
      'outcome': 'success',
      'pid': 41,
      'finished_at': '2026-09-12T12:00:00Z',
    },
  };
  Map<String, dynamic> post = {
    'ok': true,
    'name': 'hermes-update',
    'pid': 41,
    'action_id': 'action-1',
  };
  Completer<Map<String, dynamic>>? pendingCheck;
  final reads = <(String, Map<String, String>)>[];
  final posts = <(String, Map<String, dynamic>)>[];
  bool closed = false;

  ProfileGateway gateway(WorkspaceScope scope) => ProfileGateway(
    scope: scope,
    get: (endpoint, query) async {
      reads.add((endpoint, query));
      return switch (endpoint) {
        'health' => {'ok': true, 'version': check['current_version']},
        'hermes/update/check' => pendingCheck?.future ?? check,
        'hermes/update/receipt' => receipt,
        'actions/hermes-update/status' => status,
        _ => throw StateError('Unexpected read: $endpoint'),
      };
    },
    post: (endpoint, body) async {
      posts.add((endpoint, body));
      return post;
    },
    rpc: (_, _) async => <String, dynamic>{},
    discover: () async => const ProfileDiscovery(
      profiles: <HermesProfile>[],
      currentName: null,
      activeName: null,
    ),
    close: () => closed = true,
  );
}

SavedConnection _connection(
  String id, {
  String? host,
  int dashboardPort = 9119,
  String? prefix,
}) => SavedConnection(
  id: id,
  label: id.toUpperCase(),
  host: host ?? '$id.example',
  port: 8642,
  apiKey: '',
  dashboardPortOverride: dashboardPort,
  dashboardPrefix: prefix,
);

void main() {
  testWidgets(
    'exact endpoint duplicates are mutually exclusive at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hosts = {
        for (final id in ['a', 'b', 'c']) id: _Host(),
      };
      final connections = [
        _connection('a', host: 'EXAMPLE.com', prefix: '/gateway/'),
        _connection('b', host: 'example.COM', prefix: 'gateway'),
        _connection('c', host: 'example.com', dashboardPort: 9120),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: BackendUpdatesScreen(
              connections: connections,
              gatewayFactory: (connection, scope) =>
                  hosts[connection.id]!.gateway(scope),
            ),
          ),
        ),
      );
      await _tapSelection(tester, 'a');
      await _tapSelection(tester, 'b');
      await _tapShared(tester, 'backend-updates-check-selected');
      await tester.pumpAndSettle();
      _expectVersionChecks(hosts['a']!, 1);
      _expectVersionChecks(hosts['b']!, 2);

      await _tapSelection(tester, 'c');
      expect(_selected(tester, 'c'), isTrue);
      await _tapShared(tester, 'backend-updates-check-selected');
      await tester.pumpAndSettle();
      _expectVersionChecks(hosts['b']!, 3);
      _expectVersionChecks(hosts['c']!, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected hosts are checked and fresh refusal skips its write', (
    tester,
  ) async {
    final hosts = {'a': _Host(), 'b': _Host(), 'c': _Host()};
    final scopes = <WorkspaceScope>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BackendUpdatesScreen(
          connections: [_connection('a'), _connection('b'), _connection('c')],
          gatewayFactory: (connection, scope) {
            scopes.add(scope);
            return hosts[connection.id]!.gateway(scope);
          },
        ),
      ),
    );
    await _tapSelection(tester, 'a');
    await _tapSelection(tester, 'c');
    await _tapShared(tester, 'backend-updates-check-selected');
    await tester.pumpAndSettle();

    expect(hosts['a']!.reads.last.$1, 'hermes/update/check');
    expect(hosts['a']!.reads.last.$2, {'force': 'true', 'profile': 'default'});
    _expectVersionChecks(hosts['b']!, 1);
    _expectVersionChecks(hosts['c']!, 2);
    expect(scopes.map((scope) => scope.profileName), everyElement('default'));

    hosts['c']!.check = {..._available, 'update_available': false};
    await _tapShared(tester, 'backend-updates-update-selected');
    await tester.pumpAndSettle();
    expect(find.textContaining('A · http://a.example:9119'), findsOneWidget);
    expect(find.textContaining('C · http://c.example:9119'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Update selected').last);
    await tester.pumpAndSettle();

    expect(hosts['a']!.posts.single.$1, 'hermes/update?profile=default');
    expect(hosts['b']!.posts, isEmpty);
    expect(hosts['c']!.posts, isEmpty);
    await tester.scrollUntilVisible(
      find.text('The server reports no update is available.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('The server reports no update is available.'),
      findsOneWidget,
    );
  });

  testWidgets('automatic card check enables the selected batch action', (
    tester,
  ) async {
    final host = _Host();
    await tester.pumpWidget(
      MaterialApp(
        home: BackendUpdatesScreen(
          connections: [_connection('a')],
          gatewayFactory: (_, scope) => host.gateway(scope),
        ),
      ),
    );
    await _tapSelection(tester, 'a');
    _expectVersionChecks(host, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('backend-updates-update-selected')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('selected status refresh shows a correlated partial outcome', (
    tester,
  ) async {
    final host = _Host();
    await tester.pumpWidget(
      MaterialApp(
        home: BackendUpdatesScreen(
          connections: [_connection('a')],
          gatewayFactory: (_, scope) => host.gateway(scope),
        ),
      ),
    );
    await _tapSelection(tester, 'a');
    await _tapShared(tester, 'backend-updates-check-selected');
    await tester.pumpAndSettle();
    await _tapShared(tester, 'backend-updates-update-selected');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update selected').last);
    await tester.pumpAndSettle();

    host
      ..status = {
        'running': false,
        'pid': 41,
        'exit_code': 1,
        'lines': ['updated package', 'restart failed'],
        'action_id': 'action-1',
      }
      ..receipt = {
        'receipt': {
          'outcome': 'partial',
          'pid': 41,
          'finished_at': '2026-09-12T12:00:00Z',
        },
      };
    await _tapShared(tester, 'backend-updates-refresh-selected');
    await tester.pumpAndSettle();

    expect(
      find.text('The backend update completed only partially.'),
      findsOneWidget,
    );
    expect(find.text('Update logs'), findsOneWidget);
  });

  testWidgets('late check completion after close is ignored', (tester) async {
    final host = _Host()..pendingCheck = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: BackendUpdatesScreen(
          connections: [_connection('a')],
          gatewayFactory: (_, scope) => host.gateway(scope),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    host.pendingCheck!.complete(_available);
    await tester.pump();

    expect(host.closed, isTrue);
    expect(tester.takeException(), isNull);
  });
}

// Assert both independent reads, including their captured profile scope, so
// unrelated traffic cannot accidentally satisfy update-check count assertions.
void _expectVersionChecks(_Host host, int count) {
  expect(host.reads.map((read) => read.$1), [
    for (var i = 0; i < count; i++) ...['health', 'hermes/update/check'],
  ]);
  for (final read in host.reads) {
    expect(read.$2, {
      'profile': 'default',
      if (read.$1 == 'hermes/update/check') 'force': 'true',
    });
  }
}

bool _selected(WidgetTester tester, String id) => tester
    .widget<StudioSelectionTile>(
      find.byKey(ValueKey('backend-update-select-$id')),
    )
    .value;

Future<void> _tapSelection(WidgetTester tester, String id) async {
  final key = ValueKey('backend-update-select-$id');
  await _scrollTo(tester, key);
  final target = find.byKey(key);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _tapShared(WidgetTester tester, String key) async {
  await _scrollToTop(tester);
  await tester.tap(find.byKey(ValueKey(key)));
}

Future<void> _scrollTo(WidgetTester tester, ValueKey<String> key) async {
  final target = find.byKey(key);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 5000));
  await tester.pumpAndSettle();
}
