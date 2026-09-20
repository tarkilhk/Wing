import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/remote_file_saver.dart';
import 'package:wing/core/services/remote_files_client.dart';

class _Picker extends FilePickerPlatform {
  String? filename;
  Uint8List? data;
  Uri? destination;
  Object? error;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    filename = fileName;
    data = bytes;
    if (error != null) throw error!;
    return destination;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  setUp(() {
    final original = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = original);
    picker = _Picker();
    FilePickerPlatform.instance = picker;
  });
  final file = RemoteFileDownload(
    filename: 'FULL_BANK_ANALYSIS.md',
    bytes: [35, 32, 65, 10],
  );

  test(
    'saves exact downloaded filename and bytes to the chosen destination',
    () async {
      picker.destination = Uri.parse('content://documents/report.md');
      expect(await saveRemoteFile(file), isTrue);
      expect(picker.filename, file.filename);
      expect(picker.data, file.bytes);
    },
  );
  test('cancel returns false and picker errors remain failures', () async {
    expect(await saveRemoteFile(file), isFalse);
    picker.error = PlatformException(code: 'write_failed');
    await expectLater(saveRemoteFile(file), throwsA(isA<PlatformException>()));
  });
  test(
    'oversized bytes never reach the picker, empty files can be saved',
    () async {
      await expectLater(
        saveRemoteFile(
          RemoteFileDownload(
            filename: 'too-large.bin',
            bytes: Uint8List(RemoteFilesClient.defaultMaxDownloadBytes + 1),
          ),
        ),
        throwsStateError,
      );
      expect(picker.filename, isNull);
      picker.destination = Uri.parse('content://documents/empty.txt');
      expect(
        await saveRemoteFile(
          RemoteFileDownload(filename: 'empty.txt', bytes: []),
        ),
        isTrue,
      );
      expect(picker.data, isEmpty);
    },
  );
}
