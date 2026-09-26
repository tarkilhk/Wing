import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/widgets/deliverable_attachment.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';

void main() {
  for (final deliverables in [false, true]) {
    testWidgets('retained Markdown uses current callbacks: $deliverables', (
      tester,
    ) async {
      final calls = <String>[];
      MarkdownMessageContent content(String owner, {bool enabled = true}) =>
          MarkdownMessageContent(
            data: '[Report](/srv/report.md)',
            deliverables: deliverables,
            onOpenRemoteFile: enabled ? (_) async => calls.add(owner) : null,
            onDownloadRemoteFile: enabled
                ? (_) async {
                    calls.add('$owner download');
                    return false;
                  }
                : null,
          );
      final value = ValueNotifier(content('old'));
      addTearDown(value.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<MarkdownMessageContent>(
              valueListenable: value,
              builder: (_, child, _) => child,
            ),
          ),
        ),
      );
      final original = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      value.value = content('new');
      await tester.pump();
      expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)),
        same(original),
      );
      if (deliverables) {
        await tester.tap(find.text('Open preview'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Download'));
        await tester.pumpAndSettle();
        expect(calls, ['new', 'new download']);
      } else {
        original.onTapLink!('Report', '/srv/report.md', '');
        await tester.pump();
        expect(calls, ['new']);
      }
      value.value = content('disabled', enabled: false);
      await tester.pump();
      expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)),
        isNot(same(original)),
      );
      if (deliverables) {
        final attachment = tester.widget<DeliverableAttachment>(
          find.byType(DeliverableAttachment),
        );
        expect(attachment.onOpen, isNull);
        expect(attachment.onDownload, isNull);
      }
    });
  }

  testWidgets(
    'content, theme and viewport changes invalidate retained rendering',
    (tester) async {
      var text = 'First **answer**';
      var dark = false;
      var width = 390.0;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return Theme(
                data: dark ? ThemeData.dark() : ThemeData.light(),
                child: MediaQuery(
                  data: MediaQueryData(size: Size(width, 800)),
                  child: Scaffold(body: MarkdownMessageContent(data: text)),
                ),
              );
            },
          ),
        ),
      );
      MarkdownBody body() =>
          tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      final first = body();
      change(() => text = 'Second **answer**');
      await tester.pump();
      expect(body().data, text);
      expect(body(), isNot(same(first)));
      final light = body();
      change(() => dark = true);
      await tester.pump();
      expect(body().styleSheet!.p!.color, isNot(light.styleSheet!.p!.color));
      final wide = body();
      change(() => width = 320);
      await tester.pump();
      expect(body(), isNot(same(wide)));
      expect(tester.takeException(), isNull);
    },
  );
}
