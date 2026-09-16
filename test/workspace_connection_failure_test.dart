import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/services/workspace_connection_failure.dart';

void main() {
  test('a real unanswered RPC is classified for connection recovery', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((_) {});
    });
    final client = WsClient(
      'http://127.0.0.1:${server.port}',
      token: 'local-test',
    );
    addTearDown(() async {
      client.close();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    await client.connect();
    await expectLater(
      client.send(
        'session.resume',
        {},
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(
        isA<JsonRpcError>()
            .having((error) => error.reason, 'reason', 'request_timeout')
            .having(isTemporaryWorkspaceFailure, 'recoverable', isTrue),
      ),
    );
  });
}
