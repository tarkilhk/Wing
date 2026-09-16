import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'support/profile_paging_fixture.dart';

void main() {
  late ProfilePagingFixture fixture;
  late ProfileWorkspaceController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = ProfilePagingFixture();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Paging QA',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'paging',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
  }

  Future<void> scroll(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 35 && !done(); i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(done(), isTrue);
  }

  testWidgets(
    'scroll loads through 100 chats and stops without duplicate pins',
    (tester) async {
      await show(tester);
      await scroll(tester, () => controller.current!.nextSessionOffset == null);
      expect(controller.current!.sessions.length, 125);
      expect(fixture.reads.length, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a page error keeps the list and exposes an explicit retry', (
    tester,
  ) async {
    fixture.pageFailures.add(('personal', 50));
    await show(tester);
    await scroll(tester, () => find.text('Retry').evaluate().isNotEmpty);
    expect(controller.current!.sessions.length, 51);
    expect(fixture.reads.length, 2);
    fixture.pageFailures.clear();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(controller.current!.sessions.length, 101);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'project scrolling reveals members locally and preserves old pins',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(460, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await controller.selectProject(controller.current!.projects.first);
      await show(tester);
      expect(find.text('Pinned chats'), findsOneWidget);
      expect(find.text('personal chat 120'), findsOneWidget);
      await scroll(
        tester,
        () => find.text('personal chat 110').evaluate().isNotEmpty,
      );
      expect(
        fixture.reads.length,
        1,
        reason: 'No invented project paging endpoint',
      );
      expect(controller.current!.projectSessions.length, 125);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, 10000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('personal other project'));
      await tester.pumpAndSettle();
      expect(find.text('personal other only'), findsOneWidget);
      expect(find.text('personal chat 110'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'search finds a chat beyond loaded pages without fetching the archive list',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), 'chat 110');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(fixture.reads.where((r) => r.$1 == 'sessions').length, 1);
      expect(find.text('personal chat 110'), findsOneWidget);
      expect(find.byKey(const ValueKey('load-more-chats')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
