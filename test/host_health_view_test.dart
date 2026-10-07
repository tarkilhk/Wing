import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_host_health.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/services/host_resources_session.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/host_resources_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_HOST_HEALTH');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final (family, file) in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(
            File(
              '$root/$file',
            ).readAsBytes().then((b) => b.buffer.asByteData()),
          ))
          .load();
    }
  });
  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('host-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = File('build/host-health/$name.png');
      await path.parent.create(recursive: true);
      await path.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final scenario in [
        'normal',
        'loading',
        'limited',
        'pressure',
        'error',
      ]) {
        testWidgets('Host ${brightness.name} $scale $scenario', (tester) async {
          final fixture = HostResourcesFixture();
          final session = HostResourcesSession(fixture.server);
          final health = AdministrationHealth(fixture.server);
          if (scenario == 'loading') fixture.statsGate = Completer();
          if (scenario == 'limited') {
            fixture.stats['psutil'] = false;
            for (final key in [
              'cpu_percent',
              'memory',
              'disk',
              'uptime_seconds',
              'process',
            ]) {
              fixture.stats.remove(key);
            }
          }
          if (scenario == 'pressure') {
            (fixture.pressure['memory'] as Map)['pressure'] = 'critical';
            (fixture.pressure['disk'] as Map)['pressure'] = 'elevated';
          }
          if (scenario == 'error') {
            await session.refresh();
            fixture.statsError = StateError('offline');
          }
          tester.view.physicalSize = Size(scale == 2 ? 320 : 393, 852);
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
                  key: const ValueKey('host-capture'),
                  child: child!,
                ),
              ),
              home: Scaffold(
                appBar: AppBar(title: const Text('Health')),
                body: AdminHealthContent(
                  health: health,
                  hostResources: session,
                  profile: null,
                  accessChecks: () => null,
                  onReviewAccess: null,
                  onRefresh: session.refresh,
                  onOpenDestination: (_) async {},
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          if (scenario == 'loading') {
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(
              tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is IconButton &&
                          w.tooltip == 'Refresh host resources',
                    ),
                  )
                  .onPressed,
              isNull,
            );
          } else {
            expect(find.byType(CircularProgressIndicator), findsNothing);
          }
          await snapshot(tester, '${brightness.name}-$scale-$scenario');
          if (scenario == 'normal') {
            final position = tester
                .state<ScrollableState>(find.byType(Scrollable))
                .position;
            final hostY =
                tester.getTopLeft(find.text('Host')).dy + position.pixels;
            await tester.scrollUntilVisible(find.text('Server'), 200);
            await tester.pumpAndSettle();
            expect(
              hostY,
              lessThan(
                tester.getTopLeft(find.text('Server')).dy + position.pixels,
              ),
            );
            expect(hostY, isPositive);
            await tester.scrollUntilVisible(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Refresh host resources',
              ),
              -200,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Refresh host resources'));
            await tester.pumpAndSettle();
            expect(
              fixture.requests.every((r) => r.$1 == 'GET' && r.$3.isEmpty),
              isTrue,
            );
            await tester.tap(find.text('hermes-nas'));
            await tester.pumpAndSettle();
            expect(find.byType(AdminHostDetailsPage), findsOneWidget);
            expect(find.text('Host resources'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await snapshot(tester, '${brightness.name}-$scale-details');
          }
          await tester.pumpWidget(const SizedBox());
          if (fixture.statsGate case final gate?) {
            gate.complete();
            await tester.pump();
          }
          session.dispose();
          health.dispose();
          fixture.server.close();
        });
      }
    }
  }

  testWidgets(
    'background and hidden surfaces pause polling and resume safely',
    (tester) async {
      final fixture = HostResourcesFixture();
      final resources = HostResourcesSession(fixture.server);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminHostHealth(resources: resources)),
        ),
      );
      await tester.pumpAndSettle();
      final initial = fixture.requests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      expect(fixture.requests.length, initial);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fixture.requests.length, initial + 2);
      await tester.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: false,
            child: Scaffold(body: AdminHostHealth(resources: resources)),
          ),
        ),
      );
      await tester.pump();
      final hidden = fixture.requests.length;
      await tester.pump(const Duration(minutes: 1));
      expect(fixture.requests.length, hidden);
      await tester.pumpWidget(const SizedBox());
      resources.dispose();
      fixture.server.close();
    },
  );
}
