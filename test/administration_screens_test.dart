import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_settings_page.dart';
import 'package:wing/core/screens/administration/admin_memory_page.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/screens/administration/admin_widgets.dart';
import 'package:wing/core/screens/administration/admin_tool_setup_page.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'support/administration_fixture.dart';

const _fields = [
  AdminField(
    'memory.memory_char_limit',
    'Memory budget',
    AdminFieldKind.integer,
    minimum: 1,
  ),
];
void main() {
  testWidgets('managed provider selection explains required sign-in', (
    tester,
  ) async {
    final fixture = AdministrationFixture();
    fixture.override = (method, path, query, body) async {
      if (path == 'profiles') {
        return {
          'profiles': [
            {'name': 'personal'},
          ],
        };
      }
      if (method == 'PUT' && path == 'tools/toolsets/stt/provider') {
        return {
          'ok': true,
          'provider': 'Nous Subscription',
          'needs_nous_auth': true,
        };
      }
      return {
        'active_provider': null,
        'providers': [
          {
            'name': 'Nous Subscription',
            'status': 'needs_auth',
            'requires_nous_auth': true,
          },
        ],
      };
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: AdminToolSetupPage(
          profile: fixture.server.profile('personal'),
          name: 'stt',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use provider'));
    await tester.pumpAndSettle();
    expect(
      find.text('Selection saved. This provider still needs account access.'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be confirmed'), findsNothing);
  });
  testWidgets(
    'late operation refresh after leaving a page does not load or set state',
    (tester) async {
      late VoidCallback refresh;
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminLoad(
              load: () async {
                reads++;
                return <String, dynamic>{};
              },
              builder: (_, _, reload) {
                refresh = reload;
                return const Text('Loaded');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      refresh();
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'save confirmation stays above editor actions with the keyboard open',
    (tester) async {
      final fixture = AdministrationFixture();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: AdminSettingsPage(
            profile: fixture.server.profile('personal'),
            title: 'Memory settings',
            fields: _fields,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2500');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final footer = tester.getRect(find.widgetWithText(TextButton, 'Close'));
      expect(footer.bottom, lessThanOrEqualTo(564));
      expect(
        tester.getRect(find.byType(SnackBar)).bottom,
        lessThanOrEqualTo(footer.top),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'an externally changed field preserves the draft without overwriting it',
    (tester) async {
      final f = AdministrationFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSettingsPage(
            profile: f.server.profile('personal'),
            title: 'Memory settings',
            fields: _fields,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2500');
      (f.configs['personal']!['memory'] as Map)['memory_char_limit'] = 4000;
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      expect(find.text('2500'), findsOneWidget);
      expect(f.requests.where((r) => r.$1 == 'PUT'), isEmpty);
    },
  );

  testWidgets(
    'partial settings readback keeps both edits and never reports success',
    (tester) async {
      final f = AdministrationFixture();
      f.override = (method, path, query, body) async {
        // Use the real fixture contract except that this server ignores one field.
        final handler = f.override;
        f.override = null;
        try {
          final result = await f.send(method, path, query, body);
          if (method == 'PUT') {
            (f.configs['personal']!['memory'] as Map)['memory_enabled'] = true;
          }
          return result;
        } finally {
          f.override = handler;
        }
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSettingsPage(
            profile: f.server.profile('personal'),
            title: 'Memory settings',
            fields: [memoryFields.first, _fields.first],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.enterText(find.byType(TextFormField), '2500');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Save not confirmed'), findsOneWidget);
      expect(find.textContaining('Defaults saved'), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      expect(find.text('2500'), findsOneWidget);
    },
  );
  testWidgets(
    'settings editor keeps original owner after a parent selection change',
    (tester) async {
      final f = AdministrationFixture();
      Future<void> show(String name) => tester.pumpWidget(
        MaterialApp(
          home: AdminSettingsPage(
            profile: f.server.profile(name),
            title: 'Memory settings',
            fields: _fields,
          ),
        ),
      );
      await show('personal');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2500');
      await tester.pump();
      await show('work');
      await tester.pumpAndSettle();
      expect(find.text('Server A / personal'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final write = f.requests.firstWhere((r) => r.$1 == 'PUT');
      expect(write.$3['profile'], 'personal');
      expect(f.configs['work']!['memory'], {
        'memory_enabled': false,
        'memory_char_limit': 3000,
      });
      expect(
        find.textContaining('Defaults saved for personal'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'unconfirmed settings save preserves draft and makes no success claim',
    (tester) async {
      final f = AdministrationFixture()..ignoreSave = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSettingsPage(
            profile: f.server.profile('personal'),
            title: 'Memory settings',
            fields: _fields,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2500');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('2500'), findsOneWidget);
      expect(find.textContaining('Save not confirmed'), findsOneWidget);
      expect(find.textContaining('Defaults saved'), findsNothing);
    },
  );

  testWidgets(
    'pending save prevents duplicate submission and keeps target visible',
    (tester) async {
      final f = AdministrationFixture()..writeGate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSettingsPage(
            profile: f.server.profile('personal'),
            title: 'Memory settings',
            fields: _fields,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2500');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Server A / personal'), findsOneWidget);
      f.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(f.requests.where((r) => r.$1 == 'PUT').length, 1);
    },
  );

  testWidgets('memory failure is not rendered as an empty list', (
    tester,
  ) async {
    final f = AdministrationFixture()..failReads = true;
    await tester.pumpWidget(
      MaterialApp(home: AdminMemoryPage(profile: f.server.profile('personal'))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load'), findsOneWidget);
    expect(find.text('No retained memories in this profile.'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'malformed memory response becomes unavailable instead of a widget exception',
    (tester) async {
      final f = AdministrationFixture();
      f.override = (_, _, _, _) async => {'memory': 'broken'};
      await tester.pumpWidget(
        MaterialApp(
          home: AdminMemoryPage(profile: f.server.profile('personal')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The server returned an invalid response.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('secret editor does not load existing secrets or expose input', (
    tester,
  ) async {
    final f = AdministrationFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminSecretPage(
          profile: f.server.profile('personal'),
          name: 'EXAMPLE_API_KEY',

          isSet: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(f.requests, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'settings fit 360dp, large text and open keyboard in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final f = AdministrationFixture();
        await tester.pumpWidget(
          MaterialApp(
            theme: profileWorkspaceTheme(wingTheme(brightness)),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: AdminSettingsPage(
              profile: f.server.profile('personal'),
              title: 'Memory settings',
              fields: _fields,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
        expect(save.bottom, lessThanOrEqualTo(520));
        expect(save.left, greaterThanOrEqualTo(0));
      },
    );
  }
}
