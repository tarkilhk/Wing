import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/services/ws_client.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  for (final action in ['save', 'cancel', 'timeout']) {
    testWidgets(
      'vault save-login server request shows a masked form: $action',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final host = Host();
        final controller = ProfileWorkspaceController(
          connection: identityTestConnection(),
          connectionIdentity: 'vault-wire-test',
          preferences: preferences,
          gatewayFactory: host.gateway,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final chat = await controller.createChat();
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
            'session_id': chat.runtimeId,
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
              'sid': chat.runtimeId,
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
          expect(chat.error, contains('expired'));
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
        expect(chat.sensitivePrompt, isNull);
        expect(password, findsNothing);
        expect(chat.draft, isNot(contains('dummy-vault-password')));
        expect(
          chat.messages.toString(),
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
