import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;
import 'support/loopback_http_fixtures.dart';

void main() {
  useRealHttpClientsForLoopbackFixtures();

  for (final action in ['save', 'cancel', 'timeout']) {
    testWidgets(
      'vault save-login server request shows a masked form: $action',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final appPreferences = AppPreferences(preferences);
        addTearDown(appPreferences.dispose);
        final host = Host();
        final controller = ProfileWorkspaceController(
          access: ConnectionAccess(
            connection: identityTestConnection(),
            dashboardOAuth: null,
          ),
          connectionIdentity: 'vault-wire-test',
          preferences: preferences,
          appPreferences: appPreferences,
          gatewayFactory: host.gateway,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final chat = await controller.createChat(canDispatch: () => true);
        await tester.pumpWidget(
          MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
        );

        Future<void> deliver(Map<String, dynamic> frame) async {
          await tester.runAsync(() async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            final connected = Completer<WebSocket>();
            final subscription = server
                .transform(WebSocketTransformer())
                .listen(connected.complete);
            final delivered = Completer<void>();
            final client = WsClient('http://127.0.0.1:${server.port}')
              ..onStreamEvent = (event) {
                host.gateways['a']!.onEvent!(event);
                delivered.complete();
              };
            try {
              await client.connect();
              final socket = await connected.future;
              socket.add(jsonEncode(frame));
              await delivered.future.timeout(const Duration(seconds: 2));
            } finally {
              client.close();
              await subscription.cancel();
              await server.close(force: true);
            }
          });
          await tester.pump();
          await tester.pump();
        }

        await deliver({
          'jsonrpc': '2.0',
          'id': 'srq-vault-test',
          'method': 'vault.save_login',
          'params': {
            'session_id': chat.runtime.runtimeId,
            'origin': 'https://example.test',
            'site': 'Example',
          },
        });
        expect(find.text('Save login for Example'), findsOneWidget);
        final password = find.byKey(const Key('sensitive-prompt-password'));
        expect(tester.widget<TextField>(password).obscureText, isTrue);
        expect(tester.widget<TextField>(password).enableSuggestions, isFalse);
        expect(
          host.calls.where((call) => call.$2 == 'request.answer'),
          isEmpty,
        );
        await tester.enterText(
          find.byKey(const Key('sensitive-prompt-field')),
          'fixture@example.test',
        );
        await tester.enterText(password, 'dummy-vault-password');
        await tester.pump();
        if (action == 'timeout') {
          await deliver({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {
              'type': 'request.cancel',
              'sid': chat.runtime.runtimeId,
              'payload': {
                'id': 'srq-vault-test',
                'method': 'vault.save_login',
                'reason': 'timeout',
              },
            },
          });
          expect(
            host.calls.where((call) => call.$2 == 'request.answer'),
            isEmpty,
          );
          expect(chat.runtime.error, contains('expired'));
        } else {
          final button = find.byKey(
            Key(
              action == 'save'
                  ? 'sensitive-prompt-submit'
                  : 'sensitive-prompt-cancel',
            ),
          );
          await tester.ensureVisible(button);
          await tester.pump();
          await tester.tap(button);
          await tester.pump();
          await tester.pump();
          final replies = host.calls.where(
            (call) => call.$2 == 'request.answer',
          );
          expect(replies, hasLength(1));
          expect(replies.single.$3['id'], 'srq-vault-test');
          expect(replies.single.$3['profile'], 'a');
          final value = (replies.single.$3['result'] as Map)['value'];
          if (action == 'save') {
            expect(jsonDecode(value as String), {
              'identifier': 'fixture@example.test',
              'password': 'dummy-vault-password',
            });
          } else {
            expect(value, '');
          }
        }
        expect(chat.runtime.secureInput, isNull);
        expect(password, findsNothing);
        expect(
          chat.composer.observation.text,
          isNot(contains('dummy-vault-password')),
        );
        expect(
          chat.reading.messages.toString(),
          isNot(contains('dummy-vault-password')),
        );
        expect(
          [
            for (final key in preferences.getKeys()) preferences.get(key),
          ].toString(),
          isNot(contains('dummy-vault-password')),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
