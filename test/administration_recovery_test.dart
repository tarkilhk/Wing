import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_connectors_page.dart';
import 'package:wing/core/screens/administration/admin_defaults_page.dart';
import 'package:wing/core/screens/administration/admin_profiles_page.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/services/ws_client.dart';
import 'support/administration_fixture.dart';

Map<String, dynamic> profiles({String display = 'Shared root'}) => {
  'profiles': [
    {'name': 'default', 'is_default': true, 'display_name': display},
    {'name': 'personal'},
    {'name': 'work'},
  ],
};

void main() {
  for (final failure in [
    JsonRpcError(
      'reload.mcp',
      'MCP discovery failed: fixture reason',
      code: 5015,
    ),
    JsonRpcError('reload.mcp', 'Timeout', reason: 'request_timeout'),
    JsonRpcError(
      'reload.mcp',
      'Connection unavailable',
      reason: 'connection_closed',
    ),
  ]) {
    testWidgets(
      'MCP reconnection reports ${failure.reason ?? 'server error'} without retrying',
      (tester) async {
        final fixture = AdministrationFixture();
        fixture.rpcOverride = (_, _) async => throw failure;
        await tester.pumpWidget(
          MaterialApp(
            home: AdminConnectorsPage(
              profile: fixture.server.profile('personal'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reconnect MCP tools'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reconnect'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Your edits are kept'), findsNothing);
        expect(find.text('MCP tools reconnected.'), findsNothing);
        expect(
          find.textContaining(switch (failure.reason) {
            'request_timeout' => 'It may still be running',
            'connection_closed' => 'connection closed',
            _ => 'MCP discovery failed: fixture reason',
          }),
          findsOneWidget,
        );
        expect(fixture.rpcRequests, [('default', 'reload.mcp')]);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Reconnect MCP tools'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );
  }

  testWidgets('cancelling reconnection sends no request to Hermes', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    final requests = <Map<String, dynamic>>[];
    fixture.rpcOverride = (_, params) async {
      requests.add({...params});
      return {
        'status': 'confirm_required',
        'message': 'Reload invalidates the prompt cache.',
      };
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminConnectorsPage(profile: fixture.server.profile('personal')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect MCP tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('MCP tools reconnected.'), findsNothing);
  });

  testWidgets('MCP reconnection needs only one confirmation and one request', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    final requests = <Map<String, dynamic>>[];
    fixture.rpcOverride = (method, params) async {
      expect(method, 'reload.mcp');
      requests.add({...params});
      // Stock ReloadMcpParams forbids extra fields, including profile.
      if (params.keys.any(
        (key) => !{'session_id', 'confirm', 'always', 'rev'}.contains(key),
      )) {
        throw JsonRpcError(
          method,
          'Invalid params: profile: Extra inputs are not permitted',
          code: 4000,
        );
      }
      return params['confirm'] == true
          ? {'status': 'reloaded'}
          : {
              'status': 'confirm_required',
              'message': 'Reload invalidates the prompt cache.',
            };
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminConnectorsPage(profile: fixture.server.profile('personal')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect MCP tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Your edits are kept'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests, [
      {'confirm': true},
    ]);
    expect(find.text('MCP tools reconnected.'), findsOneWidget);
  });

  testWidgets(
    'MCP reconnection belongs to connectors and confirms server-wide scope',
    (tester) async {
      final fixture = AdministrationFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminConnectorsPage(
            profile: fixture.server.profile('personal'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Backend version'), findsNothing);
      await tester.tap(find.text('Reconnect MCP tools'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('all profiles on this server'),
        ),
        findsOneWidget,
      );
      expect(fixture.rpcRequests, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.rpcRequests, isEmpty);
      await tester.tap(find.text('Reconnect MCP tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(fixture.rpcRequests, [('default', 'reload.mcp')]);
      expect(find.text('MCP tools reconnected.'), findsOneWidget);
      expect(
        fixture.requests.any((request) => request.$2.contains('update')),
        isFalse,
      );
    },
  );

  testWidgets(
    'device-code recovery captures owner, avoids duplicate start and cancels exact session',
    (tester) async {
      final f = AdministrationFixture();
      f.override = (method, path, query, body) async {
        if (path == 'profiles') return profiles();
        if (path == 'profiles/active') return {'current': 'default'};
        if (path.endsWith('/start')) {
          return {
            'session_id': 'owned-session',
            'flow': 'device_code',
            'user_code': 'ABCD',
            'poll_interval': 60,
          };
        }
        if (method == 'DELETE') return {'ok': true};
        throw StateError('Unexpected request');
      };
      Future<void> show(String name) => tester.pumpWidget(
        MaterialApp(
          home: AdminProviderSignIn(
            profile: f.server.profile(name),
            provider: const {'id': 'provider-a', 'name': 'Provider A'},
            shared: false,
          ),
        ),
      );
      await show('personal');
      expect(f.requests, isEmpty);
      await tester.tap(find.text('Start sign-in'));
      await tester.pumpAndSettle();
      await show('work');
      expect(find.text('Server A / personal'), findsOneWidget);
      expect(find.text('Start sign-in'), findsNothing);
      expect(find.text('ABCD'), findsOneWidget);
      await tester.tap(find.text('Cancel sign-in'));
      await tester.pumpAndSettle();
      final writes = f.requests.where((r) => r.$1 != 'GET').toList();
      expect(writes.length, 2);
      expect(writes.last.$2, 'providers/oauth/sessions/owned-session');
      for (final r in writes) {
        expect(r.$3['profile'], 'personal');
        expect(r.$4!['profile'], 'personal');
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed cancellation retains recovery screen and allows retry', (
    tester,
  ) async {
    final f = AdministrationFixture();
    f.override = (method, path, query, body) async {
      if (path == 'profiles') return profiles();
      if (path.endsWith('/start')) {
        return {
          'session_id': 'pending',
          'flow': 'device_code',
          'poll_interval': 60,
        };
      }
      return {'ok': false};
    };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminProviderSignIn(
          profile: f.server.profile('default'),
          provider: const {'id': 'provider-a', 'name': 'Provider A'},
          shared: true,
        ),
      ),
    );
    await tester.tap(find.text('Start sign-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel sign-in'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Cancellation could not be confirmed'),
      findsOneWidget,
    );
    expect(find.text('Cancel sign-in'), findsOneWidget);
    expect(find.text('Server A / Shared accounts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'MCP unconfirmed enablement retains previous state without a success claim',
    (tester) async {
      final f = AdministrationFixture();
      f.override = (method, path, query, body) async {
        if (path == 'profiles') return profiles();
        if (path == 'mcp/servers') {
          return {
            'servers': [
              {'name': 'docs', 'enabled': false, 'transport': 'http'},
            ],
          };
        }
        return {'ok': true};
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminConnectorsPage(profile: f.server.profile('personal')),
        ),
      );
      await tester.pumpAndSettle();
      expect(f.requests.where((r) => r.$1 != 'GET'), isEmpty);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      expect(find.textContaining('could not be confirmed'), findsOneWidget);
      expect(find.textContaining('Saved for new sessions'), findsNothing);
      final write = f.requests.singleWhere((r) => r.$1 == 'PUT');
      expect(write.$3['profile'], 'personal');
      expect(write.$4, {'enabled': true, 'profile': 'personal'});
      expect(f.requests.any((r) => r.$2.endsWith('/test')), false);
    },
  );

  testWidgets(
    'default profile rename accepts display name and verifies unchanged canonical owner',
    (tester) async {
      final f = AdministrationFixture();
      var display = 'Shared root';
      f.override = (method, path, query, body) async {
        if (path == 'profiles') return profiles(display: display);
        if (path == 'profiles/active') return {'current': 'default'};
        if (method == 'PATCH') {
          display = body!['new_name'] as String;
          return {'ok': true, 'name': 'default'};
        }
        throw StateError('Unexpected request');
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminProfilesPage(
            server: f.server,
            onOpenProfile: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Manage Shared root'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'My shared account');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Profile renamed.'), findsOneWidget);
      expect(find.text('My shared account'), findsOneWidget);
      final write = f.requests.singleWhere((r) => r.$1 == 'PATCH');
      expect(write.$2, 'profiles/default');
      expect(write.$3, isEmpty);
    },
  );

  testWidgets(
    'unknown model flags hide unsupported reasoning controls and reset requires consent',
    (tester) async {
      final f = AdministrationFixture();
      f.override = (method, path, query, body) async {
        if (path == 'model/info') {
          return {'provider': 'provider-a', 'model': 'model-a'};
        }
        if (path == 'model/options') {
          return {
            'providers': [
              {
                'slug': 'provider-a',
                'models': ['model-a'],
              },
            ],
          };
        }
        if (path == 'model/auxiliary') {
          return {
            'tasks': [
              {'task': 'vision', 'provider': 'auto', 'model': ''},
            ],
          };
        }
        throw StateError('Unexpected request');
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDefaultsPage(profile: f.server.profile('personal')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reasoning and speed'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Reset all helper models'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset all helper models'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('credentials will be cleared'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.requests.where((r) => r.$1 != 'GET'), isEmpty);
    },
  );
}
