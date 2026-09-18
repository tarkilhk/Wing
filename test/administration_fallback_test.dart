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

// Desktop contract inspected 2026-09-19 at upstream Hermes main
// 21642218445e213b02ea7158f71214022645c9c6:
// apps/desktop/src/app/settings/fallback-models-field.tsx normalizes strings,
// retains incomplete local rows, and emits only complete pairs on edits.
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
  for (final invalid in <Object?>[null, 42, false, {}]) {
    testWidgets('incomplete ${invalid.runtimeType} is an editable draft', (
      tester,
    ) async {
      final fixture = AdministrationFixture();
      fixture.configs['default']!['fallback_providers'] = [invalid, _entry];
      await _open(tester, fixture);
      expect(find.text('Choose model'), findsOneWidget);
      expect(find.text('backup-model'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
      expect(find.text('Invalid fallback entry'), findsNothing);
      expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
      await tester.tap(find.text('Choose model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('second'));
      await tester.pumpAndSettle();
      expect(fixture.configs['default']!['fallback_providers'], [
        {'provider': 'example', 'model': 'second'},
        _entry,
      ]);
    });
  }

  testWidgets(
    'desktop strings normalize and incomplete drafts survive saves locally',
    (tester) async {
      final fixture = AdministrationFixture();
      fixture.configs['default']!['fallback_providers'] = [
        'example/team/model',
        'model-only',
        null,
        _entry,
      ];
      await _open(tester, fixture);
      expect(find.text('team/model'), findsOneWidget);
      expect(find.text('model-only'), findsOneWidget);
      expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
      await tester.tap(find.text('Add fallback'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('second'));
      await tester.pumpAndSettle();
      expect(fixture.configs['default']!['fallback_providers'], [
        {'provider': 'example', 'model': 'team/model'},
        _entry,
        {'provider': 'example', 'model': 'second'},
      ]);
      expect(find.text('model-only'), findsOneWidget);
      expect(find.text('Choose model'), findsOneWidget);
      await _manage(tester, 4, 'Move up');
      expect(fixture.configs['default']!['fallback_providers'], [
        {'provider': 'example', 'model': 'team/model'},
        _entry,
        {'provider': 'example', 'model': 'second'},
      ]);
      await _manage(tester, 1, 'Remove');
      expect(fixture.configs['default']!['fallback_providers'], [
        _entry,
        {'provider': 'example', 'model': 'second'},
      ]);
      expect(find.textContaining('changed elsewhere'), findsNothing);
    },
  );

  testWidgets('editing a row preserves its routing fields', (tester) async {
    final fixture = AdministrationFixture();
    fixture.configs['default']!['fallback_providers'] = [_entry];
    await _open(tester, fixture);
    await tester.tap(find.text('backup-model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second'));
    await tester.pumpAndSettle();
    expect(fixture.configs['default']!['fallback_providers'], [
      {..._entry, 'model': 'second'},
    ]);
  });

  testWidgets('changes to incomplete raw data still block saving', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.configs['default']!['fallback_providers'] = [null, _entry];
    await _open(tester, fixture);
    fixture.configs['default']!['fallback_providers'] = [false, _entry];
    await _manage(tester, 2, 'Remove');
    expect(find.textContaining('changed elsewhere'), findsOneWidget);
    expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
  });

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
        fixture.configs['default']!['fallback_providers'] = [null, _entry];
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
        await tester.scrollUntilVisible(find.text('Choose model'), 100);
        expect(find.text('Choose model'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byTooltip('Manage fallback 1'),
          100,
        );
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Manage fallback 1').hitTestable(),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(find.text('backup-model'), 100);
        expect(find.text('backup-model'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Add fallback'), 100);
        await tester.pumpAndSettle();
        expect(find.text('Add fallback').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.drag(find.byType(ListView), const Offset(0, 1000));
          await tester.pumpAndSettle();
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

  for (final value in <Object?>[
    {..._entry},
    'example/model',
    42,
  ]) {
    testWidgets('non-list ${value.runtimeType} opens empty like desktop', (
      tester,
    ) async {
      final fixture = AdministrationFixture();
      fixture.configs['default']!['fallback_providers'] = value;
      await _open(tester, fixture);
      expect(find.text('No fallback models configured.'), findsOneWidget);
      expect(find.text('Add fallback'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
      expect(fixture.requests.where((r) => r.$1 == 'PUT'), isEmpty);
    });
  }

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

  testWidgets('list edits save an ordered list with route metadata', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.configs['default']!['fallback_providers'] = [_entry];
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

  testWidgets('external list change blocks saving until refreshed', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.configs['default']!['fallback_providers'] = [_entry];
    await _open(tester, fixture);
    fixture.configs['default']!['fallback_providers'] = [
      {..._entry, 'model': 'changed-model'},
    ];
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
    fixture.configs['default']!['fallback_providers'] = [_entry];
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
    fixture.configs['default']!['fallback_providers'] = [_entry];
    await _open(tester, fixture);
    expect(find.textContaining('Could not load'), findsOneWidget);
    fixture.failReads = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('backup-model'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
  });
}
