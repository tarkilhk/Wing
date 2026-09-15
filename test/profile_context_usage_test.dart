import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  late Host host;
  late ProfileWorkspaceController controller;
  Completer<Map<String, dynamic>>? pending;
  late Map<String, dynamic> breakdownResponse;
  const snapshot = {
    'context_used': 250,
    'context_max': 1000,
    'context_percent': 25,
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host();
    pending = null;
    breakdownResponse = snapshot;
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'context-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: (scope) {
        final base = host.gateway(scope);
        return host.gateways[scope.profileName] = ProfileGateway(
          scope: scope,
          discover: base.discover,
          get: base.read,
          rpc: (method, params) {
            if (method == 'session.context_breakdown') {
              host.calls.add((scope.profileName, method, params));
              return pending?.future ?? Future.value(breakdownResponse);
            }
            return base.call(method, params);
          },
        );
      },
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  test(
    'usage belongs to the original chat and partial events retain server limits',
    () async {
      final a = await controller.createChat();
      await controller.refreshContext(a);
      expect(a.context!.percent, 25);
      expect(host.calls.last.$3, {'session_id': 'a-runtime', 'profile': 'a'});
      await controller.switchProfile('b');
      final b = await controller.createChat();
      await controller.refreshContext(b);
      host.event('a', 'session.usage', {
        'usage': {'context_used': 750, 'context_percent': 75},
      });
      expect(a.context!.percent, 75);
      expect(a.context!.max, 1000);
      expect(b.context!.percent, 25);
    },
  );

  test('late breakdown cannot overwrite a newer live usage event', () async {
    final chat = await controller.createChat();
    await controller.refreshContext(chat);
    pending = Completer();
    final refresh = controller.refreshContext(chat);
    host.event('a', 'session.usage', {
      'usage': {'context_used': 900, 'context_percent': 90},
    });
    pending!.complete(snapshot);
    await refresh;
    expect(chat.context!.percent, 90);
    host.event('a', 'session.usage', {
      'usage': {'context_max': 0},
    });
    expect(chat.context, isNull);
  });

  test(
    'refetches context when a resumed session becomes ready without a prompt',
    () async {
      // A cold resume can answer context_breakdown before the lazy agent exists.
      // Hermes returns an explicit zero/unknown breakdown in that phase, then
      // emits session.info after agent construction. The ready response has no
      // context_* fields until the next breakdown RPC.
      breakdownResponse = {
        'context_used': 0,
        'context_max': 0,
        'context_percent': 0,
        'context_estimated': false,
      };
      host.running = false;
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'same'),
      );
      final restored = controller.current!.chat!;
      await Future<void>.delayed(Duration.zero);
      expect(restored.context, isNull);
      expect(
        host.calls.where((call) => call.$2 == 'session.context_breakdown'),
        hasLength(1),
      );

      breakdownResponse = {
        'context_used': 1200,
        'context_max': 4000,
        'context_percent': 30,
        'context_estimated': true,
      };
      host.event('a', 'session.info', {
        'usage': {'calls': 0, 'input': 0, 'output': 0, 'total': 0},
      });
      await Future<void>.delayed(Duration.zero);

      expect(restored.context?.percent, 30);
      expect(restored.context?.estimated, isTrue);
      expect(restored.messages, isNotEmpty);
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      expect(
        host.calls.where((call) => call.$2 == 'session.context_breakdown'),
        hasLength(2),
      );
    },
  );

  test(
    'late pre-ready breakdown cannot erase the ready session usage',
    () async {
      host.running = false;
      final beforeReady = Completer<Map<String, dynamic>>();
      pending = beforeReady;
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'same'),
      );
      final chat = controller.current!.chat!;
      pending = null;
      host.event('a', 'session.info', {
        'usage': {'calls': 0, 'input': 0, 'output': 0},
      });
      await Future<void>.delayed(Duration.zero);
      expect(chat.context?.percent, 25);
      beforeReady.complete({
        'context_used': 0,
        'context_max': 0,
        'context_percent': 0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(chat.context?.percent, 25);
    },
  );
}
