import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/pdf_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdf-test');
  const service = PdfPreviewService(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'opens exact bytes and addresses pages and disposal by native handle',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'open' => {'documentId': 'opaque-1', 'pageCount': 2},
          'render' => Uint8List.fromList([1, 2, 3]),
          _ => null,
        };
      });
      final bytes = Uint8List.fromList([37, 80, 68, 70]);
      final document = await service.open(bytes);
      expect(calls.single.arguments, {'bytes': bytes});
      expect(document.pageCount, 2);
      expect(await service.render(document, 1), [1, 2, 3]);
      expect(calls.last.arguments, {'documentId': 'opaque-1', 'page': 1});
      await expectLater(service.render(document, 2), throwsArgumentError);
      expect(calls, hasLength(2));
      await service.close(document);
      expect(calls.last.arguments, {'documentId': 'opaque-1'});
    },
  );

  test('invalid metadata releases the returned native document', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'open'
          ? {'documentId': 'bad-document', 'pageCount': 0}
          : null;
    });
    await expectLater(service.open(Uint8List.fromList([1])), throwsStateError);
    expect(calls.map((call) => call.method), ['open', 'close']);
    expect(calls.last.arguments, {'documentId': 'bad-document'});
  });

  test('invalid bytes and native failures remain safe', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      throw PlatformException(
        code: 'decoder',
        message: '/private/document.pdf SECRET',
      );
    });
    await expectLater(service.open(Uint8List(0)), throwsStateError);
    expect(calls, 0);
    await expectLater(
      service.open(Uint8List.fromList([1])),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'safe error',
          'This PDF could not be displayed.',
        ),
      ),
    );
    await service.close(const PdfDocument('gone', 1));
  });
}
