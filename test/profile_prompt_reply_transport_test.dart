import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

void main() {
  for (final kind in ['single', 'batch', 'secret', 'approval']) {
    test(
      '$kind reply passes strict validation over the real gateway socket',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final connected = Completer<WebSocket>();
        final advertised = Completer<void>();
        final replies = <Map<String, dynamic>>[];
        final subscription = server.listen((request) async {
          if (!WebSocketTransformer.isUpgradeRequest(request)) {
            request.response.write(
              'window.__HERMES_SESSION_TOKEN__="fixture-token";',
            );
            await request.response.close();
            return;
          }
          final socket = await WebSocketTransformer.upgrade(request);
          connected.complete(socket);
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {'type': 'gateway.ready', 'payload': {}},
            }),
          );
          socket.listen((raw) {
            final frame = jsonDecode(raw as String) as Map<String, dynamic>;
            final method = frame['method'];
            final params = frame['params'] as Map;
            if (method == 'client.capabilities') {
              expect(params, {'server_requests': true});
              advertised.complete();
              return;
            }
            replies.add(frame);
            // Upstream contracts/prompt_voice.py: neither reply is session-scoped.
            final allowed = method == 'clarify.lock'
                ? {'request_id', 'question_id', 'answer', 'profile'}
                : {'id', 'result', 'profile'};
            final unknown = params.keys.where((key) => !allowed.contains(key));
            socket.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': frame['id'],
                if (unknown.isNotEmpty)
                  'error': {
                    'code': 4000,
                    'message':
                        'invalid params: ${unknown.first}: Extra inputs are not permitted',
                  }
                else
                  'result': {
                    'status': 'ok',
                    if (method == 'clarify.lock') 'remaining': [],
                  },
              }),
            );
          });
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
        });
        SharedPreferences.setMockInitialValues({});
        final host = Host();
        final delivered = Completer<void>();
        final secondApprovalDelivered = Completer<void>();
        final connection = SavedConnection(
          id: 'reply-transport',
          label: 'Fixture',
          host: '127.0.0.1',
          port: server.port,
          dashboardPortOverride: server.port,
          apiKey: '',
        );
        final controller = ProfileWorkspaceController(
          connection: connection,
          connectionIdentity: 'reply-transport',
          preferences: await SharedPreferences.getInstance(),
          gatewayFactory: (WorkspaceScope scope) {
            final base = host.gateway(scope);
            final wire = ProfileGateway.forConnection(connection, scope);
            final gateway = ProfileGateway(
              scope: scope,
              discover: base.discover,
              get: base.read,
              connect: wire.connect,
              close: wire.close,
              rpc: (method, params) =>
                  {'clarify.lock', 'request.answer'}.contains(method)
                  ? wire.call(method, params)
                  : base.call(method, params),
            );
            wire.onEvent = (event) {
              gateway.onEvent?.call(event);
              if (event.data['request_id'] == 'queue-second' &&
                  !secondApprovalDelivered.isCompleted) {
                secondApprovalDelivered.complete();
              }
              if (!delivered.isCompleted) delivered.complete();
            };
            return gateway;
          },
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final chat = await controller.createChat();
        final socket = await connected.future;
        await advertised.future.timeout(const Duration(seconds: 2));
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'srq-fixture',
            'method': kind == 'approval'
                ? 'approval'
                : kind == 'secret'
                ? 'secret'
                : 'clarify',
            'params': {
              'session_id': chat.runtimeId,
              if (kind == 'approval') ...{
                'request_id': 'queue-fixture',
                'command': 'echo fixture',
                'choices': ['once', 'deny'],
              },
              if (kind == 'batch')
                'questions': [
                  {
                    'qid': 'q0',
                    'question': 'Which room?',
                    'choices': ['Bedroom'],
                  },
                ]
              else if (kind == 'single')
                'question': 'Which room?'
              else
                'env_var': 'FIXTURE_TOKEN',
            },
          }),
        );
        if (kind == 'approval') {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 'srq-second',
              'method': 'approval',
              'params': {
                'session_id': chat.runtimeId,
                'request_id': 'queue-second',
                'command': 'echo second',
                'choices': ['once', 'deny'],
              },
            }),
          );
          await secondApprovalDelivered.future.timeout(
            const Duration(seconds: 2),
          );
        }
        await delivered.future.timeout(const Duration(seconds: 2));
        if (kind == 'approval') {
          expect(chat.approval?['request_id'], 'queue-fixture');
          await controller.approve(
            chat,
            'once',
            requestId: chat.approval!['request_id'] as String,
          );
          expect(chat.approval?['request_id'], 'queue-second');
          expect((chat.approvals.position, chat.approvals.total), (2, 2));
          await controller.approve(chat, 'deny', requestId: 'queue-second');
          expect(chat.approval, isNull);
        } else if (kind == 'secret') {
          await controller.respondSensitivePrompt(
            chat,
            'dummy-fixture-value',
            expectedRequest: chat.sensitivePrompt!,
          );
          expect(chat.sensitivePrompt, isNull);
        } else {
          await controller.clarify(
            chat,
            'Bedroom',
            expectedRequest: chat.clarification,
          );
          expect(chat.clarification, isNull);
        }
        expect(replies, hasLength(kind == 'approval' ? 2 : 1));
        if (kind == 'approval') {
          expect(replies.last['params'], {
            'profile': 'a',
            'id': 'srq-second',
            'result': {'choice': 'deny'},
          });
        }
        expect(
          replies.first['method'],
          kind == 'batch' ? 'clarify.lock' : 'request.answer',
        );
        expect(replies.first['params'], {
          'profile': 'a',
          if (kind == 'batch') ...{
            'request_id': 'srq-fixture',
            'question_id': 'q0',
            'answer': 'Bedroom',
          } else ...{
            'id': 'srq-fixture',
            'result': kind == 'approval'
                ? {'choice': 'once'}
                : kind == 'secret'
                ? {'value': 'dummy-fixture-value'}
                : {'answer': 'Bedroom'},
          },
        });
      },
    );
  }
}
