import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/bot_display_client.dart';
import 'package:wing/core/models/bot_display.dart';
import 'support/bot_display_fixture.dart';

void main() {
  test(
    'fragmented handshake, true-colour frame and exact input packets',
    () async {
      final peer = DisplayPeer(fragment: true);
      final client = peer.client;
      final frame = client.frames.first;
      peer.begin();
      client.start();
      final result = await frame;
      expect((result.width, result.height), (4, 3));
      expect(result.pixels.take(8), [0, 90, 130, 255, 17, 90, 130, 255]);
      client.pointer(100, -1, 1);
      client.key(0xff0d, true);
      client.key(0xff0d, false);
      expect(peer.sent[0], 'RFB 003.008\n'.codeUnits);
      expect(peer.sent.where((p) => p.length == 6).last, [5, 1, 0, 3, 0, 0]);
      expect(peer.sent.last, [4, 0, 0, 0, 0, 0, 255, 13]);
      client.close();
      final count = peer.sent.length;
      client.pointer(1, 1, 1);
      client.key(65, true);
      expect(peer.sent, hasLength(count));
    },
  );

  test(
    'overlapping CopyRect and resize use the complete new framebuffer',
    () async {
      final peer = DisplayPeer();
      final frames = <BotDisplayFrame>[];
      final client = peer.client;
      final sub = client.frames.listen(frames.add);
      peer.begin();
      client.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final copy = ByteData(20)
        ..setUint16(2, 1)
        ..setUint16(4, 1)
        ..setUint16(8, 3)
        ..setUint16(10, 1)
        ..setInt32(12, 1);
      peer.add(copy.buffer.asUint8List());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        [for (var x = 0; x < 4; x++) frames.last.pixels[x * 4]],
        [0, 0, 17, 34],
      );
      final resize = ByteData(16)
        ..setUint16(2, 1)
        ..setUint16(8, 2)
        ..setUint16(10, 1)
        ..setInt32(12, -223);
      peer.add(resize.buffer.asUint8List());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect((frames.last.width, frames.last.height), (2, 1));
      client.close();
      await sub.cancel();
    },
  );

  test(
    'oversized dimensions and unrequested encodings terminate the stream',
    () async {
      final peer = DisplayPeer(width: 65535, height: 65535);
      final error = expectLater(
        peer.client.frames,
        emitsError(isA<FormatException>()),
      );
      peer.begin();
      peer.client.start();
      await error;
      expect(peer.closed, true);
      final next = DisplayPeer();
      final future = expectLater(
        next.client.frames,
        emitsInOrder([
          isA<BotDisplayFrame>(),
          emitsError(isA<FormatException>()),
          emitsDone,
        ]),
      );
      next.begin();
      next.client.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final invalid = ByteData(16)
        ..setUint16(2, 1)
        ..setUint16(8, 1)
        ..setUint16(10, 1)
        ..setInt32(12, 16);
      next.add(invalid.buffer.asUint8List());
      await future;
    },
  );

  test('display ticket keeps the gateway prefix and custom headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final request = Completer<HttpRequest>();
    server.listen((r) async {
      request.complete(r);
      final ws = await WebSocketTransformer.upgrade(r);
      await ws.close();
    });
    final client = await BotDisplayClient.connect(
      'http://127.0.0.1:${server.port}/hermes/',
      'ticket with + characters',
      {'X-Test-Gateway': 'kept'},
    );
    final r = await request.future;
    expect(r.uri.path, '/hermes/api/display/ws');
    expect(r.uri.queryParameters, {
      'display_ticket': 'ticket with + characters',
    });
    expect(r.headers.value('X-Test-Gateway'), 'kept');
    client.close();
    await server.close(force: true);
  });
}
