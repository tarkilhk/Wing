import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/hosted_connection_request_panel.dart';
import '../profile_connection_identity_test.dart' show identityTestConnection;
import 'canonical_gateway_fixture.dart';
import 'form_family_capture.dart';
import 'profile_browser_fixture.dart';

Map<String, dynamic> connectionRequest({
  String id = 'mail-request',
  int seq = 0,
}) => {
  'op_id': id,
  'seq': seq,
  'deadline_at': 1999999999,
  'timeout_seconds': 300,
  'tool_call_id': 'connect-1',
  'display': {
    'suggested': ['gmail'],
  },
  'targets': [
    {
      'name': 'Gmail',
      'kind': 'connector',
      'action': 'connect',
      'state': 'initiated',
      'alias': 'work',
      'connect_url': 'https://accounts.example.test/authorize',
    },
  ],
};

class ConnectionRequestFixture extends ProfileBrowserFixture {
  Map<String, dynamic>? pending = connectionRequest();
  Map<String, dynamic> status = {...connectionRequest(), 'settled': false};
  final connectionCalls = <(String, Map<String, dynamic>)>[];
  final gateways = <String, ProfileGateway>{};
  final sequences = <(String, String), int>{};
  Completer<void>? responseGate, statusGate;
  bool reject = false, loseResponse = false;
  String? runtimeOverride;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    late final ProfileGateway result;
    result = ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      close: base.close,
      connect: () async {
        if (result.onEvent != null) gateways[scope.profileName] = result;
        await base.connect();
      },
      rpc: (method, params) async {
        if (method == 'session.resume') {
          final snapshot = await base.call(method, params);
          final runtime = runtimeOverride ?? snapshot['session_id'] as String;
          return {
            ...snapshot,
            'session_id': runtime,
            'last_sequence': sequences[(scope.profileName, runtime)] ?? 0,
            'pending_connection': pending,
          };
        }
        if (method == 'connection.respond') {
          connectionCalls.add((method, Map.of(params)));
          await responseGate?.future;
          if (reject) throw StateError('Fixture connection refused');
          status = {
            ...status,
            'seq': (status['seq'] as int) + 1,
            'settled': true,
          };
          pending = null;
          if (loseResponse) {
            throw TimeoutException('Lost Continue acknowledgment');
          }
          return {'status': 'ok', 'settled': true};
        }
        if (method == 'connectors.operation.status') {
          connectionCalls.add((method, Map.of(params)));
          if (status['settled'] == true) {
            throw JsonRpcError(
              method,
              'Unknown operation',
              reason: 'UNKNOWN_OPERATION',
            );
          }
          final response = Map<String, dynamic>.of(status)
            ..remove('display')
            ..remove('tool_call_id')
            ..remove('timeout_seconds');
          await statusGate?.future;
          return response;
        }
        return base.call(method, params);
      },
    );
    return result;
  }

  void event(ProfileChat chat, String type, Map<String, dynamic> data) {
    final profile = chat.key.workspace.profileName;
    final key = (profile, chat.runtime.runtimeId);
    final seq = (sequences[key] ?? 0) + 1;
    sequences[key] = seq;
    gateways[profile]!.onEvent!(
      StreamEvent(
        type: type,
        data: data,
        sessionId: chat.runtime.runtimeId,
        envelope: {
          'seq': seq,
          'replay_epoch': canonicalSnapshotFields['replay_epoch'],
          'authority_epoch': 1,
          'execution_generation': 0,
        },
      ),
    );
  }
}

Future<(ProfileWorkspaceController, AppPreferences)>
connectionRequestController(ConnectionRequestFixture fixture) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final appPreferences = AppPreferences(preferences);
  final controller = ProfileWorkspaceController(
    access: ConnectionAccess(
      connection: identityTestConnection(),
      dashboardOAuth: null,
    ),
    connectionIdentity: 'received-connection-request',
    preferences: preferences,
    appPreferences: appPreferences,
    gatewayFactory: fixture.gateway,
  );
  await controller.initialize();
  await controller.openSession(
    ProfileSessionKey(controller.current!.scope, 'newest'),
  );
  return (controller, appPreferences);
}

void registerConnectionRequestScenarios({
  bool native = false,
  Future<void> Function(WidgetTester, String, bool)? nativeCapture,
}) {
  if (!native) setUpAll(loadFormFamilyFonts);
  testWidgets(
    'Conversation connection requests retain owner through pending failure and retry',
    (tester) async {
      if (!native) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      Future<void> capture(String name) async {
        if (native) {
          await nativeCapture?.call(tester, name, false);
        } else {
          await captureFormFamily(tester, name);
        }
      }

      Future<void> settle() => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          final fixture = ConnectionRequestFixture();
          final (controller, preferences) = await connectionRequestController(
            fixture,
          );
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: formFamilyCapture,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: wingTheme(brightness),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: ProfileWorkspaceScreen(
                    controller: controller,
                    createBotsSession: () => BotsSession((_) async => const []),
                  ),
                ),
              ),
            );
            await settle();
            final continueButton = find.byTooltip(
              'Continue connection request',
            );
            await tester.ensureVisible(continueButton);
            await settle();
            expect(find.text('Gmail · work'), findsOneWidget);
            expect(find.byTooltip('Authorize work'), findsOneWidget);
            final stem = 'connection-request-${brightness.name}-$scale';
            await capture('$stem-request');
            fixture.responseGate = Completer<void>();
            fixture.reject = true;
            await tester.tap(continueButton);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is CircularProgressIndicator &&
                    widget.semanticsLabel == 'Continuing…',
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: find.byType(HostedConnectionRequestPanel),
                matching: find.byType(CircularProgressIndicator),
              ),
              findsOneWidget,
            );
            final progress = find.descendant(
              of: find.byType(HostedConnectionRequestPanel),
              matching: find.byType(CircularProgressIndicator),
            );
            expect(
              tester
                  .getRect(progress)
                  .overlaps(
                    Offset.zero &
                        tester.view.physicalSize / tester.view.devicePixelRatio,
                  ),
              isTrue,
            );
            expect(
              tester
                  .widget<IconButton>(
                    find.ancestor(
                      of: continueButton,
                      matching: find.byType(IconButton),
                    ),
                  )
                  .onPressed,
              isNull,
            );
            await capture('$stem-pending');
            fixture.responseGate!.complete();
            await settle();
            await tester.ensureVisible(continueButton);
            await settle();
            expect(find.textContaining('Could not finish.'), findsOneWidget);
            await capture('$stem-failed');
            fixture.reject = false;
            fixture.responseGate = null;
            await tester.tap(find.byTooltip('Check connection status'));
            await settle();
            expect(find.text('Connection status checked.'), findsOneWidget);
            await tester.ensureVisible(continueButton);
            await tester.tap(continueButton);
            await settle();
            expect(find.byType(HostedConnectionRequestPanel), findsNothing);
            expect(find.byTooltip('Continue connection request'), findsNothing);
            final responses = fixture.connectionCalls
                .where((call) => call.$1 == 'connection.respond')
                .toList();
            expect(responses, hasLength(2));
            for (final call in responses) {
              expect(call.$2, {
                'profile': 'personal',
                'owner': {'type': 'session', 'session_id': 'runtime-newest'},
                'op_id': 'mail-request',
                'result': {'settled_by': 'continue'},
              });
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
            preferences.dispose();
          }
        }
      }
    },
  );
}
