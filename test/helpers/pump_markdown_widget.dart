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
      final icon = widget<Icon>(
        find.descendant(of: disclosure, matching: find.byType(Icon)).first,
      );
      if (icon.icon != Icons.keyboard_arrow_right_rounded) continue;
      final label = (element.widget as ProfileActivitySection).label;
      final title = find
          .descendant(of: disclosure, matching: find.text(label))
          .first;
      await ensureVisible(title);
      await pump(const Duration(milliseconds: 300));
      final rect = getRect(title);
      await tapAt(Offset(rect.left + 4, rect.center.dy));
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
