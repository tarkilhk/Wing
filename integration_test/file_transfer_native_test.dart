import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/config_backup_io.dart';
import 'package:wing/core/services/connection_manager.dart';

/// Run with scripts/test_native_file_transfer.py on a disposable emulator.
/// The host selects fixture files and dismisses native dialogs at the markers.
/// No Hermes connection or real configuration is used.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const contents = '{"probe":"Wing native file transfer — ✓"}';
  late ConfigBackupIo backupIo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backupIo = ConfigBackupIo(
      connectionManager: ConnectionManager(
        await SharedPreferences.getInstance(),
      ),
    );
  });

  testWidgets('native metadata identifies the installed debug app', (_) async {
    final info = await PackageInfo.fromPlatform();
    expect(info.packageName, 'com.tarkilhk.wing.dev');
    expect(info.version, isNotEmpty);
    expect(int.tryParse(info.buildNumber), greaterThan(0));
  });

  testWidgets('backup import reads selected UTF-8 file', (_) async {
    debugPrint('FILE_TRANSFER:backup-select');
    expect(await backupIo.pickBackupFile(), contents);
  });

  testWidgets('cancelled backup import returns no contents', (_) async {
    debugPrint('FILE_TRANSFER:backup-cancel');
    expect(await backupIo.pickBackupFile(), isNull);
  });

  testWidgets('document attachment provides a readable local path', (_) async {
    debugPrint('FILE_TRANSFER:document-select');
    final file = await FilePicker.pickFile(type: FileType.any);
    expect(file, isNotNull);
    expect(file!.name, 'wing-native-probe.json');
    expect(file.path, isNotNull);
    expect(await File(file.path!).readAsString(), contents);
  });

  testWidgets('photo attachment provides a readable local PNG', (_) async {
    debugPrint('FILE_TRANSFER:photo-select');
    final file = await FilePicker.pickFile(type: FileType.image);
    expect(file, isNotNull);
    expect(file!.name, 'wing-native-probe.png');
    expect(file.path, isNotNull);
    expect(await File(file.path!).readAsBytes(), await file.readAsBytes());
    expect((await file.readAsBytes()).take(8), [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]);
  });

  testWidgets('cancelled attachment selection returns no file', (_) async {
    debugPrint('FILE_TRANSFER:document-cancel');
    expect(await FilePicker.pickFile(type: FileType.any), isNull);
  });

  testWidgets('backup export opens Android sharing and handles dismissal', (
    _,
  ) async {
    debugPrint('FILE_TRANSFER:share-cancel');
    expect(await backupIo.deliverExport(contents), isNull);
    final directory = await getTemporaryDirectory();
    final exports = directory.listSync().whereType<File>().where(
      (file) => file.uri.pathSegments.last.startsWith('wing-config-'),
    );
    expect(exports, isNotEmpty);
    expect(await exports.last.readAsString(), contents);
    for (final file in exports) {
      await file.delete();
    }
  });
}
