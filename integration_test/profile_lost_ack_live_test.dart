import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_connection_identity.dart';
import 'package:hermes_android/core/services/profile_selection_store.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';

/// A transparent, one-shot WebSocket fault injector.
///
/// It forwards the credential-bearing path and query without inspecting or
/// logging them. Only the request id of the nonce-bearing prompt is retained.
class _LostAckProxy {
  final int upstreamPort;
  final String nonce;
  HttpServer? _server;
  Object? _targetRequestId;
  bool _dropArmed = true;

  int matchingSubmitCount = 0;
  int downstreamConnections = 0;
  bool sawSuccessfulAck = false;

  _LostAckProxy({required this.upstreamPort, required this.nonce});

  int get port => _server!.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_accept);
  }

  Future<void> _accept(HttpRequest request) async {
    WebSocket? downstream;
    WebSocket? upstream;
    try {
      downstream = await WebSocketTransformer.upgrade(request);
      downstreamConnections++;
      final upstreamUri = request.requestedUri.replace(
        scheme: 'ws',
        host: '127.0.0.1',
        port: upstreamPort,
      );
      upstream = await WebSocket.connect(upstreamUri.toString());
      final client = downstream;
      final server = upstream;
      var interrupted = false;

      client.listen(
        (frame) {
          _observeClientFrame(frame);
          if (!interrupted && server.readyState == WebSocket.open) {
            server.add(frame);
          }
        },
        onError: (_) => server.close(),
        onDone: () => server.close(),
        cancelOnError: true,
      );
      server.listen(
        (frame) {
          if (interrupted) return;
          if (_shouldDrop(frame)) {
            interrupted = true;
            unawaited(client.close(WebSocketStatus.goingAway));
            unawaited(server.close(WebSocketStatus.goingAway));
            return;
          }
          if (client.readyState == WebSocket.open) client.add(frame);
        },
        onError: (_) => client.close(),
        onDone: () => client.close(),
        cancelOnError: true,
      );
    } catch (_) {
      await downstream?.close();
      await upstream?.close();
    }
  }

  void _observeClientFrame(Object? frame) {
    if (frame is! String) return;
    try {
      final message = jsonDecode(frame);
      if (message is! Map || message['method'] != 'prompt.submit') return;
      final params = message['params'];
      if (params is! Map || !params['text'].toString().contains(nonce)) return;
      matchingSubmitCount++;
      if (_dropArmed) _targetRequestId ??= message['id'];
    } catch (_) {
      // Non-JSON and unrelated frames remain transparent.
    }
  }

  bool _shouldDrop(Object? frame) {
    if (!_dropArmed || _targetRequestId == null || frame is! String) {
      return false;
    }
    try {
      final message = jsonDecode(frame);
      if (message is! Map || message['id'] != _targetRequestId) return false;
      if (message['error'] != null || !message.containsKey('result')) {
        return false;
      }
      sawSuccessfulAck = true;
      _dropArmed = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const upstreamPort = int.fromEnvironment('HERMES_TEST_PORT');
  const runModel = bool.fromEnvironment('RUN_MODEL');

  testWidgets(
    'accepted attachment prompt survives a lost acknowledgement without resend',
    (tester) async {
      expect(upstreamPort, greaterThan(0), reason: 'Set HERMES_TEST_PORT');
      expect(runModel, isTrue, reason: 'Explicit RUN_MODEL=true is required');

      final nonce =
          'D09_LOST_ACK_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      final proxy = _LostAckProxy(upstreamPort: upstreamPort, nonce: nonce);
      await proxy.start();
      addTearDown(proxy.close);

      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final connection = SavedConnection(
        id: 'profile-lost-ack-live-qa',
        label: 'Lost acknowledgement live QA',
        host: '127.0.0.1',
        port: upstreamPort,
        dashboardPortOverride: upstreamPort,
        desktopGatewayUrl: 'http://127.0.0.1:${proxy.port}',
        apiKey: '',
      );
      final manager = await ConnectionManager.create(preferences);
      await manager.importConnections([connection], replaceExisting: false);
      await ProfileSelectionStore(preferences).write(
        await ProfileConnectionIdentity().resolve(connection),
        'android-qa-a',
      );
      final controller = ProfileWorkspaceController(
        connection: connection,
        connectionIdentity: await ProfileConnectionIdentity().resolve(
          connection,
        ),
        preferences: preferences,
      );
      addTearDown(controller.dispose);

      Future<void> until(
        bool Function() condition, {
        int seconds = 60,
        String? reason,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(condition(), isTrue, reason: reason);
      }

      await controller.initialize();
      expect(controller.error, isNull);
      expect(controller.current!.scope.profileName, 'android-qa-a');
      final chat = await controller.createChat();
      chat.draft =
          'Bounded lost-ack setup. Use only the clarify tool to ask exactly '
          '"May the queued attachment test continue?" Wait for my answer, then '
          'reply exactly READY. Do not use any other tool, browse, delegate, or '
          'read or change files.';
      await controller.send(chat);
      await until(
        () => chat.clarification != null || !chat.busy,
        seconds: 120,
        reason: chat.error,
      );
      expect(
        chat.clarification,
        isNotNull,
        reason: 'Setup did not invoke clarify; this is not a product failure.',
      );

      final directory = await getTemporaryDirectory();
      final source = File('${directory.path}/$nonce.txt');
      await source.writeAsString('ATTACHMENT_$nonce');
      addTearDown(() async {
        if (await source.exists()) await source.delete();
      });
      await controller.addAttachment(chat, source.path, '$nonce.txt');
      chat.draft =
          'Attachment transport check $nonce. Reply exactly ACK_$nonce. Do not '
          'use tools or perform any other work.';
      await controller.queuePrompt(chat, chat.draft);
      expect(chat.queuedPrompts, hasLength(1));

      await controller.clarify(chat, 'Yes');
      await until(
        () => proxy.sawSuccessfulAck,
        seconds: 180,
        reason: 'The upstream gateway never acknowledged the queued prompt.',
      );
      expect(proxy.matchingSubmitCount, 1);
      await until(
        () => chat.queuePaused && !chat.queueDraining,
        reason: chat.error,
      );
      expect(chat.queuedPrompts, hasLength(1));

      await controller.reconnect(chat.key.workspace);
      await until(
        () => proxy.downstreamConnections >= 2,
        reason: 'Android did not reconnect through the transparent proxy.',
      );
      await until(() => !chat.busy, seconds: 180, reason: chat.error);
      await controller.refreshHistory(chat);
      expect(chat.historyError, isNull);
      expect(
        chat.messages.where(
          (message) =>
              message['role'] == 'user' &&
              message['content'].toString().contains(nonce),
        ),
        hasLength(1),
      );
      expect(proxy.matchingSubmitCount, 1);
      expect(chat.queuePaused, isTrue);
      expect(chat.queuedPrompts, hasLength(1));

      final retained = chat.queuedPrompts.single;
      await controller.removeQueuedPrompt(chat, 0, expectedPrompt: retained);
      expect(chat.queuedPrompts, isEmpty);
      expect(proxy.matchingSubmitCount, 1);
    },
    skip: upstreamPort == 0 || !runModel,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
