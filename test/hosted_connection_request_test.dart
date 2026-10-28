import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/models/hosted_connector_accounts.dart';
import 'support/hosted_connection_request_scenarios.dart';

class _AuthorizationBrowser extends UrlLauncherPlatform {
  final calls = <(String, LaunchOptions)>[];
  final gate = Completer<bool>();
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) {
    calls.add((url, options));
    return gate.future;
  }
}

void main() {
  registerConnectionRequestScenarios();

  test(
    'status overlays preserve request metadata and reject stale or unrelated updates',
    () {
      final request = HostedConnectionOperation.fromJson(connectionRequest());
      final status = {...connectionRequest(seq: 1), 'settled': false}
        ..remove('display')
        ..remove('tool_call_id');
      final next = request.applyStatus(status);
      expect(next.isDirectory, isTrue);
      expect(next.suggested, ['gmail']);
      expect(next.toolCallId, 'connect-1');
      expect(identical(next.applyStatus(status), next), isTrue);
      expect(
        identical(
          next.applyStatus({...status, 'op_id': 'other', 'seq': 2}),
          next,
        ),
        isTrue,
      );
      final settled = next.applyStatus({...status, 'seq': 2, 'settled': true});
      expect(
        identical(settled.applyStatus({...status, 'seq': 3}), settled),
        isTrue,
      );
    },
  );

  test('authorization only exposes supported remote account URLs', () {
    for (final url in [
      'javascript:alert(1)',
      'file:///private',
      'https:relative',
    ]) {
      final target = HostedConnectionTarget.fromJson({
        'name': 'mail',
        'kind': 'connector',
        'state': 'pending',
        'connect_url': url,
      });
      expect(target.needsAuthorization, isFalse);
    }
    expect(
      HostedConnectionTarget.fromJson({
        'name': 'plugin',
        'kind': 'plugin',
        'state': 'pending',
        'connect_url': 'https://example.test',
      }).needsAuthorization,
      isFalse,
    );
  });

  test(
    'Continue is single flight and a newer request retires its late response',
    () async {
      final fixture = ConnectionRequestFixture();
      final (controller, preferences) = await connectionRequestController(
        fixture,
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      final chat = controller.current!.chat!;
      final operation = chat.connectionOperation!;
      fixture.responseGate = Completer<void>();
      final first = controller.continueConnectionOperation(chat, operation);
      final firstFailure = expectLater(first, throwsStateError);
      await expectLater(
        controller.continueConnectionOperation(chat, operation),
        throwsStateError,
      );
      expect(fixture.connectionCalls, hasLength(1));
      fixture.event(
        chat,
        'connection.request',
        connectionRequest(id: 'next-operation'),
      );
      fixture.responseGate!.complete();
      await firstFailure;
      expect(chat.connectionOperation!.id, 'next-operation');
      expect(chat.connectionOperation!.settled, isFalse);
      expect(chat.connectionOperationWorking, isFalse);
      expect(fixture.connectionCalls, hasLength(1));
    },
  );

  test(
    'updates settle the current operation without losing directory metadata',
    () async {
      final fixture = ConnectionRequestFixture();
      final (controller, preferences) = await connectionRequestController(
        fixture,
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      final chat = controller.current!.chat!;
      fixture.event(chat, 'connection.update', {
        ...fixture.status,
        'op_id': 'different',
        'seq': 10,
      });
      expect(chat.connectionOperation!.sequence, 0);
      fixture.event(
        chat,
        'connection.update',
        {...fixture.status, 'seq': 1, 'settled': true}
          ..remove('display')
          ..remove('tool_call_id'),
      );
      expect(chat.connectionOperation!.settled, isTrue);
      expect(chat.connectionOperation!.isDirectory, isTrue);
      expect(
        controller.canContinueConnectionOperation(
          chat,
          chat.connectionOperation!,
        ),
        isFalse,
      );
    },
  );

  test(
    'accepted reconnect snapshot clears requests absent from canonical state',
    () async {
      final fixture = ConnectionRequestFixture();
      final (controller, preferences) = await connectionRequestController(
        fixture,
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      final chat = controller.current!.chat!;
      expect(chat.connectionOperation, isNotNull);
      fixture.pending = null;
      await controller.refresh();
      expect(chat.connectionOperation, isNull);
    },
  );
  test(
    'lost settled ACK recovers through UNKNOWN_OPERATION and canonical snapshot',
    () async {
      final fixture = ConnectionRequestFixture()..loseResponse = true;
      final (controller, preferences) = await connectionRequestController(
        fixture,
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      final chat = controller.current!.chat!;
      await expectLater(
        controller.continueConnectionOperation(chat, chat.connectionOperation!),
        throwsA(isA<TimeoutException>()),
      );
      expect(chat.connectionOperation, isNotNull);
      await controller.refreshConnectionOperation(
        chat,
        chat.connectionOperation!,
      );
      expect(chat.connectionOperation, isNull);
      expect(
        fixture.connectionCalls.where(
          (call) => call.$1 == 'connection.respond',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'late status from a replaced runtime cannot settle its replacement',
    () async {
      final fixture = ConnectionRequestFixture();
      final (controller, preferences) = await connectionRequestController(
        fixture,
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      final chat = controller.current!.chat!;
      fixture.status = {...fixture.status, 'seq': 1};
      fixture.statusGate = Completer<void>();
      final refresh = controller.refreshConnectionOperation(
        chat,
        chat.connectionOperation!,
      );
      final retired = expectLater(refresh, throwsStateError);
      fixture.runtimeOverride = 'replacement-runtime';
      await controller.refresh();
      fixture.statusGate!.complete();
      await retired;
      expect(chat.runtime.runtimeId, 'replacement-runtime');
      expect(chat.connectionOperation!.sequence, 0);
      expect(chat.connectionOperationWorking, isFalse);
    },
  );

  test(
    'read-only conversations may check status but cannot continue',
    () async {
      final fixture = ConnectionRequestFixture();
      final (controller, preferences) = await connectionRequestController(
        fixture,
      );
      addTearDown(() {
        controller.dispose();
        preferences.dispose();
      });
      final chat = controller.current!.chat!;
      fixture.gateways['personal']!.canonical.refused(
        chat.runtime.runtimeId,
        JsonRpcError(
          'session.mutate',
          'Read only',
          reason: 'session_read_only',
        ),
      );
      await controller.refresh();
      expect(chat.readOnlyReason, 'session_read_only');
      expect(
        controller.canContinueConnectionOperation(
          chat,
          chat.connectionOperation!,
        ),
        isFalse,
      );
      expect(
        controller.canRefreshConnectionOperation(
          chat,
          chat.connectionOperation!,
        ),
        isTrue,
      );
      await expectLater(
        controller.continueConnectionOperation(chat, chat.connectionOperation!),
        throwsStateError,
      );
      await controller.refreshConnectionOperation(
        chat,
        chat.connectionOperation!,
      );
      expect(fixture.connectionCalls.map((call) => call.$1), [
        'connectors.operation.status',
      ]);
    },
  );
  testWidgets(
    'authorization opens the received account URL and retires late failure',
    (tester) async {
      final fixture = ConnectionRequestFixture();
      final (controller, preferences) = await connectionRequestController(
        fixture,
      );
      final browser = _AuthorizationBrowser();
      final original = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = browser;
      addTearDown(() {
        UrlLauncherPlatform.instance = original;
        controller.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileWorkspaceScreen(
            controller: controller,
            createBotsSession: () => BotsSession((_) async => const []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Authorize work'));
      await tester.tap(find.byTooltip('Authorize work'));
      await tester.pump();
      expect(
        browser.calls.single.$1,
        'https://accounts.example.test/authorize',
      );
      expect(
        browser.calls.single.$2.mode,
        PreferredLaunchMode.externalApplication,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CircularProgressIndicator &&
              widget.semanticsLabel == 'Opening authorization…',
        ),
        findsOneWidget,
      );
      expect(fixture.connectionCalls, isEmpty);
      final chat = controller.current!.chat!;
      fixture.event(
        chat,
        'connection.request',
        connectionRequest(id: 'replacement'),
      );
      await tester.pump();
      browser.gate.complete(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not finish.'), findsNothing);
      expect(chat.connectionOperation!.id, 'replacement');
      expect(chat.connectionOperation!.targets.single.connected, isFalse);
      expect(find.byTooltip('Continue connection request'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
