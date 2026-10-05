import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'config_backup.dart';

/// Platform-facing half of the backup feature: picking files, writing the
/// export, and handing it to the share sheet.
///
/// Storage and codec sequencing belong to BackupSession. This adapter cannot
/// read or write saved connections or app preferences.
class ConfigBackupIo {
  Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      // An unavailable package label does not change the configuration format.
      return 'unknown';
    }
  }

  /// Writes the backup to a temp file and offers it to the share
  /// sheet. Returns the file name, or null when the user dismisses the sheet.
  Future<String?> deliverExport(
    String contents, {
    required bool Function() canDispatch,
  }) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final directory = await getTemporaryDirectory();
    if (!canDispatch()) return null;

    // Each offer owns a distinct stage: a later export cannot overwrite a file
    // whose URI is still being read by a previously admitted recipient.
    Directory? stage;
    var dispatched = false;
    try {
      stage = await directory.createTemp('wing-backup-');
      if (!canDispatch()) return null;
      final file = File('${stage.path}/wing-config-$stamp.json');
      await file.writeAsString(contents, flush: true);
      if (!canDispatch()) return null;

      // Admission is the share API call. The plugin owns its ensuing native
      // preparation and chooser work; route closure cannot revoke that offer.
      dispatched = true;
      final result = await SharePlus.instance.share(
        ShareParams(
          subject: 'Wing configuration backup',
          files: <XFile>[XFile(file.path, mimeType: 'application/json')],
        ),
      );
      if (result.status == ShareResultStatus.dismissed) return null;
      return file.uri.pathSegments.last;
    } finally {
      // Never remove an admitted URI when its chooser completes: a recipient
      // may still be reading. Only this operation's undispatched stage is ours.
      if (!dispatched && stage != null) await stage.delete(recursive: true);
    }
  }

  Future<String?> pickBackupFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return null;

    return readBackupStream(picked.readAsByteStream());
  }

  /// Counts actual streamed bytes; provider-reported lengths are not trusted.
  static Future<String> readBackupStream(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in stream) {
      count += chunk.length;
      if (count > ConfigBackupLimits.maxBytes) {
        throw const ConfigBackupException(
          'This backup exceeds the 2 MiB limit.',
        );
      }
      bytes.add(chunk);
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const ConfigBackupException('This file is not a UTF-8 backup.');
    }
  }
}
