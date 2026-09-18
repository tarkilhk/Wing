import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/administration/admin_defaults_page.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/screens/administration/admin_runtime_health.dart';
import 'package:wing/core/screens/administration/admin_identity_page.dart';
import 'package:wing/core/screens/administration/admin_memory_page.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/screens/administration/admin_settings_page.dart';
import 'package:wing/core/screens/profile_capabilities_screen.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/widgets/voice_preferences_card.dart';
import 'support/administration_design_fixture.dart';
import 'support/voice_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_ADMINISTRATION');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((b) => b.buffer.asByteData()),
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
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/administration-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final mode in ['light', 'dark', 'narrow', 'wide']) {
    for (final family in [
      'models',
      'identity',
      'memory',
      'memory-detail',
      'providers',
      'provider-detail',
      'service-keys',
      'capabilities',
      'compression',
      'usage',
      'runtime-health',
      'voice',
    ]) {
      testWidgets('$family layout $mode', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final fixture = AdministrationDesignFixture();
        final profile = fixture.server.profile('personal');
        final health = AdministrationHealth(fixture.server);
        final narrow = mode == 'narrow';
        tester.view.physicalSize = Size(
          narrow
              ? 320
              : mode == 'wide'
              ? 840
              : 390,
          844,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final page = switch (family) {
          'runtime-health' => Scaffold(
            appBar: AppBar(title: const Text('Runtime health')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AdminRuntimeHealth(health: health),
            ),
          ),
          'models' => AdminDefaultsPage(profile: profile),
          'identity' => AdminIdentityPage(
            gateway: fixture.identityGateway(),
            connectionLabel: 'Home server',
          ),
          'memory' => AdminMemoryPage(profile: profile),
          'memory-detail' => AdminMemoryDetail(
            profile: profile,
            id: 'memory:MEMORY.md:0',
          ),
          'providers' => AdminProvidersPage(profile: profile, shared: false),
          'provider-detail' => AdminProviderDetail(
            profile: profile,
            shared: false,
            providerId: 'research',
          ),
          'service-keys' => AdminServiceKeyCatalog(
            profile: profile,
            shared: false,
          ),
          'capabilities' => ProfileCapabilitiesScreen(
            gateway: profile.gateway,
            connectionLabel: 'Home server',
            onToolSetup: (_) async {},
            onLibrary: () async {},
            onHub: () async {},
            onPlugins: () async {},
          ),
          'compression' => AdminSettingsPage(
            profile: profile,
            title: 'Compression',
            fields: compressionFields,
          ),
          'usage' => AdminUsagePage(profile: profile),
          _ => Scaffold(
            appBar: AppBar(title: const Text('Voice')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: VoicePreferencesCard(
                preferences: preferences,
                device: VoiceDeviceFixture(),
              ),
            ),
          ),
        };
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: profileWorkspaceTheme(
              wingTheme(
                mode == 'light' || mode == 'wide'
                    ? Brightness.light
                    : Brightness.dark,
              ),
              accent: mode == 'wide'
                  ? WorkspaceAccent.gold
                  : WorkspaceAccent.mint,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(narrow ? 2 : 1),
                disableAnimations: narrow,
              ),
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: child!,
              ),
            ),
            home: page,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await snapshot(tester, '$mode-$family');
        if (family == 'runtime-health') {
          await tester.ensureVisible(find.text('Doctor'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Doctor'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Run'),
            ),
          );
          await tester.pumpAndSettle();
          await snapshot(tester, '$mode-runtime-result');
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Doctor'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Failed'), findsOneWidget);
          await snapshot(tester, '$mode-runtime-findings');
        }
        if (family == 'identity') {
          fixture.partialIdentity = true;
          await tester.enterText(
            find.byKey(const ValueKey('profile-description-field')),
            'Research companion',
          );
          await tester.enterText(
            find.byKey(const ValueKey('profile-soul-field')),
            'A long draft kept after a partially applied save.\n' * 12,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(find.text('1 unsaved change'), findsOneWidget);
          await snapshot(tester, '$mode-identity-partial');
        }
        if (family == 'compression') {
          await tester.enterText(
            find.byKey(const ValueKey('setting:compression.threshold')),
            '82',
          );
          await tester.pumpAndSettle();
          fixture.ignoreSave = true;
          final gate = Completer<void>();
          fixture.writeGate = gate;
          await tester.tap(find.text('Save'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
                .onPressed,
            isNull,
          );
          await snapshot(tester, '$mode-compression-pending');
          gate.complete();
          await tester.pumpAndSettle();
          expect(find.textContaining('Save not confirmed'), findsOneWidget);
          await snapshot(tester, '$mode-compression-unconfirmed');
        }
        // Exercise the full scrollable extent, including controls outside the capture.
        final scrolls = find.byType(Scrollable);
        if (scrolls.evaluate().isNotEmpty) {
          for (var step = 0; step < 8; step++) {
            await tester.drag(scrolls.first, const Offset(0, -500));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await snapshot(tester, '$mode-$family-bottom');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        health.dispose();
        await tester.pumpAndSettle();
      });
    }
  }
}
