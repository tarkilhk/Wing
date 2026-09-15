import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/android_file_delivery_service.dart';
import 'package:wing/core/services/remote_files_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidFileDeliveryService.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'opens supported downloaded bytes with their exact filename and MIME',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return true;
          });
      const service = AndroidFileDeliveryService();
      final download = RemoteFileDownload(
        filename: 'server-report.pdf',
        bytes: <int>[0, 1, 127, 255],
      );

      expect(service.supportsType('server-report.pdf'), isTrue);
      expect(await service.openInApp(download), isTrue);
      expect(received?.method, 'openInApp');
      final arguments = received?.arguments as Map<Object?, Object?>;
      expect(arguments['filename'], 'server-report.pdf');
      expect(arguments['mimeType'], 'application/pdf');
      expect(
        arguments['bytes'] as Uint8List,
        orderedEquals(<int>[0, 1, 127, 255]),
      );
    },
  );

  test('limits handoff types and reports a missing viewer as false', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls++;
          return false;
        });
    const service = AndroidFileDeliveryService();

    expect(service.supportsType('notes.docx'), isFalse);
    expect(
      await service.openInApp(
        RemoteFileDownload(filename: 'notes.docx', bytes: <int>[1]),
      ),
      isFalse,
    );
    expect(calls, 0);
    expect(
      await service.openInApp(
        RemoteFileDownload(filename: 'recording.m4a', bytes: <int>[1, 2]),
      ),
      isFalse,
    );
    expect(calls, 1);
  });

  test('rejects invalid downloaded bytes without invoking Android', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          called = true;
          return true;
        });
    const service = AndroidFileDeliveryService();

    await expectLater(
      service.openInApp(
        RemoteFileDownload(filename: 'empty.pdf', bytes: const <int>[]),
      ),
      throwsA(isA<StateError>()),
    );
    expect(called, isFalse);
  });

  test('surfaces only a safe write or launch failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
            code: 'private-native-detail',
            message: '/private/cache/path',
          ),
        );
    const service = AndroidFileDeliveryService();

    await expectLater(
      service.openInApp(
        RemoteFileDownload(filename: 'clip.mp4', bytes: <int>[1]),
      ),
      throwsA(
        isA<StateError>()
            .having((error) => error.message, 'message', contains('could not'))
            .having(
              (error) => error.message,
              'private detail',
              isNot(contains('private')),
            ),
      ),
    );
  });

  test('reports a missing Android bridge as unavailable', () async {
    const service = AndroidFileDeliveryService();

    expect(
      await service.openInApp(
        RemoteFileDownload(filename: 'report.pdf', bytes: <int>[1]),
      ),
      isFalse,
    );
  });
}
