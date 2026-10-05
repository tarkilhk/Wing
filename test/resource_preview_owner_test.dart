import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/owned_remote_files.dart';
import 'package:wing/core/services/pdf_preview_service.dart';
import 'package:wing/core/services/remote_files_client.dart';

class _Files implements RemoteFilesDataSource {
  final downloadResult = Completer<RemoteFileDownload>();
  String? profile;
  String? session;
  @override
  Future<RemoteTextPreview> readText(
    String path, {
    required String profileName,
    required String storedSessionId,
  }) => throw UnimplementedError();
  @override
  Future<RemoteFileDownload> download(
    String path, {
    required String profileName,
    required String storedSessionId,
  }) {
    profile = profileName;
    session = storedSessionId;
    return downloadResult.future;
  }
}

class _Pdf extends PdfPreviewService {
  final rendering = Completer<Uint8List>();
  final renderEntered = Completer<void>();
  final closed = <String>[];
  @override
  Future<PdfDocument> open(Uint8List bytes) async =>
      const PdfDocument('captured', 2);
  @override
  Future<Uint8List> render(PdfDocument document, int page) {
    renderEntered.complete();
    return rendering.future;
  }

  @override
  Future<void> close(PdfDocument document) async => closed.add(document.id);
}

void main() {
  test(
    'captured transport releases once and rejects its late result',
    () async {
      final source = _Files();
      var releases = 0;
      final owner = OwnedRemoteFiles(
        source: source,
        profileName: 'captured-profile',
        storedSessionId: 'captured-session',
        release: () => releases++,
      );
      final pending = owner.download('relative.png');
      final rejected = expectLater(pending, throwsStateError);
      owner.dispose();
      owner.dispose();
      source.downloadResult.complete(
        RemoteFileDownload(filename: 'relative.png', bytes: [1]),
      );
      await rejected;
      expect(releases, 1);
      expect(source.profile, 'captured-profile');
      expect(source.session, 'captured-session');
      await expectLater(owner.download('later.png'), throwsStateError);
    },
  );

  test('HTML retains the original failed decode for a single share', () async {
    final file = RemoteFileDownload(filename: 'report.html', bytes: [0xff]);
    final sharing = Completer<void>();
    var downloads = 0;
    var shares = 0;
    final reader = HtmlPreviewReader(
      download: () async {
        downloads++;
        return file;
      },
      share: (original) {
        expect(original, same(file));
        shares++;
        return sharing.future;
      },
    );
    addTearDown(reader.dispose);
    await reader.load();
    expect(reader.observation.source, isNull);
    expect(reader.observation.hasFile, isTrue);
    expect(reader.observation.error, contains("can't be read here"));
    final pending = reader.share();
    await reader.share();
    await reader.load();
    expect(shares, 1);
    expect(downloads, 1);
    expect(reader.observation.sharing, isTrue);
    sharing.complete();
    expect(await pending, isNull);
    expect(reader.observation.sharing, isFalse);
  });

  test(
    'closing HTML during download discards bytes and publications',
    () async {
      final download = Completer<RemoteFileDownload>();
      var publications = 0;
      final reader = HtmlPreviewReader(
        download: () => download.future,
        share: (_) async => fail('A closed HTML reader must not share'),
      )..addListener(() => publications++);
      final pending = reader.load();
      expect(publications, 1);
      reader.dispose();
      download.complete(
        RemoteFileDownload(
          filename: 'report.html',
          bytes: utf8.encode('<h1>x</h1>'),
        ),
      );
      await pending;
      expect(publications, 1);
      expect(reader.observation.source, isNull);
      expect(reader.observation.hasFile, isFalse);
      await reader.share();
    },
  );

  test(
    'closing PDF waits for the captured render before releasing native handle',
    () async {
      final service = _Pdf();
      final reader = service.createReader(
        () async => RemoteFileDownload(filename: 'report.pdf', bytes: [1]),
      );
      var publications = 0;
      reader.addListener(() => publications++);
      final pending = reader.load();
      await service.renderEntered.future;
      final beforeClose = publications;
      reader.dispose();
      expect(service.closed, isEmpty);
      service.rendering.complete(Uint8List.fromList([1, 2, 3]));
      await pending;
      expect(service.closed, ['captured']);
      expect(publications, beforeClose);
      expect(reader.observation.pageImage, isNull);
      reader.dispose();
      expect(service.closed, ['captured']);
    },
  );

  test(
    'decoded image facts copy bytes and retain distinct address admission',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final image = await acquireUserAttachmentImage(
        'remote.png',
        (_) async => bytes,
      );
      bytes[0] = 9;
      expect(image.bytes, [1, 2, 3]);
      expect(() => image.bytes![0] = 9, throwsUnsupportedError);
      var calls = 0;
      final windows = await acquireConversationImage(r'C:\images\x.png', (
        _,
      ) async {
        calls++;
        return Uint8List.fromList([4]);
      });
      expect(windows.bytes, [4]);
      expect(calls, 1);
      await expectLater(
        acquireUserAttachmentImage(r'C:\images\x.png', (_) async => bytes),
        throwsFormatException,
      );
      await expectLater(
        acquireConversationImage('file:///private/x.png', (_) async => bytes),
        throwsFormatException,
      );
      await expectLater(
        acquireUserAttachmentImage('data:text/plain;base64,eA==', null),
        throwsFormatException,
      );
      final embedded = await acquireUserAttachmentImage(
        'data:image/png;base64,AQID',
        null,
      );
      expect(embedded.bytes, [1, 2, 3]);
    },
  );
}
