import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/widgets/workspace_connection_status.dart';

void main() {
  late ServerConnectionStatus status;

  setUp(() {
    status = ServerConnectionStatus('Host')
      ..accessAvailable()
      ..liveChanged('chat', true);
  });
  tearDown(() => status.dispose());

  Future<void> render(
    WidgetTester tester, {
    bool showHint = true,
    bool reducedMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: Column(
            children: [
              WorkspaceConnectionStatus(status: status, showHint: showHint),
            ],
          ),
        ),
      ),
    ),
  );

  final bar = find.byKey(const ValueKey('workspace-connection-status'));

  testWidgets('short reconnects never open the connection bar', (tester) async {
    await render(tester);
    expect(tester.getSize(bar).height, 0);
    status.beginRecovery('chat');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSize(bar).height, 0);
    status.endRecovery('chat');
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getSize(bar).height, 0);
    expect(find.textContaining('Reconnecting'), findsNothing);
  });

  testWidgets(
    'connection notice animates both ways and hides stale semantics',
    (tester) async {
    final semantics = tester.ensureSemantics();
      await render(tester);
      status.beginRecovery('chat');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 60));
      final entering = tester.getSize(bar).height;
      expect(entering, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 200));
      final expanded = tester.getSize(bar).height;
      expect(expanded, greaterThan(entering));
      expect(
        find.bySemanticsLabel('Reconnecting… Your draft stays here.'),
        findsOneWidget,
      );

      status.endRecovery('chat');
      await tester.pump();
      expect(
        find.bySemanticsLabel('Reconnecting… Your draft stays here.'),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getSize(bar).height, inExclusiveRange(0, expanded));
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, 0);

      status.failRecovery('chat', 'History unavailable');
      await tester.pumpAndSettle();
      expect(
        find.text('Chat unavailable · Your draft stays here.'),
        findsOneWidget,
      );
      await render(tester, showHint: false);
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, 0);
      expect(
        find.text('Chat unavailable · Your draft stays here.'),
        findsNothing,
      );
      await render(tester);
      await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, expanded);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    },
  );

  testWidgets(
    'reduced motion changes height immediately after the grace period',
    (tester) async {
      await render(tester, reducedMotion: true);
      status.beginRecovery('chat');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(bar).height, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getSize(bar).height, greaterThan(0));
      status.endRecovery('chat');
      await tester.pump();
      expect(tester.getSize(bar).height, 0);
    },
  );
}
