import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/config_backup_operation.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/backup_session.dart';
import 'package:wing/core/services/config_backup_io.dart';
import 'package:wing/core/services/config_backup_service.dart';
import 'package:wing/core/services/connection_manager.dart'
    show ConnectionManager, CredentialStore;

class _Credentials implements CredentialStore {
  final _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'closing during real export preparation prevents native share',
    () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      PackageInfo.setMockInitialValues(
        appName: 'Wing',
        packageName: 'com.tarkilhk.wing',
        version: 'fixture',
        buildNumber: '1',
        buildSignature: '',
      );
      final storage = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        storage,
        credentialStore: _Credentials(),
      );
      final owner = AppPreferences(storage);
      final session = BackupSession(
        configuration: ConfigBackupService(
          connectionManager: manager,
          appPreferences: owner,
        ),
        io: ConfigBackupIo(),
      );
      final directory = await Directory.systemTemp.createTemp(
        'wing-backup-export-lifetime-',
      );
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final directoryEntered = Completer<void>();
      final directoryResult = Completer<String>();
      var shareDispatches = 0;
      final sharedPaths = <String>[];
      messenger.setMockMethodCallHandler(pathChannel, (call) {
        expect(call.method, 'getTemporaryDirectory');
        directoryEntered.complete();
        return directoryResult.future;
      });
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'share');
        shareDispatches++;
        sharedPaths.addAll(
          List<String>.from((call.arguments as Map)['paths'] as List),
        );
        return 'fixture-recipient';
      });
      addTearDown(() async {
        session.close();
        owner.dispose();
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        await directory.delete(recursive: true);
      });

      var publications = 0;
      session.presentation.addListener(() => publications++);
      final attempt = session.beginExport()!;
      final pending = session.export(
        attempt,
        BackupExportIntent(passphrase: '', confirmation: ''),
      );
      await directoryEntered.future;
      expect(shareDispatches, 0);
      expect(await directory.list().toList(), isEmpty);
      final beforeClose = publications;

      session.close();
      directoryResult.complete(directory.path);
      final result = await pending;

      // Assert physical effects before the logical refusal/publication result.
      expect(shareDispatches, 0);
      expect(sharedPaths, isEmpty);
      expect(await directory.list().toList(), isEmpty);
      expect(result, isNull);
      expect(publications, beforeClose);
    },
  );

  test(
    'an admitted share keeps its file after session closure and settlement',
    () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      PackageInfo.setMockInitialValues(
        appName: 'Wing',
        packageName: 'com.tarkilhk.wing',
        version: 'fixture',
        buildNumber: '1',
        buildSignature: '',
      );
      final storage = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        storage,
        credentialStore: _Credentials(),
      );
      final owner = AppPreferences(storage);
      final session = BackupSession(
        configuration: ConfigBackupService(
          connectionManager: manager,
          appPreferences: owner,
        ),
        io: ConfigBackupIo(),
      );
      final directory = await Directory.systemTemp.createTemp(
        'wing-backup-share-settlement-',
      );
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final shareEntered = Completer<String>();
      final shareResult = Completer<String>();
      var shareDispatches = 0;
      messenger.setMockMethodCallHandler(pathChannel, (call) async {
        expect(call.method, 'getTemporaryDirectory');
        return directory.path;
      });
      messenger.setMockMethodCallHandler(shareChannel, (call) {
        expect(call.method, 'share');
        shareDispatches++;
        final paths = List<String>.from(
          (call.arguments as Map)['paths'] as List,
        );
        expect(paths, hasLength(1));
        shareEntered.complete(paths.single);
        return shareResult.future;
      });
      addTearDown(() async {
        session.close();
        owner.dispose();
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        await directory.delete(recursive: true);
      });

      var publications = 0;
      session.presentation.addListener(() => publications++);
      final pending = session.export(
        session.beginExport()!,
        BackupExportIntent(passphrase: '', confirmation: ''),
      );
      final sharedFile = File(await shareEntered.future);
      expect(shareDispatches, 1);
      final contents = await sharedFile.readAsString();
      final beforeClose = publications;

      session.close();
      expect(await sharedFile.readAsString(), contents);
      shareResult.complete('fixture-recipient');
      final result = await pending;

      // Chooser completion is not proof that the receiving app finished reading.
      expect(shareDispatches, 1);
      expect(await sharedFile.readAsString(), contents);
      expect(result, isNull);
      expect(publications, beforeClose);
    },
  );
}
