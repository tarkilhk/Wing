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

  testWidgets('all pages load in bounded requests and pins remain unique', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    final reads = fixture.reads
        .where((r) => r.$1 == 'sessions' && r.$2['limit'] == '100')
        .toList();
    expect(reads.length, 4);
    expect(reads.where((r) => r.$2['offset'] == '100').length, 2);
    expect(
      find.byKey(const ValueKey('chat-personal-chat-120')),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('Show all 123 chats'), findsWidgets);
  });
  testWidgets('page failure preserves rows and has an explicit retry', (
    tester,
  ) async {
    fixture.pageFailures.add(('personal', 100));
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not finish loading personal.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-personal-chat-120')),
      findsOneWidget,
    );
    fixture.pageFailures.clear();
    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();
    expect(find.text('Could not finish loading personal.'), findsNothing);
  });
  testWidgets(
    'search finds older chats across profiles without an archive scan',
    (tester) async {
      await show(tester);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'chat 110');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('personal chat 110'), findsOneWidget);
      expect(find.text('work chat 110'), findsOneWidget);
      expect(
        fixture.reads.where(
          (r) => r.$1 == 'sessions' && r.$2['archived'] == 'only',
        ),
        isEmpty,
      );
    },
  );
}
