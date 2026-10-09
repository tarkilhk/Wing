import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/bots/bot_profile_editor.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/screens/bots/bots_content.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';

import '../test/support/administration_fixture.dart';
import '../test/support/bots_fixture.dart';
import '../test/support/profile_browser_fixture.dart';

/// The host injects Android input and captures the actual window. No live I/O.
Future<void> _native(
  WidgetTester tester,
  String name, {
  String action = 'capture',
  String? text,
  bool? keyboard,
}) async {
  final cache = Directory.systemTemp.path;
  final token = '$name-${DateTime.now().microsecondsSinceEpoch}';
  await File('$cache/wing-bots-stage.json').writeAsString(
    jsonEncode({
      'name': name,
      'token': token,
      'action': action,
      'ime_insets_bottom': tester.view.viewInsets.bottom,
      'text': ?text,
      'keyboard': ?keyboard,
    }),
  );
  final ack = File('$cache/wing-bots-ack');
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await ack.exists() && await ack.readAsString() == token) {
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      return;
    }
  }
  throw StateError('Native Bots driver did not complete $name');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('BOTS_NATIVE_INPUT')) {
    throw StateError('Use scripts/test_native_bots.py on an owned emulator.');
  }
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final large in [false, true]) {
      final label = '${brightness.name}-${large ? 'large' : 'normal'}';
      testWidgets('Android Bots $label', (tester) async {
        await _native(tester, '$label-configure', action: 'configure');
        final metricsDeadline = DateTime.now().add(const Duration(seconds: 10));
        while (((tester.view.physicalSize.width /
                            tester.view.devicePixelRatio) -
                        (large ? 320 : 390))
                    .abs() >
                1 &&
            DateTime.now().isBefore(metricsDeadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final preferences = AppPreferences(prefs);
        final browser = ProfileBrowserFixture();
        final controller = ProfileWorkspaceController(
          access: ConnectionAccess(
            connection: SavedConnection(
              id: 'host',
              label: 'Home server',
              host: 'unused',
              port: 1,
              apiKey: '',
            ),
            dashboardOAuth: null,
          ),
          connectionIdentity: 'instance-1',
          preferences: prefs,
          appPreferences: preferences,
          gatewayFactory: browser.gateway,
        );
        final fixture = BotsFixture(
          server: AdministrationFixture('Home server').server,
        );
        fixture.profiles.first['name'] = 'personal';
        fixture.profiles.first['display_name'] = 'personal';
        fixture.profiles.first['canonical_session']['id'] = 'pin-one';
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            home: ProfileWorkspaceScreen(
              controller: controller,
              createBotsSession: () =>
                  BotsSession((_) async => [fixture.repository]),
            ),
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          controller.dispose();
          preferences.dispose();
        });
        Future<void> frames() async {
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await frames();
        final media = MediaQuery.of(
          tester.element(find.byType(ProfileWorkspaceScreen)),
        );
        expect(
          media.size.width,
          inInclusiveRange(large ? 319 : 389, large ? 321 : 391),
        );
        if (large) {
          expect(media.textScaler.scale(16), greaterThan(24));
        } else {
          expect(media.textScaler.scale(16), inInclusiveRange(15, 17));
        }
        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await tester.pumpAndSettle();
        final botsNav = find.byKey(const ValueKey('nav-bots'));
        await tester.ensureVisible(botsNav);
        await tester.tap(botsNav.hitTestable());
        await tester.pumpAndSettle();
        await _native(tester, '$label-roster');

        final search = find.byKey(const ValueKey('bots-search'));
        await tester.tap(search);
        await _native(
          tester,
          '$label-search',
          action: 'type',
          text: 'Atlas',
          keyboard: true,
        );
        await frames();
        expect(tester.widget<TextField>(search).controller!.text, 'Atlas');
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        await _native(tester, '$label-search-hide', action: 'hide-keyboard');
        await frames();
        expect(tester.view.viewInsets.bottom, 0);
        await tester.tap(find.text('Atlas').last);
        await tester.pumpAndSettle();
        expect(controller.current!.chat!.key.sessionId, 'pin-one');
        await _native(tester, '$label-chat-back', action: 'back');
        await tester.pumpAndSettle();
        expect(find.byType(BotsContent), findsOneWidget);
        expect(tester.widget<TextField>(search).controller!.text, 'Atlas');

        Future<void> edit(String title) async {
          await tester.tap(find.byTooltip('Actions for $title'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('bot-menu-edit')));
          await tester.pumpAndSettle();
        }

        await edit('Atlas');
        final name = find.widgetWithText(TextField, 'Bot name');
        await tester.tap(name);
        await _native(
          tester,
          '$label-name',
          action: 'append',
          text: ' Native',
          keyboard: true,
        );
        await frames();
        expect(tester.widget<TextField>(name).controller!.text, 'Atlas Native');
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        await _native(tester, '$label-name-hide', action: 'hide-keyboard');
        await frames();
        expect(tester.view.viewInsets.bottom, 0);
        await tester.tap(find.byTooltip('Save appearance'));
        await tester.pumpAndSettle();
        expect(find.byType(BotProfileEditor), findsNothing);
        expect(
          fixture.profiles.first['ui_meta']['hermes-bots']['title'],
          'Atlas Native',
        );
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        await edit('Atlas Native');
        await tester.scrollUntilVisible(
          find.byTooltip('Upload avatar'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(BotProfileEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await _native(tester, '$label-editor-bottom');
        await tester.tap(find.byTooltip('Upload avatar'));
        await frames();
        await _native(tester, '$label-picker-cancel', action: 'picker-cancel');
        await tester.pumpAndSettle();
        expect(find.byType(BotProfileEditor), findsOneWidget);
        expect(
          fixture.commands.where((call) => call.$2 == 'profiles.set_asset'),
          isEmpty,
        );
        await tester.ensureVisible(find.text('Profile settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Profile settings'));
        await tester.pumpAndSettle();
        expect(find.text('Role & instructions'), findsOneWidget);
        await _native(tester, '$label-settings');
        await _native(tester, '$label-settings-back', action: 'back');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Color 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Color 1'));
        await _native(tester, '$label-editor-back', action: 'back');
        await tester.pumpAndSettle();
        expect(find.text('Discard edits?'), findsOneWidget);
        await _native(tester, '$label-discard');
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.byType(BotProfileEditor), findsOneWidget);
        await _native(tester, '$label-discard-back', action: 'back');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.byType(BotsContent), findsOneWidget);

        await tester.tap(find.byTooltip('Create bot'));
        await tester.pumpAndSettle();
        await _native(
          tester,
          '$label-new-name',
          action: 'type',
          text: 'native-bot',
          keyboard: true,
        );
        await frames();
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Profile name'))
              .controller!
              .text,
          'native-bot',
        );
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        await _native(tester, '$label-new-hide', action: 'hide-keyboard');
        await frames();
        expect(tester.view.viewInsets.bottom, 0);
        await _native(tester, '$label-create');
        await tester.tap(find.byTooltip('Create bot'));
        await tester.pumpAndSettle();
        expect(
          fixture.commands.where((c) => c.$2 == 'profiles.create'),
          hasLength(1),
        );

        await tester.tap(find.widgetWithText(Tab, 'Groups'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Research team'));
        await tester.pumpAndSettle();
        final groupComposer = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Message the group',
        );
        await tester.tap(groupComposer);
        await _native(
          tester,
          '$label-message',
          action: 'type',
          text: 'Review the plan',
          keyboard: true,
        );
        await frames();
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        fixture.sendLost = true;
        await tester.tap(find.byTooltip('Send group message'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Retry same message'), findsOneWidget);
        expect(tester.widget<TextField>(groupComposer).readOnly, true);
        await _native(tester, '$label-group-hide', action: 'hide-keyboard');
        await frames();
        expect(tester.view.viewInsets.bottom, 0);
        await _native(tester, '$label-retry');
        await tester.tap(find.byTooltip('Retry same message'));
        await tester.pumpAndSettle();
        expect(fixture.events, hasLength(1));
        await _native(tester, '$label-group-back', action: 'back');
        await tester.pumpAndSettle();
        // Successful retry makes the focused composer editable again. Android
        // Back first dismisses its restored IME, then leaves the room.
        if (find.byType(BotGroupScreen).evaluate().isNotEmpty) {
          expect(tester.view.viewInsets.bottom, 0);
          await _native(tester, '$label-group-route-back', action: 'back');
        }
        expect(find.byType(BotsContent), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Groups'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _native(tester, '$label-complete');
      });
    }
  }
}
