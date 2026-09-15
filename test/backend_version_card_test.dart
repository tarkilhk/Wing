import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/backend_update_controller.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/widgets/backend_version_card.dart';

const _available = <String, dynamic>{
  'current_version': '1.2.3',
  'install_method': 'pipx',
  'behind': 2,
  'update_available': true,
  'can_apply': true,
};

class _UpdateHost {
  Map<String, dynamic> checkResponse = _available;
  Map<String, dynamic> statusResponse = {
    'running': true,
    'pid': 41,
    'exit_code': null,
    'lines': <String>[],
  };
  Map<String, dynamic> postResponse = {
    'ok': true,
    'name': 'hermes-update',
    'pid': 41,
    'action_id': 'action-1',
  };
  Map<String, dynamic> receiptResponse = {
    'receipt': {
      'pid': 41,
      'finished_at': '2026-09-12T12:00:00Z',
      'outcome': 'success',
    },
    'summary': 'success',
  };
  Completer<Map<String, dynamic>>? pendingCheck;
  bool statusFails = false;
  final reads = <(String, Map<String, String>)>[];
  final posts = <(String, Map<String, dynamic>)>[];

  late final ProfileGateway gateway = ProfileGateway(
    scope: WorkspaceScope(connectionId: 'host', profileName: 'work'),
    get: (endpoint, query) async {
      reads.add((endpoint, query));
      if (endpoint == 'hermes/update/check') {
        return pendingCheck?.future ?? checkResponse;
      }
      if (endpoint == 'hermes/update/receipt') {
        return receiptResponse;
      }
      if (statusFails) {
        throw StateError('private disconnected detail');
      }
      return statusResponse;
    },
    post: (endpoint, body) async {
      posts.add((endpoint, body));
      return postResponse;
    },
    rpc: (_, _) async => <String, dynamic>{},
    discover: () async => const ProfileDiscovery(
      profiles: [],
      currentName: null,
      activeName: null,
    ),
  );
}

void main() {
  Future<void> showCard(
    WidgetTester tester,
    _UpdateHost host, {
    Size size = const Size(800, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackendVersionCard(
              gateway: host.gateway,
              connectionLabel: 'Production host',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> check(WidgetTester tester) async {
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
  }

  Future<void> openConfirmation(WidgetTester tester) async {
    await tester.tap(find.text('Update backend'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows version information only after a manual check', (
    tester,
  ) async {
    final host = _UpdateHost()
      ..checkResponse = {..._available, 'behind': 0, 'update_available': false};
    await showCard(tester, host);
    expect(host.reads, isEmpty);
    expect(find.text('Current version unavailable'), findsOneWidget);

    await check(tester);

    expect(host.reads, hasLength(1));
    expect(host.reads.single.$1, 'hermes/update/check');
    expect(host.reads.single.$2, {'force': 'true', 'profile': 'work'});
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('Install method: pipx'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Update backend'), findsNothing);
  });

  testWidgets('keeps malformed availability unknown and shows host guidance', (
    tester,
  ) async {
    final host = _UpdateHost()
      ..checkResponse = {
        'current_version': '1.2.3',
        'behind': -1,
        'update_available': 'yes',
        'can_apply': false,
      };
    await showCard(tester, host);
    await check(tester);

    expect(find.text('Update status unavailable.'), findsOneWidget);
    expect(
      find.text('Updates must be applied from the server host.'),
      findsOneWidget,
    );
    expect(find.text('Up to date'), findsNothing);
  });

  testWidgets('confirmation names the host and cancel does not post', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);

    expect(find.text('Update backend on Production host?'), findsOneWidget);
    expect(
      find.text(
        'This updates the whole Hermes host. All profiles on Production host may disconnect while the backend restarts.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(host.posts, isEmpty);
  });

  testWidgets('confirmed update rechecks eligibility and starts once', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Update backend').last);
    await tester.pumpAndSettle();

    expect(
      host.reads.where((call) => call.$1 == 'hermes/update/check'),
      hasLength(2),
    );
    expect(host.posts, hasLength(1));
    expect(host.posts.single.$1, 'hermes/update?profile=work');
    expect(
      find.text(
        'Backend update started for this host. Refresh status to follow it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('fresh check can refuse a previously advertised update', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    host.checkResponse = {
      ..._available,
      'update_available': false,
      'behind': 0,
    };
    await openConfirmation(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Update backend').last);
    await tester.pumpAndSettle();

    expect(host.posts, isEmpty);
    expect(
      find.text('The server reports no update is available.'),
      findsOneWidget,
    );
  });

  testWidgets('manual status refresh reports disconnection without retrying', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Update backend').last);
    await tester.pumpAndSettle();
    host.statusFails = true;

    await tester.tap(find.text('Refresh update status'));
    await tester.pumpAndSettle();

    expect(
      find.text('Backend update status is unavailable. Check again.'),
      findsOneWidget,
    );
    expect(host.posts, hasLength(1));
  });

  testWidgets('shows terminal outcome and expandable bounded output', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Update backend').last);
    await tester.pumpAndSettle();
    host.statusResponse = {
      'running': false,
      'pid': 41,
      'exit_code': 0,
      'action_id': 'action-1',
      'lines': ['Downloading', 'Applied core', 'Skipped optional'],
    };
    host.receiptResponse = {
      'receipt': {
        'pid': 41,
        'finished_at': '2026-09-12T12:00:00Z',
        'outcome': 'partial',
      },
      'summary': 'partial',
    };

    await tester.tap(find.text('Refresh update status'));
    await tester.pumpAndSettle();

    expect(
      find.text('The backend update completed only partially.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Recent update output'));
    await tester.pumpAndSettle();
    expect(
      find.text('Downloading\nApplied core\nSkipped optional'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(
        SelectableText,
        'Downloading\nApplied core\nSkipped optional',
      ),
      findsOneWidget,
    );
  });

  testWidgets('confirmation cannot start a replacement gateway', (
    tester,
  ) async {
    final first = _UpdateHost();
    final second = _UpdateHost();
    late StateSetter replace;
    var current = first;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            replace = setState;
            return BackendVersionCard(
              gateway: current.gateway,
              connectionLabel: current == first ? 'First host' : 'Second host',
            );
          },
        ),
      ),
    );
    await check(tester);
    await openConfirmation(tester);

    replace(() => current = second);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Update backend').last);
    await tester.pumpAndSettle();

    expect(first.posts, isEmpty);
    expect(second.posts, isEmpty);
  });

  testWidgets('external controller remains parent-owned after card disposal', (
    tester,
  ) async {
    final host = _UpdateHost();
    final external = BackendUpdateController(host.gateway);
    await external.checkForUpdate();
    await tester.pumpWidget(
      MaterialApp(
        home: BackendVersionCard(
          gateway: host.gateway,
          updateController: external,
        ),
      ),
    );
    expect(find.text('1.2.3'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    void listener() {}
    expect(() => external.addListener(listener), returnsNormally);
    external.removeListener(listener);
    external.dispose();
  });

  testWidgets('confirmation cannot start a replacement external controller', (
    tester,
  ) async {
    final first = _UpdateHost();
    final second = _UpdateHost();
    final firstController = BackendUpdateController(first.gateway);
    final secondController = BackendUpdateController(second.gateway);
    addTearDown(firstController.dispose);
    addTearDown(secondController.dispose);
    late StateSetter replace;
    var currentHost = first;
    var currentController = firstController;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            replace = setState;
            return BackendVersionCard(
              gateway: currentHost.gateway,
              updateController: currentController,
            );
          },
        ),
      ),
    );
    await check(tester);
    await openConfirmation(tester);

    replace(() {
      currentHost = second;
      currentController = secondController;
    });
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Update backend').last);
    await tester.pumpAndSettle();

    expect(first.posts, isEmpty);
    expect(second.posts, isEmpty);
  });

  testWidgets('late check response cannot cross gateway ownership', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final first = _UpdateHost()..pendingCheck = pending;
    final second = _UpdateHost();
    await tester.pumpWidget(
      MaterialApp(home: BackendVersionCard(gateway: first.gateway)),
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(home: BackendVersionCard(gateway: second.gateway)),
    );
    pending.complete(_available);
    await tester.pump();

    expect(find.text('1.2.3'), findsNothing);
    expect(find.text('Current version unavailable'), findsOneWidget);
  });

  testWidgets('disposed card ignores a late check response', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final host = _UpdateHost()..pendingCheck = pending;
    await tester.pumpWidget(
      MaterialApp(home: BackendVersionCard(gateway: host.gateway)),
    );
    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(_available);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions remain usable on a narrow large-text phone', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host, size: const Size(320, 640), textScale: 2);
    await check(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Update backend'));
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    expect(find.text('Update backend on Production host?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
