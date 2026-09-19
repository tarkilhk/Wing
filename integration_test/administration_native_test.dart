import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wing/core/screens/administration/admin_identity_page.dart';
import 'package:wing/core/screens/administration/admin_runtime_health.dart';
import 'package:wing/core/services/administration_health.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/screens/administration/admin_settings_page.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/screens/profile_capabilities_screen.dart';
import 'package:wing/core/theme/wing_theme.dart';
import '../test/support/administration_design_fixture.dart';
import 'package:wing/core/widgets/compact_switch.dart';

/// Production widgets on disposable Android with in-memory observations only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android runtime findings survive reviewing the same operation', (
    tester,
  ) async {
    final fixture = AdministrationDesignFixture();
    final health = AdministrationHealth(fixture.server);
    addTearDown(health.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AdminRuntimeHealth(health: health),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Run Doctor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Doctor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    await tester.tap(find.text('Diagnostic output'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A required dependency'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    await tester.ensureVisible(find.text('Review output'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review output'));
    await tester.pumpAndSettle();
    expect(fixture.requests.where((r) => r.$1 == 'POST'), hasLength(1));
    expect(
      fixture.requests.where((r) => r.$2 == 'actions/doctor/status'),
      hasLength(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Android editors: keyboard, conflict, accessibility action and discard',
    (tester) async {
      final fixture = AdministrationDesignFixture();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => adminPush(
                      context,
                      (context) => AdminSettingsPage(
                        profile: fixture.server.profile('personal'),
                        title: 'Memory settings',
                        fields: [memoryFields[2]],
                      ),
                    ),
                    child: const Text('Edit memory'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final entry = tester.getSemantics(find.text('Edit memory'));
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          entry.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextFormField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '2800');
        await tester.pumpAndSettle();
        expect(find.text('Save').hitTestable(), findsOneWidget);
        (fixture.configs['personal']!['memory'] as Map)['memory_char_limit'] =
            3200;
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        // Hide the native IME before navigating the comparison below the input.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Keep my value'));
        await tester.pumpAndSettle();
        expect(find.text('Current server value: 3200'), findsOneWidget);
        await tester.tap(find.text('Keep my value'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          (fixture.configs['personal']!['memory'] as Map)['memory_char_limit'],
          2800,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit memory'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextFormField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '2900');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('1 unsaved change'), findsOneWidget);
        expect(find.text('Close').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.text('Discard edits?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.text('Edit memory'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('Android full-screen Identity retains long draft on back', (
    tester,
  ) async {
    final fixture = AdministrationDesignFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showAdminIdentityEditor(
                context,
                gateway: fixture.identityGateway(),
                connectionLabel: 'Home server',
              ),
              child: const Text('Edit identity'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit identity'));
    await tester.pumpAndSettle();
    final soul = find.byKey(const ValueKey('profile-soul-field'));
    await tester.ensureVisible(soul);
    await tester.enterText(
      soul,
      List.filled(20, 'Be thoughtful, clear and precise.').join('\n'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save').hitTestable(), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(soul).controller!.text,
      contains('precise.\nBe thoughtful'),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fixture.soul.split('\n'), hasLength(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Android provider ownership and separate capability actions at large text',
    (tester) async {
      final fixture = AdministrationDesignFixture();
      final profile = fixture.server.profile('personal');
      var setup = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: AdminProviderDetail(
            profile: profile,
            shared: false,
            providerId: 'research',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Manage shared account'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage shared account'));
      await tester.pumpAndSettle();
      expect(find.text('Home server / Shared accounts'), findsOneWidget);
      expect(
        fixture.requests
            .where((r) => r.$2 == 'providers/oauth')
            .last
            .$3['profile'],
        'default',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ProfileCapabilitiesScreen(
            gateway: profile.gateway,
            connectionLabel: 'Home server',
            onToolSetup: (_) async {
              setup = true;
            },
            onLibrary: () async {},
            onHub: () async {},
            onPlugins: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capabilities'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Web search and research'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Web search and research'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      final toggle = find.byType(CompactSwitch);
      expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      await tester.tapAt(tester.getTopLeft(toggle) + const Offset(3, 3));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('Setup and providers'), findsOneWidget);
      await tester.ensureVisible(find.text('Setup and providers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Setup and providers'));
      await tester.pumpAndSettle();
      expect(setup, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_NATIVE_ADMINISTRATION')) {
        debugPrint('NATIVE_ADMINISTRATION_CAPTURE_READY');
        await Future<void>.delayed(const Duration(seconds: 10));
      }
    },
  );
}
