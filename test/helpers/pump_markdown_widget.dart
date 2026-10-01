import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';

extension PumpMarkdownWidget on WidgetTester {
  Future<void> pumpMarkdownWidget(Widget widget) async {
    await pumpWidget(widget);
    await settleMarkdown();
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
