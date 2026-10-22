import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/bot_display_client.dart';
import 'package:wing/core/models/bot_display.dart';
import 'support/bot_display_fixture.dart';

void main() {
  Future<(DisplayPeer, StreamIterator<BotDisplayFrame>)> startPeer({
    bool fragment = false,
  }) async {
    final peer = DisplayPeer(fragment: fragment);
    final frames = StreamIterator(peer.client.frames);
    addTearDown(() async {
      peer.client.close();
      await frames.cancel();
    });
    peer.begin();
    peer.client.start();
    expect(await frames.moveNext(), isTrue);
    return (peer, frames);
  }

  test('fragmented handshake decodes a complete true-colour frame', () async {
    final (peer, frames) = await startPeer(fragment: true);
    expect(peer.sent.first, 'RFB 003.008\n'.codeUnits);
    expect((frames.current.width, frames.current.height), (4, 3));
    expect(frames.current.pixels.take(8), [0, 90, 130, 255, 17, 90, 130, 255]);
  });

  test(
    'stock clipboard negotiation delivers pixels without desktop-layout messages',
    () async {
      final (peer, frames) = await startPeer();
      final packet = peer.sent.singleWhere((p) => p[0] == 2);
      expect(packet.sublist(16), [0xc0, 0xa1, 0xe5, 0xce]);
      expect(peer.client.clipboardReady, isTrue);
      expect((frames.current.width, frames.current.height), (4, 3));
    },
  );

  test(
    'extended clipboard preserves Unicode and newlines without key events',
    () async {
      final (peer, _) = await startPeer(fragment: true);
      expect(peer.client.clipboardReady, true);
      final start = peer.sent.length;
      peer.client.setClipboard('café 😀\nsecond line');
      final packet = peer.sent.last;
      expect(packet[0], 6);
      expect(ByteData.sublistView(packet).getInt32(4), -(packet.length - 8));
      expect(ByteData.sublistView(packet).getUint32(8), 0x10000001);
      final payload = Uint8List.fromList(zlib.decode(packet.sublist(12)));
      expect(ByteData.sublistView(payload).getUint32(0), payload.length - 4);
      expect(utf8.decode(payload.sublist(4)), 'café 😀\r\nsecond line\x00');
      expect(peer.sent.skip(start).where((p) => p[0] == 4), isEmpty);
      expect(
        () => peer.client.setClipboard('x' * (256 * 1024)),
        throwsStateError,
      );
      expect(() => peer.client.setClipboard('bad\x00text'), throwsStateError);
    },
  );

  test('pointer input is clamped to the remote framebuffer', () async {
    final (peer, _) = await startPeer();
    peer.client.pointer(100, -1, 1);
    expect(peer.sent.last, [5, 1, 0, 3, 0, 0]);
  });

  test('key input encodes both press and release', () async {
    final (peer, _) = await startPeer();
    peer.client.key(0xff0d, true);
    expect(peer.sent.last, [4, 1, 0, 0, 0, 0, 255, 13]);
    peer.client.key(0xff0d, false);
    expect(peer.sent.last, [4, 0, 0, 0, 0, 0, 255, 13]);
  });

  test('closed viewer cannot send remote input', () async {
    final (peer, _) = await startPeer();
    peer.client.close();
    final count = peer.sent.length;
    peer.client.pointer(1, 1, 1);
    peer.client.key(65, true);
    expect(peer.sent, hasLength(count));
    expect(peer.closed, isTrue);
  });

  test(
    'overlapping CopyRect reads the original pixels before writing',
    () async {
      final (peer, frames) = await startPeer();
      final copy = ByteData(20)
        ..setUint16(2, 1)
        ..setUint16(4, 1)
        ..setUint16(8, 3)
        ..setUint16(10, 1)
        ..setInt32(12, 1);
      peer.add(copy.buffer.asUint8List());
      expect(await frames.moveNext(), isTrue);
      expect(
        [for (var x = 0; x < 4; x++) frames.current.pixels[x * 4]],
        [0, 0, 17, 34],
      );
    },
  );

  test('resize publishes the new framebuffer dimensions', () async {
    final (peer, frames) = await startPeer();
    final resize = ByteData(16)
      ..setUint16(2, 1)
      ..setUint16(8, 2)
      ..setUint16(10, 1)
      ..setInt32(12, -223);
    peer.add(resize.buffer.asUint8List());
    expect(await frames.moveNext(), isTrue);
    expect((frames.current.width, frames.current.height), (2, 1));
    expect(frames.current.pixels, hasLength(2 * 1 * 4));
  });

  test('oversized dimensions terminate the stream', () async {
    final peer = DisplayPeer(width: 65535, height: 65535);
    addTearDown(peer.client.close);
    final error = expectLater(
      peer.client.frames,
      emitsInOrder([emitsError(isA<FormatException>()), emitsDone]),
    );
    peer.begin();
    peer.client.start();
    await error;
    expect(peer.closed, isTrue);
  });

  test('unrequested encodings terminate the stream', () async {
    final (peer, frames) = await startPeer();
    final error = expectLater(
      frames.moveNext(),
      throwsA(isA<FormatException>()),
    );
    final invalid = ByteData(16)
      ..setUint16(2, 1)
      ..setUint16(8, 1)
      ..setUint16(10, 1)
      ..setInt32(12, 16);
    peer.add(invalid.buffer.asUint8List());
    await error;
    expect(peer.closed, isTrue);
  });

  test('display ticket keeps the gateway prefix and custom headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
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
    addTearDown(client.close);
    final r = await request.future;
    expect(r.uri.path, '/hermes/api/display/ws');
    expect(r.uri.queryParameters, {
      'display_ticket': 'ticket with + characters',
    });
    expect(r.headers.value('X-Test-Gateway'), 'kept');
  });
}
