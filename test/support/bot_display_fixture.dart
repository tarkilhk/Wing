import 'package:wing/core/services/group_observations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:wing/core/services/bot_display_client.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'bots_fixture.dart';

/// A stock RFB peer: all bytes pass through the production stream parser.
class DisplayPeer {
  DisplayPeer({this.fragment = false, this.width = 4, this.height = 3});
  final bool fragment;
  final int width, height;
  final input = StreamController<List<int>>();
  final sent = <Uint8List>[];
  bool closed = false;
  int phase = 0, requests = 0;
  late final client = BotDisplayClient(
    incoming: input.stream,
    send: accept,
    disconnect: () {
      closed = true;
      unawaited(input.close());
    },
  );
  void add(List<int> bytes) {
    if (closed) return;
    if (fragment) {
      for (final b in bytes) {
        input.add([b]);
      }
    } else {
      input.add(bytes);
    }
  }

  void begin() {
    add(ascii.encode('RFB 003.008\n'));
  }

  void accept(Uint8List bytes) {
    sent.add(bytes);
    if (phase == 0) {
      phase++;
      add([1, 1]);
    } else if (phase == 1) {
      phase++;
      add([0, 0, 0, 0]);
    } else if (phase == 2) {
      phase++;
      final init = ByteData(24)
        ..setUint16(0, width)
        ..setUint16(2, height);
      add(init.buffer.asUint8List());
    } else if (bytes[0] == 3) {
      requests++;
      if (requests == 1 && width * height < 100000) raw();
    }
  }

  void raw() {
    final header = ByteData(16)
      ..setUint16(2, 1)
      ..setUint16(8, width)
      ..setUint16(10, height);
    add([
      ...header.buffer.asUint8List(),
      for (var i = 0; i < width * height; i++) ...[i * 17 % 256, 90, 130, 0],
    ]);
  }
}

class DisplayFixture {
  final roster = BotsFixture();
  final peers = <DisplayPeer>[];
  final calls = <(String, String, Map<String, dynamic>)>[];
  String viewer = 'phone-viewer';
  String holder = 'agent';
  String? held;
  int epoch = 0, retains = 0, releases = 0;
  bool running = true, failRelease = false, failStatus = false;
  Completer<void>? acquireWait, beforeAcquire, statusWait, connectWait;
  Map<String, dynamic> get lease => {
    'holder': holder,
    'epoch': epoch,
    'viewer_hash': held == null
        ? null
        : sha256.convert(utf8.encode(held!)).toString().substring(0, 12),
  };
  Map<String, dynamic> get status => {
    'supported': true,
    'installed': true,
    'running': running,
    'lease': lease,
  };
  late final repository = BotsRepository(
    groupObservations: GroupObservations(roster.repository.scope),
    scope: roster.repository.scope,
    instance: 'Home server',
    retain: () {
      retains++;
    },
    release: () {
      releases++;
    },
    read: (profile, method, params) async {
      calls.add((profile, method, params));
      if (method == 'display.status') {
        await statusWait?.future;
        if (failStatus) throw StateError('Offline');
        return status;
      }
      if (method == 'display.observe') {
        return {
          ...status,
          'ticket': 'one-use',
          'viewer_id': viewer,
          'path': '/api/display/ws',
        };
      }
      return roster.read(profile, method, params);
    },
    command: (profile, method, params, canDispatch, onDispatched) async {
      if (method == 'display.lease.acquire') await beforeAcquire?.future;
      if (!canDispatch()) throw StateError('Retired');
      onDispatched();
      calls.add((profile, method, params));
      if (method == 'display.lease.acquire') {
        await acquireWait?.future;
        holder = 'human';
        held = params['viewer_id'] as String;
        epoch++;
      } else if (method == 'display.lease.release') {
        if (failRelease) throw StateError('Offline');
        if (params['force'] != true &&
            params['viewer_id'] != held &&
            holder == 'human') {
          throw StateError('viewer_mismatch');
        }
        holder = 'agent';
        held = null;
        epoch++;
      } else if (method == 'display.start' || method == 'display.stop') {
        running = method == 'display.start';
      } else {
        throw StateError('Unexpected command');
      }
      return {...status, 'lease': lease};
    },
    displayConnect: (_) async {
      await connectWait?.future;
      final peer = DisplayPeer();
      peers.add(peer);
      final client = peer.client;
      peer.begin();
      return client;
    },
    ownership: roster.ownership,
    savedHistory: roster.savedHistory,
  );
}
