import 'package:file_picker/file_picker.dart';

import 'remote_files_client.dart';

/// Saves authenticated bytes through Android's document destination picker.
/// A cancelled picker is not a failure and must not report a successful save.
Future<bool> saveRemoteFile(RemoteFileDownload file) async {
  if (file.bytes.length > RemoteFilesClient.defaultMaxDownloadBytes) {
    throw StateError('This file exceeds the 32 MiB download limit.');
  }
  final destination = await FilePicker.saveFile(
    fileName: file.filename,
    bytes: file.bytes,
  );
  return destination != null;
}
