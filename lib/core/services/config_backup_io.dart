import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'config_backup.dart';
import 'config_backup_service.dart';
import 'connection_manager.dart';

/// Platform-facing half of the backup feature: picking files, writing the
/// export, and handing it to the share sheet.
///
/// Kept apart from [ConfigBackupService] so the pure logic stays testable, and
/// shared by App settings and the first-connection welcome screen.
class ConfigBackupIo {
  final ConnectionManager connectionManager;

  ConfigBackupIo({required this.connectionManager});

  ConfigBackupService get _service => ConfigBackupService(
    connectionManager: connectionManager,
    preferences: connectionManager.prefs,
  );

  Future<String> exportBackup(String passphrase) async {
    String appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } catch (_) {
      appVersion = 'unknown';
    }
    final backup = await _service.export(appVersion: appVersion);
    return ConfigBackupCodec.encode(backup, passphrase: passphrase);
  }

  /// Writes the backup to a temp file and offers it to the share
  /// sheet. Returns the file name, or null when the user dismisses the sheet.
  Future<String?> deliverExport(String contents) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/wing-config-$stamp.json');
    await file.writeAsString(contents, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(
        subject: 'Wing configuration backup',
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
      ),
    );
    if (result.status == ShareResultStatus.dismissed) return null;
    return file.uri.pathSegments.last;
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

  Future<ConfigImportResult> importBackup(
    String contents,
    String passphrase,
    ConfigImportMode mode,
  ) async {
    final backup = await ConfigBackupCodec.decode(
      contents,
      passphrase: passphrase,
    );
    return _service.import(backup, mode: mode);
  }
}
