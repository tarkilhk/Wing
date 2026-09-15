import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';

void main() {
  test('delivers a server-initiated clarify request to the app', () async {
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
          'method': 'clarify',
          'params': {
            'session_id': 'runtime-a',
            'questions': [
              {
                'qid': 'q0',
                'question':
                    'Which space should the first purifier protect during haze?',
                'choices': ['One closed bedroom', 'Living room or study'],
                'multi_select': false,
              },
            ],
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
      expect(events.single.type, 'clarify');
      expect(events.single.sessionId, 'runtime-a');
      expect(events.single.data['request_id'], 'srq-0123456789ab');
      expect((events.single.data['questions'] as List).single['qid'], 'q0');
    } finally {
      client.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
