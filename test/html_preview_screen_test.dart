import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/chat_output.dart';
import 'package:wing/core/screens/chat_outputs_screen.dart';
import 'package:wing/core/screens/html_preview_screen.dart';
import 'package:wing/core/services/remote_files_client.dart';
import 'package:wing/core/widgets/web_output_preview.dart';

void main() {
  testWidgets('chat HTML opens full viewer and Back returns directly to chat', (
    tester,
  ) async {
    const path = '/srv/reports/index.html';
    const source = '<!doctype html><h1>Full report</h1>';
    final downloads = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatOutputsScreen(
                    chatTitle: 'Report chat',
                    initialOutput: const ChatOutput(
                      kind: ChatOutputKind.file,
                      path: path,
                      url: null,
                      label: 'index.html',
                    ),
                    loadHistory: (_) => throw StateError('Unneeded history'),
                    readText: (path) async => RemoteTextPreview(
                      path: path,
                      text: '<!doctype html><h1>Full',
                      language: 'text',
                      mimeType: 'text/plain',
                      byteSize: source.length,
                      binary: false,
                      truncated: true,
                    ),
                    download: (path) async {
                      downloads.add(path);
                      return RemoteFileDownload(
                        filename: 'index.html',
                        bytes: utf8.encode(source),
                      );
                    },
                  ),
                ),
              ),
              child: const Text('Open preview'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    expect(downloads, [path]);
    final viewer = tester.widget<WebOutputPreview>(
      find.byType(WebOutputPreview),
    );
    expect(viewer.source, source);
    expect(viewer.format, WebOutputFormat.html);
    expect(find.textContaining('Preview shortened'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open preview'), findsOneWidget);
    expect(find.byType(ChatOutputsScreen), findsNothing);
  });

  testWidgets('download failure offers retry and renders the retried file', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: HtmlPreviewScreen(
          title: 'index.html',
          download: () async {
            if (++calls == 1) throw TimeoutException('test');
            return RemoteFileDownload(
              filename: 'index.html',
              bytes: utf8.encode('<h1>Report</h1>'),
            );
          },
          share: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be reached'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(WebOutputPreview), findsOneWidget);
  });

  testWidgets(
    'invalid UTF-8 offers original file without rendering partial HTML',
    (tester) async {
      final file = RemoteFileDownload(filename: 'index.html', bytes: [0xff]);
      RemoteFileDownload? shared;
      var downloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HtmlPreviewScreen(
            title: 'index.html',
            download: () async {
              downloads++;
              return file;
            },
            share: (file) async => shared = file,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("can't be read here"), findsOneWidget);
      expect(find.byType(WebOutputPreview), findsNothing);
      await tester.tap(find.text('Save or share'));
      await tester.pumpAndSettle();
      expect(shared, same(file));
      expect(downloads, 1);
    },
  );
}
