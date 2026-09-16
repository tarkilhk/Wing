import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:wing/core/config/support_wing.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/support_wing_section.dart';

// Uses the configured destination with a fake launcher; makes no network calls.
final _testUri = wingSupportUri;
const _frame = Key('support-frame');
const _capture = bool.fromEnvironment('CAPTURE_SUPPORT');

class _Browser extends UrlLauncherPlatform {
  final calls = <(String, LaunchOptions)>[];
  Future<bool> Function() result = () async => true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) {
    calls.add((url, options));
    return result();
  }
}

Future<void> _show(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: wingTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: _frame,
        child: Scaffold(
          appBar: AppBar(title: const Text('App settings')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(WingSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'About',
                  style: wingTheme(brightness).textTheme.titleMedium,
                ),
                const SizedBox(height: WingSpacing.md),
                Card(child: SupportWingSection(uri: _testUri)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _captureFrame(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frame),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/support-review').createSync(recursive: true);
    File(
      'build/support-review/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late UrlLauncherPlatform original;
  late _Browser browser;

  setUpAll(() async {
    const directory = String.fromEnvironment('CAPTURE_FONT_DIR');
    if (directory.isEmpty) return;
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
  });

  setUp(() {
    original = UrlLauncherPlatform.instance;
    browser = _Browser();
    UrlLauncherPlatform.instance = browser;
  });
  tearDown(() => UrlLauncherPlatform.instance = original);

  test('app, README and GitHub funding use the supplied Ko-fi account', () {
    expect(wingSupportUri.toString(), 'https://ko-fi.com/tarkil');
    expect(
      File('README.md').readAsStringSync(),
      contains('[Buy me a coffee](https://ko-fi.com/tarkil)'),
    );
    expect(
      File('.github/FUNDING.yml').readAsStringSync().trim(),
      'ko_fi: tarkil',
    );
  });

  testWidgets('opens only on request, externally, without extra data', (
    tester,
  ) async {
    await _show(tester);
    expect(browser.calls, isEmpty);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(browser.calls.single.$1, _testUri.toString());
    final options = browser.calls.single.$2;
    expect(options.mode, PreferredLaunchMode.externalApplication);
    expect(options.webViewConfiguration.headers, isEmpty);
  });

  for (final throws in [false, true]) {
    testWidgets('browser failure (throws: $throws) allows retry', (
      tester,
    ) async {
      browser.result = () async {
        if (throws) throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
        return false;
      };
      await _show(tester);
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not open your browser.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SelectableText, _testUri.toString()),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      browser.result = () async => true;
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(browser.calls, hasLength(2));
      expect(find.textContaining('Could not open your browser.'), findsNothing);
    });
  }

  testWidgets('pending launch prevents duplicates and tolerates leaving', (
    tester,
  ) async {
    final pending = Completer<bool>();
    browser.result = () => pending.future;
    await _show(tester);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(OutlinedButton));
    expect(browser.calls, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('accessible $brightness support at ${scale}x and 320dp', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 1000);
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          await _show(tester, brightness: brightness, scale: scale);
          expect(tester.takeException(), isNull);
          expect(find.text('Support Wing'), findsOneWidget);
          expect(
            find.text(
              'If Wing is useful in your day, you can buy me a coffee and help me keep improving it.',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Completely optional. Every feature is available either way.',
            ),
            findsOneWidget,
          );
          // Large text can place the action below the viewport.
          await tester.ensureVisible(find.byType(OutlinedButton));
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(find.byType(OutlinedButton)),
            matchesSemantics(
              label: 'Buy me a coffee',
              hint: 'Opens Ko-fi in your browser',
              isButton: true,
              isEnabled: true,
              hasEnabledState: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await _captureFrame(tester, '${brightness.name}-$scale');
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(browser.calls, hasLength(1));
          browser.result = () async => false;
          await tester.tap(find.byType(OutlinedButton));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(SelectableText));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _captureFrame(tester, '${brightness.name}-$scale-error');
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
