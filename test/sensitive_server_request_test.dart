import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/ws_client.dart';

void main() {
  for (final method in [
    'sudo',
    'secret',
    'vault.unlock_prompt',
    'vault.save_login',
    'vault.code',
  ]) {
    test('delivers server-initiated $method to the app', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final connected = Completer<WebSocket>();
      final subscription = server
          .transform(WebSocketTransformer())
          .listen(connected.complete);
      final events = <StreamEvent>[];
      final client = WsClient('http://127.0.0.1:${server.port}')
        ..onStreamEvent = events.add;
      try {
        await client.connect();
        final socket = await connected.future;
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'srq-0123456789ab',
            'method': method,
            'params': {
              'session_id': 'runtime-a',
              'origin': 'https://example.test',
              'site': 'Example test',
            },
          }),
        );
        // A subsequent RPC response establishes that the preceding request frame
        // was consumed, without relying on a timing-dependent sleep.
        socket.listen((raw) {
          final frame = jsonDecode(raw as String) as Map;
          socket.add(
            jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': {}}),
          );
        });
        await client.send('session.info', {'session_id': 'runtime-a'});
        expect(events, hasLength(1));
        expect(events.single.type, method);
        expect(events.single.sessionId, 'runtime-a');
        expect(events.single.data['request_id'], 'srq-0123456789ab');
        expect(events.single.data['site'], 'Example test');
      } finally {
        client.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    });
  }
}
