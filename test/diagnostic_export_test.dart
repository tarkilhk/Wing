import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/app_settings_content.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_diagnostics.dart';
import 'package:wing/core/services/diagnostic_export.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/theme/wing_theme.dart';

const _native = MethodChannel('com.tarkilhk.wing/diagnostics');
const _share = MethodChannel('dev.fluttercommunity.plus/share');
const _capture = bool.fromEnvironment('CAPTURE_DIAGNOSTICS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    if (!_capture) return;
    const directory = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final name in entry.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(File('$directory/$name').readAsBytesSync()),
          ),
        );
      }
      await loader.load();
    }
    await (FontLoader('WingProjectIcons')..addFont(
          File(
            'assets/fonts/codicons.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('WingIcons')..addFont(
          File(
            'assets/fonts/wing-icons.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_native, null);
    messenger.setMockMethodCallHandler(_share, null);
  });

  for (final outcome in ['success', 'dismissal', 'failure']) {
    test(
      'share $outcome retains ZIP until handoff settles and removes only its stage',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'wing-diagnostic-test-',
        );
        final stage = await Directory('${root.path}/stage').create();
        final archive = await File(
          '${stage.path}/wing-diagnostics.zip',
        ).writeAsString('fixture archive');
        final sibling = await File(
          '${root.path}/unrelated',
        ).writeAsString('keep');
        addTearDown(() => root.delete(recursive: true));
        final preparation = Completer<String>();
        final entered = Completer<void>();
        final delivery = Completer<String>();
        var exports = 0;
        messenger.setMockMethodCallHandler(_native, (call) {
          expect(call.method, 'export');
          exports++;
          return preparation.future;
        });
        messenger.setMockMethodCallHandler(_share, (call) {
          final args = call.arguments as Map;
          expect(args['paths'], [archive.path]);
          expect(args['mimeTypes'], ['application/zip']);
          entered.complete();
          return delivery.future;
        });
        final session = DiagnosticExportSession();
        addTearDown(session.dispose);
        final pending = session.share();
        expect(session.busy, isTrue);
        await session.share();
        preparation.complete(archive.path);
        await entered.future;
        expect(exports, 1);
        expect(await archive.exists(), isTrue);
        expect(session.busy, isTrue);
        if (outcome == 'failure') {
          delivery.completeError(
            PlatformException(
              code: 'unavailable',
              message: 'secret-native-message',
            ),
          );
        } else {
          delivery.complete(outcome == 'dismissal' ? '' : 'recipient');
        }
        await pending;
        expect(session.busy, isFalse);
        expect(
          session.error,
          outcome == 'failure' ? contains('Try again') : isNull,
        );
        expect(session.error, isNot(contains('secret-native-message')));
        expect(await stage.exists(), isFalse);
        expect(await sibling.readAsString(), 'keep');
      },
    );
  }

  test(
    'leaving during preparation retires the offer and cleans the completed ZIP',
    () async {
      final stage = await Directory.systemTemp.createTemp(
        'wing-diagnostic-retired-',
      );
      final archive = await File(
        '${stage.path}/bundle.zip',
      ).writeAsString('fixture');
      final prepared = Completer<String>();
      var shares = 0;
      messenger.setMockMethodCallHandler(_native, (_) => prepared.future);
      messenger.setMockMethodCallHandler(_share, (_) async {
        shares++;
        return 'recipient';
      });
      final session = DiagnosticExportSession();
      final pending = session.share();
      session.dispose();
      prepared.complete(archive.path);
      await pending;
      expect(shares, 0);
      expect(await stage.exists(), isFalse);
    },
  );

  test(
    'collection failure settles with retry and never opens sharing',
    () async {
      var shares = 0;
      messenger.setMockMethodCallHandler(
        _native,
        (_) async => throw PlatformException(code: 'disk_full'),
      );
      messenger.setMockMethodCallHandler(_share, (_) async {
        shares++;
        return 'recipient';
      });
      final session = DiagnosticExportSession();
      addTearDown(session.dispose);
      await session.share();
      expect(session.busy, isFalse);
      expect(session.error, contains('Try again'));
      expect(shares, 0);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'offline App settings share feedback ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          PackageInfo.setMockInitialValues(
            appName: 'Wing',
            packageName: 'com.tarkilhk.wing',
            version: '1.4.1',
            buildNumber: '2518',
            buildSignature: '',
          );
          final preferences = AppPreferences(
            await SharedPreferences.getInstance(),
          );
          addTearDown(preferences.dispose);
          var prepared = Completer<String>();
          var requests = 0;
          messenger.setMockMethodCallHandler(_native, (_) {
            requests++;
            return prepared.future;
          });
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: scale == 2,
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: AppSettingsContent(
                    preferences: preferences,
                    pluginServer: null,
                    createVoiceSession: () => throw StateError('not used'),
                    onChanged: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final action = find.byTooltip('Share diagnostic logs');
          await Scrollable.ensureVisible(
            tester.element(find.text('Diagnostic logs')),
            alignment: 0.15,
          );
          await tester.pumpAndSettle();
          await tester.tap(action);
          await tester.pump();
          expect(requests, 1);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is IconButton && w.tooltip == 'Share diagnostic logs',
                  ),
                )
                .onPressed,
            isNull,
          );
          await tester.pump(const Duration(milliseconds: 150));
          if (_capture) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(
                'build/feature-verification/diagnostics',
              );
              await directory.create(recursive: true);
              await File(
                '${directory.path}/pending-${brightness.name}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          prepared.completeError(PlatformException(code: 'disk_full'));
          await tester.pumpAndSettle();
          expect(
            find.text('Could not share diagnostic logs. Try again.'),
            findsOneWidget,
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          prepared = Completer<String>();
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pump();
          expect(requests, 2);
          await tester.pumpWidget(const SizedBox.shrink());
          prepared.completeError(PlatformException(code: 'retired'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test(
    'LED transitions retain causes without private labels and suppress unchanged observations',
    () {
      final records = <Map<String, dynamic>>[];
      connectionDiagnosticSink = (line) =>
          records.add(jsonDecode(line) as Map<String, dynamic>);
      addTearDown(() => connectionDiagnosticSink = null);
      final status = ServerConnectionStatus('private-server-label');
      addTearDown(status.dispose);
      status.accessAvailable();
      status.liveChanged('profile', true);
      status.accessAvailable();
      expect(records.length, 2);
      status.accessFailed(const SocketException('private-password'));
      expect(records.last['phase'], 'limited');
      expect(records.last['http'], 'unavailable');
      expect(records.last['live'], 'available');
      status.beginRecovery('profile');
      expect(records.last['phase'], 'reconnecting');
      expect(records.last['retry_active'], isTrue);
      expect(jsonEncode(records), isNot(contains('private-')));
    },
  );

  test(
    'durable capture excludes exception prose and unsafe stack context independently of console',
    () async {
      final savedFlutter = FlutterError.onError;
      final savedPlatform = ui.PlatformDispatcher.instance.onError;
      final savedPrint = debugPrint;
      final records = <String>[];
      messenger.setMockMethodCallHandler(_native, (call) async {
        records.add(call.arguments as String);
        return null;
      });
      addTearDown(() {
        FlutterError.onError = savedFlutter;
        ui.PlatformDispatcher.instance.onError = savedPlatform;
        debugPrint = savedPrint;
        connectionDiagnosticSink = null;
      });
      initializeDiagnosticCapture();
      debugPrint = (message, {wrapWidth}) =>
          throw StateError('console unavailable');
      logConnectionDiagnostic(
        'ws.stream_failed',
        error: const SocketException('password=secret-token conversation-text'),
        stackTrace: StackTrace.fromString(
          '#0 safe (package:wing/core/services/ws_client.dart:12:3)\nhttps://user:secret-token@server/chat',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final event = records
          .map((s) => jsonDecode(s) as Map)
          .firstWhere((e) => e['event'] == 'ws.stream_failed');
      expect(event['causes'], [
        {'type': 'SocketException'},
      ]);
      expect(event['stack'], [
        '#0 safe (package:wing/core/services/ws_client.dart:12:3)',
      ]);
      expect(records.join(), isNot(contains('secret-token')));
      expect(records.join(), isNot(contains('conversation-text')));
    },
  );
}
