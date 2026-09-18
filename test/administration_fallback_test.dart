import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_defaults_page.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';

import 'support/administration_fixture.dart';

// Stock contract inspected 2026-09-18 at upstream Hermes main
// c661785f872b5647fbac7c138d965180783bd9af:
// hermes_cli/fallback_config.py::_iter_fallback_entries accepts a map or list;
// web_routers/config_env.py::get_config returns that value unchanged.
const _entry = {
  'provider': 'example',
  'model': 'backup-model',
  'base_url': 'https://example.invalid/v1',
  'key_env': 'EXAMPLE_API_KEY',
};

Future<void> _open(WidgetTester tester, AdministrationFixture fixture) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AdminFallbackPage(
        profile: fixture.server.profile('default'),
        choices: const [ChatModelChoice(provider: 'example', model: 'second')],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _manage(WidgetTester tester, int index, String action) async {
  await tester.tap(find.byTooltip('Manage fallback $index'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_FALLBACK');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fallback ${brightness.name} at ${scale}x text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = AdministrationFixture('Claw');
        fixture.configs['default']!['fallback_providers'] = {..._entry};
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
              key: const ValueKey('capture'),
              child: AdminFallbackPage(
                profile: fixture.server.profile('default'),
                choices: const [],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('backup-model'), 100);
        expect(find.text('backup-model'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Add fallback'), 100);
        expect(find.text('Add fallback').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/fallback-review/${brightness.name}-$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }

  testWidgets('fallback screen loads a stock single-entry configuration', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.configs['default']!['fallback_providers'] = {..._entry};
    await _open(tester, fixture);
    expect(find.text('backup-model'), findsOneWidget);
    expect(find.text('Add fallback'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
  });

  for (final value in [
    null,
    <Object?>[],
    [_entry],
  ]) {
    testWidgets('fallback screen loads ${value.runtimeType}', (tester) async {
      final fixture = AdministrationFixture();
      fixture.configs['default']!['fallback_providers'] = value;
      await _open(tester, fixture);
      expect(find.text('Add fallback'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
    });
  }

  testWidgets('single-entry edits save an ordered list with route metadata', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.configs['default']!['fallback_providers'] = {..._entry};
    await _open(tester, fixture);
    await tester.tap(find.text('Add fallback'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second'));
    await tester.pumpAndSettle();
    expect(fixture.configs['default']!['fallback_providers'], [
      _entry,
      {'provider': 'example', 'model': 'second'},
    ]);
    await _manage(tester, 2, 'Move up');
    expect(fixture.configs['default']!['fallback_providers'], [
      {'provider': 'example', 'model': 'second'},
      _entry,
    ]);
    await _manage(tester, 1, 'Remove');
    await _manage(tester, 1, 'Remove');
    expect(fixture.configs['default']!['fallback_providers'], isEmpty);
    expect(find.textContaining('changed elsewhere'), findsNothing);
    final writes = fixture.requests.where((r) => r.$1 == 'PUT').toList();
    expect(writes, hasLength(4));
    for (final write in writes) {
      expect(write.$3['profile'], 'default');
      expect(write.$4!['profile'], 'default');
      expect((write.$4!['config'] as Map).keys, ['fallback_providers']);
    }
    expect(
      fixture.configs['personal']!.containsKey('fallback_providers'),
      false,
    );
  });

  testWidgets('external map change blocks saving until refreshed', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.configs['default']!['fallback_providers'] = {..._entry};
    await _open(tester, fixture);
    fixture.configs['default']!['fallback_providers'] = {
      ..._entry,
      'model': 'changed-model',
    };
    await _manage(tester, 1, 'Remove');
    expect(find.textContaining('changed elsewhere'), findsOneWidget);
    expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('changed-model'), findsOneWidget);
    await _manage(tester, 1, 'Remove');
    expect(fixture.configs['default']!['fallback_providers'], isEmpty);
  });

  testWidgets('unconfirmed save retains the last confirmed entry', (
    tester,
  ) async {
    final fixture = AdministrationFixture()..ignoreSave = true;
    fixture.configs['default']!['fallback_providers'] = {..._entry};
    await _open(tester, fixture);
    await _manage(tester, 1, 'Remove');
    expect(find.text('backup-model'), findsOneWidget);
    expect(find.textContaining('Save not confirmed'), findsOneWidget);
    fixture.ignoreSave = false;
    await _manage(tester, 1, 'Remove');
    expect(find.text('backup-model'), findsNothing);
    expect(fixture.configs['default']!['fallback_providers'], isEmpty);
  });

  testWidgets('a failed request can retry and load a single entry', (
    tester,
  ) async {
    final fixture = AdministrationFixture()..failReads = true;
    fixture.configs['default']!['fallback_providers'] = {..._entry};
    await _open(tester, fixture);
    expect(find.textContaining('Could not load'), findsOneWidget);
    fixture.failReads = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('backup-model'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
  });
}
