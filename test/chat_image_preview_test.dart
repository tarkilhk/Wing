import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/chat_image_preview.dart';
import 'package:hermes_android/core/widgets/profile_message.dart';
import 'package:hermes_android/core/widgets/markdown_message_content.dart';

void main() {
  testWidgets('image preview opens on tap and returns to the conversation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: {
              'role': 'assistant',
              'content': '![Result chart](https://example.com/chart.png)',
            },
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(MarkdownMessageContent),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Result chart'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatImagePreview), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Open in browser'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatImagePreview), findsNothing);
    expect(find.text('Result chart'), findsOneWidget);
  });

  testWidgets('failed image has an external-open fallback', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatImagePreview(
          uri: Uri.parse('https://example.com/chart.png'),
          title: 'Result',
          onOpenExternal: () => opened = true,
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final context = tester.element(find.byType(Image));
    final fallback = image.errorBuilder!(
      context,
      StateError('Unavailable'),
      null,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: fallback)));
    expect(find.textContaining('could not be previewed'), findsOneWidget);
    await tester.tap(find.text('Open in browser'));
    expect(opened, isTrue);
  });
}
