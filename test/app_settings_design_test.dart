import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/app_settings_content.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/theme/wing_theme.dart';

const _capture = bool.fromEnvironment('CAPTURE_SETTINGS');
const _frame = Key('settings-frame');

Future<void> _captureFrame(WidgetTester tester, String name) async {
  if (!_capture) return;
  final context = tester.element(find.byKey(_frame));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    await Future.wait(
      images.map((image) => precacheImage(image.image, context)),
    );
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frame),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/settings-review').createSync(recursive: true);
    await File(
      'build/settings-review/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _show(
  WidgetTester tester,
  SharedPreferences preferences, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  VoidCallback? onChanged,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('App settings')),
          body: AppSettingsContent(
            preferences: preferences,
            onChanged: onChanged ?? () {},
            enableNotifications: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Wing',
      packageName: 'com.tarkilhk.wing',
      version: '1.0.0',
      buildNumber: '2239',
      buildSignature: '',
    );
  });

  testWidgets(
    'no contribution entry is exposed before an account is configured',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await _show(tester, preferences);
      await tester.ensureVisible(find.byKey(const ValueKey('privacy-policy')));
      await tester.pumpAndSettle();
      expect(find.text('Support Wing'), findsNothing);
      expect(find.text('Buy me a coffee'), findsNothing);
    },
  );

  testWidgets(
    'saved theme and accent update the preview and survive reopening',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      var changes = 0;
      await _show(tester, preferences, onChanged: () => changes++);
      await tester.ensureVisible(find.byKey(const ValueKey('theme-dark')));
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('accent-iris')));
      await tester.tap(find.byKey(const ValueKey('accent-iris')));
      await tester.pumpAndSettle();
      final previewContext = tester.element(
        find.byKey(const ValueKey('appearance-preview')),
      );
      expect(Theme.of(previewContext).brightness, Brightness.dark);
      expect(
        Theme.of(previewContext).colorScheme.primary,
        WorkspaceAccent.iris.dark,
      );
      expect(preferences.getString('theme_mode'), 'dark');
      expect(preferences.getString(WorkspaceAccent.preferenceKey), 'iris');
      expect(changes, 2);
      await tester.pumpWidget(const SizedBox());
      await _show(tester, preferences);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('theme-dark')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('accent-iris')))
            .selected,
        isTrue,
      );
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('settings and text picker fit $brightness at ${scale}x', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final preferences = await SharedPreferences.getInstance();
        await _show(tester, preferences, brightness: brightness, scale: scale);
        await _captureFrame(tester, '${brightness.name}-$scale-appearance');
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Text size'));
        await tester.tap(find.text('Text size'));
        await tester.pumpAndSettle();
        await _captureFrame(tester, '${brightness.name}-$scale-text-size');
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Extra large'));
        await tester.tap(find.text('Extra large'));
        await tester.pumpAndSettle();
        expect(
          preferences.getString('app_text_size_preference'),
          'extra_large',
        );
        final queue = find.widgetWithText(ChoiceChip, 'Queue');
        await tester.ensureVisible(queue);
        await tester.pumpAndSettle();
        await tester.tap(queue);
        await tester.pumpAndSettle();
        expect(preferences.getString('composer_running_action'), 'queue');
        await tester.ensureVisible(
          find.byKey(const ValueKey('privacy-policy')),
        );
        await tester.pumpAndSettle();
        await _captureFrame(tester, '${brightness.name}-$scale-about');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
