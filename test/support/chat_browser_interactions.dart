import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> filterChatsToProfile(WidgetTester tester, String name) async {
  final filter = find.byKey(const ValueKey('chat-filter-profile'));
  if (filter.evaluate().isEmpty) return;
  await tester.tap(filter);
  await tester.pumpAndSettle();
  final choice = find.byKey(ValueKey('chat-menu-$name'));
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

Future<void> revealChatProject(
  WidgetTester tester,
  String profile,
  String id,
) async {
  final row = find.byKey(ValueKey('project-$profile-$id'));
  await tester.scrollUntilVisible(
    row,
    220,
    scrollable: find
        .descendant(
          of: find.byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.vertical,
          ),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(tester.element(row), alignment: 0.4);
  await tester.pumpAndSettle();
}
