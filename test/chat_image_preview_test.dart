import 'package:wing/core/models/transcript_message.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wing/core/widgets/chat_image_preview.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';
import 'package:wing/core/widgets/resource_filename.dart';
import 'helpers/pump_markdown_widget.dart';

void main() {
  testWidgets('image preview opens on tap and returns to the conversation', (
    tester,
  ) async {
    await tester.pumpMarkdownWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileMessage(
            message: TranscriptMessage.fromRow(const {
              'role': 'assistant',
              'content': '![Result chart](/srv/chart.png)',
            }),
            loadAttachmentImage: (_) async => Uint8List.fromList(
              img.encodePng(img.Image(width: 120, height: 80)),
            ),
          ),
        ),
      ),
    );
    final thumbnail = find.descendant(
      of: find.byType(MarkdownMessageContent),
      matching: find.byType(Image),
    );
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(
        tester.widget<Image>(thumbnail).image,
        tester.element(thumbnail),
      ),
    );
    await tester.pumpAndSettle();
    expect(thumbnail, findsOneWidget);
    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    expect(find.byType(ChatImagePreview), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      tester.widget<ChatImagePreview>(find.byType(ChatImagePreview)).bytes,
      isNotNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatImagePreview), findsNothing);
    expect(thumbnail, findsOneWidget);
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
    expect(
      tester.getSize(find.byType(ResourceViewerAction)),
      const Size(32, 32),
    );
    expect(find.text('Open in browser'), findsNothing);
    await tester.tap(find.byTooltip('Open in browser'));
    expect(opened, isTrue);
  });
}
