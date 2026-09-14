import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/media_preview_service.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MediaPreviewService.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('opens exact downloaded bytes with title and resolved MIME', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });
    const service = MediaPreviewService();

    expect(service.supportsType('recording.M4A'), isTrue);
    expect(service.supportsType('report.pdf'), isFalse);
    expect(
      await service.open(
        RemoteFileDownload(filename: 'recording.M4A', bytes: [0, 1, 255]),
        title: 'Meeting recording',
        appearance: const {
          'dark': 1,
          'surface': 0xFF101917,
          'accent': 0xFFA6E3CB,
        },
      ),
      isTrue,
    );
    expect(received?.method, 'open');
    final arguments = received?.arguments as Map<Object?, Object?>;
    expect(arguments['title'], 'Meeting recording');
    expect(arguments['mimeType'], 'audio/mp4');
    expect(arguments['bytes'] as Uint8List, orderedEquals([0, 1, 255]));
    expect(arguments['appearance'], {
      'dark': 1,
      'surface': 0xFF101917,
      'accent': 0xFFA6E3CB,
    });
  });

  test(
    'uses supported supplied MIME and rejects empty or oversized media',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            return true;
          });
      const service = MediaPreviewService();

      expect(
        service.supportsType(
          'unknown.bin',
          mimeType: 'video/webm; charset=utf-8',
        ),
        isTrue,
      );
      await expectLater(
        service.open(
          RemoteFileDownload(filename: 'empty.mp3', bytes: []),
          title: 'Empty',
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.open(
          RemoteFileDownload(
            filename: 'large.mp3',
            bytes: Uint8List(MediaPreviewService.maxBytes + 1),
          ),
          title: 'Large',
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'redacts native errors and treats a missing bridge as unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(
              code: 'private-native-detail',
              message: '/private/cache/recording.mp3',
            ),
          );
      const service = MediaPreviewService();
      final file = RemoteFileDownload(filename: 'recording.mp3', bytes: [1]);

      await expectLater(
        service.open(file, title: 'Recording'),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('could not'),
              )
              .having(
                (error) => error.message,
                'private detail',
                isNot(contains('private')),
              ),
        ),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await service.open(file, title: 'Recording'), isFalse);
    },
  );
}
