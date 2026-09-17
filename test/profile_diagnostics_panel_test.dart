import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_diagnostics_panel.dart';

class _DiagnosticsHost {
  final reads = <(String, Map<String, String>)>[];
  final calls = <(String, Map<String, dynamic>)>[];
  Future<Map<String, dynamic>> Function(String, Map<String, String>)? onRead;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? onCall;

  ProfileWorkspaceData workspace(String profile) {
    final scope = WorkspaceScope(
      connectionId: 'connection',
      profileName: profile,
    );
    return ProfileWorkspaceData(
      ProfileGateway(
        scope: scope,
        discover: () async => const ProfileDiscovery(
          profiles: [],
          currentName: null,
          activeName: null,
        ),
        get: (endpoint, query) {
          reads.add((endpoint, query));
          return onRead?.call(endpoint, query) ??
              Future.value(<String, dynamic>{});
        },
        rpc: (method, params) {
          calls.add((method, params));
          return onCall?.call(method, params) ??
              Future.value(
                method == 'setup.status'
                    ? <String, dynamic>{'provider_configured': true}
                    : <String, dynamic>{'ok': true},
              );
        },
      ),
    );
  }
}

Widget _app(
  ProfileWorkspaceData workspace, {
  VoidCallback? onManage,
  double textScale = 1,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: ProfileDiagnosticsPanel(
            workspace: workspace,
            connectionLabel: 'Home server',
            onManageConnections: onManage ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('checks the captured profile through exact modern routes', (
    tester,
  ) async {
    final host = _DiagnosticsHost();
    var managed = false;
    await tester.pumpWidget(
      _app(host.workspace('work'), onManage: () => managed = true),
    );
    expect(host.reads, isEmpty);
    expect(host.calls, isEmpty);

    await tester.tap(find.text('Run checks'));
    await tester.pumpAndSettle();

    expect(host.reads, hasLength(1));
    expect(host.reads.single.$1, 'sessions');
    expect(host.reads.single.$2, {
      'limit': '1',
      'offset': '0',
      'order': 'recent',
      'profile': 'work',
    });
    expect(host.calls, hasLength(2));
    expect(host.calls[0].$1, 'setup.status');
    expect(host.calls[0].$2, {'profile': 'work'});
    expect(host.calls[1].$1, 'setup.runtime_check');
    expect(host.calls[1].$2, {'profile': 'work'});
    expect(find.text('Authenticated dashboard API responded.'), findsOneWidget);
    expect(find.text('Provider is configured.'), findsOneWidget);
    expect(find.text('Provider credentials are available.'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('More health actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More health actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage connections'));
    expect(managed, isTrue);
  });

  testWidgets('keeps false and unavailable partial results distinct', (
    tester,
  ) async {
    final host = _DiagnosticsHost()
      ..onCall = (method, _) async {
        if (method == 'setup.status') return {'provider_configured': false};
        throw TimeoutException('secret backend detail');
      };
    await tester.pumpWidget(_app(host.workspace('personal')));

    await tester.tap(find.text('Run checks'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No provider credential is configured. '
        'Open provider access to configure this profile.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Runtime readiness check is unavailable.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret backend detail'), findsNothing);
  });

  testWidgets(
    'reports authentication rejection without exposing response text',
    (tester) async {
      final host = _DiagnosticsHost()
        ..onRead = (_, _) =>
            Future.error(const DashboardHttpException(401, 'sensitive/path'));
      await tester.pumpWidget(_app(host.workspace('work')));

      await tester.tap(find.text('Run checks'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Dashboard authentication was rejected. '
          'Check the address and password in Manage connections.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('sensitive/path'), findsNothing);
    },
  );

  testWidgets('late results do not cross profile scope', (tester) async {
    final dashboard = Completer<Map<String, dynamic>>();
    final setup = Completer<Map<String, dynamic>>();
    final runtime = Completer<Map<String, dynamic>>();
    final oldHost = _DiagnosticsHost();
    oldHost.onRead = (_, _) => dashboard.future;
    oldHost.onCall = (method, _) =>
        method == 'setup.status' ? setup.future : runtime.future;
    await tester.pumpWidget(_app(oldHost.workspace('old')));
    await tester.tap(find.text('Run checks'));
    await tester.pump();

    final newHost = _DiagnosticsHost();
    await tester.pumpWidget(_app(newHost.workspace('new')));
    dashboard.complete({});
    setup.complete({'provider_configured': true});
    runtime.complete({'ok': true});
    await tester.pump();

    expect(find.text('Not checked.'), findsNWidgets(3));
    expect(find.text('Authenticated dashboard API responded.'), findsNothing);
  });

  testWidgets('disposed panel ignores late results', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final host = _DiagnosticsHost();
    host.onRead = (_, _) => pending.future;
    host.onCall = (_, _) => pending.future;
    await tester.pumpWidget(_app(host.workspace('work')));
    await tester.tap(find.text('Run checks'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    pending.complete({'provider_configured': true, 'ok': true});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 320 pixel screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = _DiagnosticsHost();

    await tester.pumpWidget(_app(host.workspace('work'), textScale: 2));

    expect(find.text('Profile checks'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('More health actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More health actions'));
    await tester.pumpAndSettle();
    expect(find.text('Manage connections'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
