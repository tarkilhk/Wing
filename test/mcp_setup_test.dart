import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_mcp_setup_page.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/mcp_setup.dart';
import 'support/administration_fixture.dart';

void main() {
  late AdministrationFixture fixture;
  late List<(String, Map<String, dynamic>)> calls;
  setUp(() {
    fixture = AdministrationFixture();
    calls = [];
    fixture.rpcOverride = (method, params) async {
      calls.add((method, {...params}));
      return method.endsWith('.list')
          ? {'servers': []}
          : {
              'ok': true,
              'server': {'name': params['name'], ...params['config'] as Map},
            };
    };
  });

  test(
    'browser setup provisions the selected profile without a dashboard callback',
    () async {
      const setup = McpSetup(
        name: 'aspire',
        address: 'https://aspire-mcp.aspireapp.com/mcp',
      );
      final saved = await setup.save(fixture.server.profile('personal'));
      expect(saved['auth'], 'oauth');
      expect(calls.last.$1, 'mcp.servers.add');
      expect(calls.last.$2, {
        'profile': 'personal',
        'name': 'aspire',
        'config': {
          'url': 'https://aspire-mcp.aspireapp.com/mcp',
          'auth': 'oauth',
          'oauth': {},
        },
      });
      expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
    },
  );

  test(
    'bearer uses the stock secret provisioning field, not inline config',
    () async {
      await const McpSetup(
        name: 'key-service',
        address: 'https://example.test/mcp',
        authentication: McpAuthentication.bearer,
        token: 'fixture-token',
      ).save(fixture.server.profile('work'));
      expect(calls.last.$2['profile'], 'work');
      expect(calls.last.$2['bearer_token'], 'fixture-token');
      expect(
        jsonEncode(calls.last.$2['config']),
        isNot(contains('fixture-token')),
      );
    },
  );

  for (final subprocess in [false, true]) {
    test(
      '${subprocess ? 'subprocess env' : 'custom headers'} store profile secrets and only persist references',
      () async {
        await McpSetup(
          name: 'custom',
          address: subprocess ? 'npx' : 'https://example.test/mcp',
          subprocess: subprocess,
          arguments: const ['-y', 'example-mcp'],
          authentication: McpAuthentication.headers,
          credentials: {
            subprocess ? 'EXAMPLE_API_KEY' : 'X-Api-Key': 'fixture-secret',
          },
        ).save(fixture.server.profile('personal'));
        final writes = fixture.requests.where((r) => r.$1 == 'PUT').toList();
        expect(writes.length, 1);
        expect(writes.single.$2, 'env');
        expect(writes.single.$3, {'profile': 'personal'});
        expect(writes.single.$4!['value'], 'fixture-secret');
        final config = calls.last.$2['config'] as Map;
        final credentialMap = config[subprocess ? 'env' : 'headers'] as Map;
        expect(credentialMap.values.single, '\${${writes.single.$4!['key']}}');
        expect(jsonEncode(config), isNot(contains('fixture-secret')));
      },
    );
  }

  test(
    'pre-registered OAuth secret stays in Hermes env and callback/TLS settings are preserved',
    () async {
      await const McpSetup(
        name: 'registered',
        address: 'https://example.test/mcp',
        clientId: 'known-client',
        clientSecret: 'fixture-secret',
        scope: 'read write',
        redirect: 'http://localhost:43210/callback',
        clientCert: '/cert.pem',
        clientKey: '/key.pem',
        caPath: '/ca.pem',
      ).save(fixture.server.profile('personal'));
      final config = calls.last.$2['config'] as Map;
      expect(
        (config['oauth'] as Map)['redirect_uri'],
        'http://localhost:43210/callback',
      );
      expect(config['client_cert'], '/cert.pem');
      expect(config['ssl_verify'], '/ca.pem');
      expect(jsonEncode(config), isNot(contains('fixture-secret')));
    },
  );

  test(
    'duplicate connector never rotates credentials or overwrites its configuration',
    () async {
      fixture.rpcOverride = (_, _) async => {
        'servers': [
          {'name': 'existing'},
        ],
      };
      await expectLater(
        const McpSetup(
          name: 'existing',
          address: 'https://example.test/mcp',
          clientId: 'id',
          clientSecret: 'fixture-secret',
        ).save(fixture.server.profile('personal')),
        throwsA(isA<AdministrationFailure>()),
      );
      expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
    },
  );

  test(
    'malformed address and injected header values fail before any request',
    () async {
      for (final setup in [
        const McpSetup(
          name: 'example',
          address: 'https://user:password@example.test',
        ),
        const McpSetup(
          name: 'example',
          address: 'https://example.test',
          authentication: McpAuthentication.headers,
          credentials: {'Authorization': 'Bearer secret\r\nInjected: yes'},
        ),
      ]) {
        await expectLater(
          setup.save(fixture.server.profile('personal')),
          throwsA(isA<AdministrationFailure>()),
        );
      }
      expect(calls, isEmpty);
      expect(fixture.requests, isEmpty);
    },
  );

  testWidgets(
    'blank setup saves user-entered service details and browser sign-in',
    (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<Map<String, dynamic>>(
                        MaterialPageRoute(
                          builder: (_) => AdminMcpSetupPage(
                            profile: fixture.server.profile('personal'),
                          ),
                        ),
                      );
                },
                child: const Text('Open setup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open setup'));
      await tester.pumpAndSettle();
      expect(find.text('Use Aspire settings'), findsNothing);
      final name = find.widgetWithText(TextField, 'Connector name');
      final address = find.widgetWithText(TextField, 'MCP address');
      expect(tester.widget<TextField>(name).controller!.text, isEmpty);
      await tester.enterText(name, 'work-docs');
      await tester.ensureVisible(address);
      expect(tester.widget<TextField>(address).controller!.text, isEmpty);
      await tester.enterText(address, 'https://docs.example/mcp');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add and sign in'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add and sign in'));
      await tester.pumpAndSettle();
      expect(calls.last.$2['name'], 'work-docs');
      expect((calls.last.$2['config'] as Map)['auth'], 'oauth');
      expect(
        (calls.last.$2['config'] as Map)['url'],
        'https://docs.example/mcp',
      );
      expect(result?['name'], 'work-docs');
      expect(find.text('Open setup'), findsOneWidget);
    },
  );
}
