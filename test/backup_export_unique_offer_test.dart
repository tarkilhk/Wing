import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/config_backup.dart';
import 'package:wing/core/services/config_backup_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent export offers keep distinct readable files and contents',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wing-distinct-backup-offers-',
      );
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final directoryResult = Completer<String>();
      final bothLookups = Completer<void>();
      final bothShares = Completer<void>();
      final shareResult = Completer<String>();
      var lookups = 0;
      final sharedPaths = <String>[];
      messenger.setMockMethodCallHandler(pathChannel, (call) {
        expect(call.method, 'getTemporaryDirectory');
        lookups++;
        if (lookups == 2) bothLookups.complete();
        return directoryResult.future;
      });
      messenger.setMockMethodCallHandler(shareChannel, (call) {
        expect(call.method, 'share');
        final paths = List<String>.from(
          (call.arguments as Map)['paths'] as List,
        );
        expect(paths, hasLength(1));
        sharedPaths.add(paths.single);
        if (sharedPaths.length == 2) bothShares.complete();
        return shareResult.future;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
        await directory.delete(recursive: true);
      });

      Future<String> contents(String theme) => ConfigBackupCodec.encode(
        ConfigBackup(
          createdAt: DateTime.utc(2026, 10, 4),
          appVersion: 'fixture',
          connections: [],
          preferences: {'theme_mode': theme},
        ),
        passphrase: '',
      );
      final firstContents = await contents('light');
      final secondContents = await contents('dark');
      final io = ConfigBackupIo();
      final first = io.deliverExport(firstContents, canDispatch: () => true);
      final second = io.deliverExport(secondContents, canDispatch: () => true);
      await bothLookups.future;
      expect(sharedPaths, isEmpty);
      directoryResult.complete(directory.path);
      await bothShares.future;

      // The offers overlap without relying on a wall-clock delay or timestamp.
      expect(sharedPaths.toSet(), hasLength(2));
      expect(
        await Future.wait(sharedPaths.map((path) => File(path).readAsString())),
        unorderedEquals([firstContents, secondContents]),
      );
      shareResult.complete('fixture-recipient');
      expect(await first, isNotNull);
      expect(await second, isNotNull);
      expect(
        await Future.wait(sharedPaths.map((path) => File(path).readAsString())),
        unorderedEquals([firstContents, secondContents]),
      );
    },
  );
}
