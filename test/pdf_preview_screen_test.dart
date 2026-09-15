import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/pdf_preview_screen.dart';
import 'package:wing/core/services/pdf_preview_service.dart';
import 'package:wing/core/services/remote_files_client.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2ioAAAAASUVORK5CYII=',
);

class _PdfService extends PdfPreviewService {
  Future<PdfDocument> Function(Uint8List bytes)? opening;
  Future<Uint8List> Function(int page)? rendering;
  final rendered = <int>[];
  final closed = <String>[];
  final openedBytes = <Uint8List>[];

  @override
  Future<PdfDocument> open(Uint8List bytes) async {
    openedBytes.add(bytes);
    return opening == null
        ? const PdfDocument('doc', 2)
        : await opening!(bytes);
  }

  @override
  Future<Uint8List> render(PdfDocument document, int page) async {
    rendered.add(page);
    return rendering == null ? _png : await rendering!(page);
  }

  @override
  Future<void> close(PdfDocument document) async => closed.add(document.id);
}

Widget _app(
  _PdfService service,
  Future<RemoteFileDownload> Function() download,
) => MaterialApp(
  home: PdfPreviewScreen(
    title: 'Report.pdf',
    service: service,
    download: download,
  ),
);

void main() {
  testWidgets('reads pages from one download and releases document on close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _PdfService();
    var downloads = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: PdfPreviewScreen(
          title: 'Report.pdf',
          service: service,
          download: () async {
            downloads++;
            return RemoteFileDownload(filename: 'report.pdf', bytes: [1, 2, 3]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(service.openedBytes.single, [1, 2, 3]);
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pump();
    expect(service.rendered, [0]);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(service.rendered, [0, 1]);
    expect(downloads, 1);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pump();
    expect(service.rendered, [0, 1]);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.closed, ['doc']);
  });

  testWidgets('closing during download never creates a native document', (
    tester,
  ) async {
    final service = _PdfService();
    final download = Completer<RemoteFileDownload>();
    await tester.pumpWidget(_app(service, () => download.future));
    await tester.pumpWidget(const SizedBox.shrink());
    download.complete(RemoteFileDownload(filename: 'report.pdf', bytes: [1]));
    await tester.pump();
    expect(service.openedBytes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during native open releases its late handle', (
    tester,
  ) async {
    final open = Completer<PdfDocument>();
    final service = _PdfService()..opening = (_) => open.future;
    await tester.pumpWidget(
      _app(
        service,
        () async => RemoteFileDownload(filename: 'report.pdf', bytes: [1]),
      ),
    );
    await tester.pump();
    expect(service.openedBytes, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    open.complete(const PdfDocument('late', 2));
    await tester.pump();
    expect(service.closed, ['late']);
    expect(service.rendered, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page failure retries without another download or native open', (
    tester,
  ) async {
    var fail = true;
    final service = _PdfService()
      ..rendering = (_) async {
        if (fail) throw StateError('PRIVATE DOCUMENT DETAIL');
        return _png;
      };
    var downloads = 0;
    await tester.pumpWidget(
      _app(service, () async {
        downloads++;
        return RemoteFileDownload(filename: 'report.pdf', bytes: [1]);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be displayed'), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(service.openedBytes, hasLength(1));
    expect(downloads, 1);
    expect(service.rendered, [0, 0]);
    expect(tester.takeException(), isNull);
  });
}
