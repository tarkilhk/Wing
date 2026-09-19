import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/screens/administration/admin_operations_page.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/theme/wing_theme.dart';

import 'support/administration_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_RUN_ALL');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '/tmp/wing-header-fonts/${entry.value}',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/run-all-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('run all ${brightness.name} at $scale', (tester) async {
        final fixture = AdministrationFixture();
        final health = AdministrationHealth(fixture.server);
        addTearDown(health.dispose);
        addTearDown(fixture.server.close);
        final starts = Completer<void>();
        var doctorRunning = true;
        var auditRunning = true;
        fixture.override = (method, path, query, body) async {
          if (path.startsWith('ops/')) {
            await starts.future;
            return {'name': path.substring(4), 'pid': 7};
          }
          if (path.startsWith('actions/')) {
            final running = path.contains('/doctor/')
                ? doctorRunning
                : auditRunning;
            return {
              'pid': 7,
              'running': running,
              'exit_code': running ? null : 0,
              'lines': ['─' * 60, 'All checks passed! 🎉'],
            };
          }
          throw StateError('Unexpected $method $path');
        };
        tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: child!,
              ),
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Hermes health')),
              body: AdminHealthContent(
                server: fixture.server,
                health: health,
                accessChecks: () => null,
                profile: fixture.server.profile('default'),
                onRefresh: () async => fail('Must not refresh'),
                onOpenDestination: (_) async {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final runAll = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Run all diagnostics',
        );
        bool enabled() => tester.widget<IconButton>(runAll).onPressed != null;
        expect(enabled(), isTrue);
        expect(
          find.descendant(of: runAll, matching: find.byIcon(Icons.refresh)),
          findsOneWidget,
        );
        expect(find.byTooltip('Refresh health'), findsNothing);
        expect(find.textContaining('Runtime profile'), findsNothing);
        expect(fixture.requests, isEmpty);
        await snapshot(tester, '${brightness.name}-$scale-idle');
        await tester.tap(runAll);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AlertDialog), findsNothing);
        expect(enabled(), isFalse);
        expect(
          find.descendant(
            of: runAll,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(find.text('Starting…'), findsNWidgets(2));
        expect(
          fixture.requests.map((r) => r.$2),
          unorderedEquals(['ops/doctor', 'ops/security-audit']),
        );
        await tester.tap(runAll);
        await tester.pump();
        expect(fixture.requests, hasLength(2));
        await snapshot(tester, '${brightness.name}-$scale-starting');
        starts.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AdminActionPage), findsNothing);
        expect(find.textContaining('Running'), findsNWidgets(2));
        expect(enabled(), isFalse);
        expect(
          find.descendant(
            of: runAll,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        await snapshot(tester, '${brightness.name}-$scale-running');
        doctorRunning = false;
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(enabled(), isFalse);
        expect(
          find.descendant(
            of: runAll,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('No issues found'), findsOneWidget);
        auditRunning = false;
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(enabled(), isTrue);
        expect(
          find.descendant(of: runAll, matching: find.byIcon(Icons.refresh)),
          findsOneWidget,
        );
        expect(find.textContaining('Completed'), findsOneWidget);
        await snapshot(tester, '${brightness.name}-$scale-completed');
        expect(
          fixture.requests.every((r) => !r.$3.containsKey('profile')),
          isTrue,
        );
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(2));
        await tester.tap(runAll);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(4));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('one failed start does not prevent the other diagnostic', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    final health = AdministrationHealth(fixture.server);
    addTearDown(health.dispose);
    addTearDown(fixture.server.close);
    fixture.override = (method, path, query, body) async => switch (path) {
      'ops/doctor' => throw StateError('Doctor unavailable'),
      'ops/security-audit' => {'name': 'security-audit', 'pid': 8},
      'actions/security-audit/status' => {
        'pid': 8,
        'running': false,
        'exit_code': 1,
        'lines': ['Audit failed'],
      },
      _ => throw StateError('Unexpected $method $path'),
    };
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            RepaintBoundary(key: const ValueKey('capture'), child: child!),
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: AdminHealthContent(
            server: fixture.server,
            health: health,
            accessChecks: () => null,
            profile: null,
            onRefresh: () async {},
            onOpenDestination: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Run all diagnostics',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(2));
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Doctor:'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Review audit findings'), findsOneWidget);
    expect(health.diagnostics.keys, ['ops/security-audit']);
    expect(health.starting, isEmpty);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Run all diagnostics',
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await snapshot(tester, 'failed-start');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
