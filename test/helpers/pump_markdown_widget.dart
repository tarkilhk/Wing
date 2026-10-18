import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';

extension PumpMarkdownWidget on WidgetTester {
  Future<void> pumpMarkdownWidget(Widget widget) async {
    await pumpWidget(widget);
    await settleMarkdown();
  }

  Future<void> openLiveActivity() async {
    final section = find.byKey(const ValueKey('live-activity'));
    if (section.evaluate().isEmpty) {
      final retained = find.byKey(
        const ValueKey('live-activity'),
        skipOffstage: false,
      );
      if (retained.evaluate().isEmpty) return;
      final latest = find.byKey(const ValueKey('jump-to-latest'));
      expect(latest, findsOneWidget);
      await tap(latest);
      await pump();
      await pump(const Duration(milliseconds: 300));
    }
    final disclosures = find.descendant(
      of: section,
      matching: find.byType(ProfileActivitySection),
    );
    for (final element in disclosures.evaluate().toList()) {
      final disclosure = find.byElementPredicate(
        (candidate) => candidate == element,
      );
      final label = widget<ProfileActivitySection>(disclosure).label;
      final header = find.ancestor(
        of: find.descendant(of: disclosure, matching: find.text(label)),
        matching: find.byType(ListTile),
      );
      expect(header, findsOneWidget);
      final expand = find.descendant(
        of: header,
        matching: find.byIcon(Icons.keyboard_arrow_right_rounded),
      );
      if (expand.evaluate().isEmpty) {
        expect(
          find.descendant(
            of: header,
            matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
          ),
          findsOneWidget,
        );
        continue;
      }
      await ensureVisible(expand);
      await pump(const Duration(milliseconds: 300));
      expect(expand.hitTestable(), findsOneWidget);
      await tap(expand);
      await pump();
      await pump(const Duration(milliseconds: 300));
      await settleMarkdown();
      await pump();
    }
  }

  Future<void> settleMarkdown() async {
    for (var attempt = 0; attempt < 200; attempt++) {
      final pending = stateList<BackgroundMarkdownContentState>(
        find.byType(BackgroundMarkdownContent),
      ).any((state) => state.pending);
      if (!pending) return;
      await runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await pump(const Duration(milliseconds: 16));
    }
    fail('Background Markdown did not render the latest complete snapshot.');
  }
}
