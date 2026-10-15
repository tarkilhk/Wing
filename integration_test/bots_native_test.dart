import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/bots/bot_profile_editor.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/screens/bots/bots_content.dart';
import 'package:wing/core/screens/bots/bots_create_screen.dart';
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

/// The host injects Android input and captures the actual window. Backend
/// responses come from owned fixtures, including the drawer's loopback HTTP.
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
      // The roster intentionally contains running work. Its Wing pulse must
      // remain active; native acknowledgment does not require global quiescence.
      await tester.pump();
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
        // DrawerVersions owns its own production HTTP adapter, independently of
        // the injected chat/Bots repositories. Keep those reads on this owned
        // loopback endpoint, with unexpected transport requests failing the test.
        final unexpectedReads = <String>[];
        final versionReads = <String>{};
        final dashboard = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        dashboard.listen((request) async {
          final path = request.uri.path;
          final query = request.uri.queryParameters;
          final scopedRead =
              query['profile'] == 'default' &&
              (path == '/api/hermes/update/check'
                  ? query.length == 2 && query['force'] == 'true'
                  : query.length == 1);
          if (request.method != 'GET' ||
              (path == '/' ? query.isNotEmpty : !scopedRead)) {
            unexpectedReads.add('${request.method} ${request.uri}');
            request.response.statusCode = HttpStatus.badRequest;
          } else if (path == '/' && query.isEmpty) {
            request.response.write(
              'window.__HERMES_SESSION_TOKEN__="native-bots-fixture";',
            );
          } else if (request.headers.value('X-Hermes-Session-Token') !=
              'native-bots-fixture') {
            unexpectedReads.add('Unauthenticated ${request.uri}');
            request.response.statusCode = HttpStatus.unauthorized;
          } else {
            final body = switch (path) {
              '/api/health' => {'ok': true, 'version': '1.2.3'},
              '/api/profiles' => {
                'profiles': [
                  {'name': 'default', 'is_default': true},
                ],
              },
              '/api/hermes/update/check' => {
                'current_version': '1.2.3',
                'update_available': false,
                'can_apply': false,
              },
              _ => null,
            };
            if (body == null) {
              unexpectedReads.add('${request.method} ${request.uri}');
              request.response.statusCode = HttpStatus.notFound;
            } else {
              versionReads.add(path);
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode(body));
            }
          }
          await request.response.close();
        });
        addTearDown(() async {
          await dashboard.close(force: true);
          expect(unexpectedReads, isEmpty);
        });
        final controller = ProfileWorkspaceController(
          access: ConnectionAccess(
            connection: SavedConnection(
              id: 'host',
              label: 'Home server',
              host: InternetAddress.loopbackIPv4.address,
              port: 1,
              dashboardPortOverride: dashboard.port,
              apiKey: '',
            ),
            dashboardOAuth: null,
          ),
          connectionIdentity: 'instance-1',
          preferences: prefs,
          appPreferences: preferences,
          gatewayFactory: browser.gateway,
        );
        final administration = AdministrationFixture('Home server');
        final fixture = BotsFixture(server: administration.server);
        fixture.profiles.first['name'] = 'personal';
        fixture.profiles.first['display_name'] = 'personal';
        fixture.profiles.first['canonical_session']['id'] = 'pin-one';
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          controller.dispose();
          preferences.dispose();
          administration.server.close();
        });
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
        Future<void> until(bool Function() ready, String outcome) async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          do {
            await tester.pump(const Duration(milliseconds: 50));
            expect(tester.takeException(), isNull, reason: outcome);
            if (ready()) return;
          } while (DateTime.now().isBefore(deadline));
          fail('Timed out waiting for $outcome');
        }

        bool visible(Finder finder) =>
            finder.hitTestable().evaluate().isNotEmpty;
        final search = find.byKey(const ValueKey('bots-search'));
        // Native search keeps the query in an EditableText. Match the roster
        // label itself so opening a result cannot target the search editor.
        Finder rosterTitle(String title) => find.descendant(
          of: find.byType(BotsContent),
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == title,
          ),
        );
        final atlas = rosterTitle('Atlas');
        Future<void> roster() => until(
          () =>
              visible(search) && find.byType(BotsContent).evaluate().isNotEmpty,
          'the usable Bots roster',
        );
        Future<void> keyboardClosed() => until(
          () => tester.view.viewInsets.bottom == 0,
          'the Android keyboard to close',
        );

        await until(
          () => visible(find.byTooltip('Open navigation menu')),
          'the workspace navigation control',
        );
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
        await tester.tap(find.byTooltip('Open navigation menu'));
        final botsNav = find.byKey(const ValueKey('nav-bots'));
        await until(() => visible(botsNav), 'the Bots navigation entry');
        await until(
          () =>
              find.text('v1.2.3').evaluate().isNotEmpty &&
              versionReads.containsAll({
                '/api/health',
                '/api/profiles',
                '/api/hermes/update/check',
              }),
          'the drawer version from the owned dashboard',
        );
        await tester.ensureVisible(botsNav);
        await tester.tap(botsNav.hitTestable());
        await roster();
        await until(() => visible(atlas), 'the loaded Atlas bot');
        await _native(tester, '$label-roster');

        await tester.tap(search);
        await _native(
          tester,
          '$label-search',
          action: 'type',
          text: 'Atlas',
          keyboard: true,
        );
        await until(
          () =>
              tester.widget<TextField>(search).controller!.text == 'Atlas' &&
              tester.view.viewInsets.bottom > 0,
          'native search input with the Android keyboard open',
        );
        expect(tester.widget<TextField>(search).controller!.text, 'Atlas');
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        await _native(tester, '$label-search-hide', action: 'hide-keyboard');
        await keyboardClosed();
        expect(tester.view.viewInsets.bottom, 0);
        await until(() => visible(atlas), 'the filtered Atlas bot result');
        await tester.tap(atlas.hitTestable());
        await until(
          () => visible(find.byKey(const ValueKey('profile-message-composer'))),
          'the canonical bot conversation',
        );
        expect(controller.current!.chat!.key.sessionId, 'pin-one');
        await _native(tester, '$label-chat-back', action: 'back');
        await roster();
        expect(find.byType(BotsContent), findsOneWidget);
        expect(tester.widget<TextField>(search).controller!.text, 'Atlas');

        Future<void> edit(String title) async {
          await tester.tap(find.byTooltip('Edit name & appearance for $title'));
          await until(
            () => visible(find.widgetWithText(TextField, 'Bot name')),
            'the bot appearance editor',
          );
        }

        await edit('Atlas');
        expect(find.byType(BotProfileEditor), findsOneWidget);
        await _native(tester, '$label-avatar-editor');
        final name = find.widgetWithText(TextField, 'Bot name');
        await tester.tap(name);
        await _native(
          tester,
          '$label-name',
          action: 'append',
          text: ' Native',
          keyboard: true,
        );
        await until(
          () =>
              tester.widget<TextField>(name).controller!.text ==
                  'Atlas Native' &&
              tester.view.viewInsets.bottom > 0,
          'native name input with the Android keyboard open',
        );
        expect(tester.widget<TextField>(name).controller!.text, 'Atlas Native');
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        await _native(tester, '$label-name-hide', action: 'hide-keyboard');
        await keyboardClosed();
        expect(tester.view.viewInsets.bottom, 0);
        expect(find.byTooltip('Save appearance'), findsNothing);
        await _native(tester, '$label-name-autosave-back', action: 'back');
        await roster();
        expect(find.byType(BotProfileEditor), findsNothing);
        expect(
          fixture.profiles.first['ui_meta']['hermes-bots']['title'],
          'Atlas Native',
        );
        await tester.tap(find.byTooltip('Clear search'));
        await until(
          () =>
              tester.widget<TextField>(search).controller!.text.isEmpty &&
              visible(
                find.byTooltip('Edit name & appearance for Atlas Native'),
              ),
          'the renamed bot after clearing the search',
        );
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
        // The picker suspends Flutter rendering. Let Android cancel it before
        // pumping the restored editor, rather than waiting for background frames.
        await _native(tester, '$label-picker-cancel', action: 'picker-cancel');
        await until(
          () => visible(find.byTooltip('Upload avatar')),
          'the restored editor after cancelling the Android picker',
        );
        expect(find.byType(BotProfileEditor), findsOneWidget);
        expect(
          fixture.commands.where((call) => call.$2 == 'profiles.set_asset'),
          isEmpty,
        );
        await tester.ensureVisible(find.byTooltip('Color 1'));
        await until(
          () => visible(find.byTooltip('Color 1')),
          'the color control',
        );
        await tester.tap(find.byTooltip('Color 1'));
        await _native(tester, '$label-color-autosave-back', action: 'back');
        await roster();
        expect(find.text('Discard edits?'), findsNothing);
        expect(
          fixture.profiles.first['ui_meta']['hermes-bots']['color'],
          isNot('#65c7bc'),
        );
        expect(find.byType(BotsContent), findsOneWidget);
        await tester.tap(find.byTooltip('Actions for Atlas Native'));
        await until(
          () => visible(find.byKey(const ValueKey('bot-menu-settings'))),
          'the bot action menu',
        );
        expect(find.byKey(const ValueKey('bot-menu-edit')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('bot-menu-settings')));
        await until(
          () => visible(find.text('Role & instructions')),
          'bot settings',
        );
        expect(find.text('Role & instructions'), findsOneWidget);
        await _native(tester, '$label-settings');
        await _native(tester, '$label-settings-back', action: 'back');
        await roster();

        await tester.tap(
          find
              .descendant(
                of: find.byType(BotsContent),
                matching: find.byTooltip('Create bot'),
              )
              .hitTestable(),
        );
        await until(
          () => visible(find.widgetWithText(TextField, 'Profile name')),
          'the new bot form',
        );
        await _native(
          tester,
          '$label-new-name',
          action: 'type',
          text: 'native-bot',
          keyboard: true,
        );
        await until(
          () =>
              tester
                      .widget<TextField>(
                        find.widgetWithText(TextField, 'Profile name'),
                      )
                      .controller!
                      .text ==
                  'native-bot' &&
              tester.view.viewInsets.bottom > 0,
          'native new-bot input with the Android keyboard open',
        );
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Profile name'))
              .controller!
              .text,
          'native-bot',
        );
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        await _native(tester, '$label-new-hide', action: 'hide-keyboard');
        await keyboardClosed();
        expect(tester.view.viewInsets.bottom, 0);
        await _native(tester, '$label-create');
        await tester.tap(
          find
              .descendant(
                of: find.byType(BotsCreateScreen),
                matching: find.byTooltip('Create bot'),
              )
              .hitTestable(),
        );
        await roster();
        expect(
          fixture.commands.where((c) => c.$2 == 'profiles.create'),
          hasLength(1),
        );

        await tester.tap(find.widgetWithText(Tab, 'Groups'));
        await until(
          () => visible(rosterTitle('Research team')),
          'the group roster',
        );
        await tester.tap(rosterTitle('Research team').hitTestable());
        final groupComposer = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Message the group',
        );
        await until(() => visible(groupComposer), 'the group conversation');
        await tester.tap(groupComposer);
        await _native(
          tester,
          '$label-message',
          action: 'type',
          text: 'Review the plan',
          keyboard: true,
        );
        await until(
          () =>
              tester.widget<TextField>(groupComposer).controller!.text ==
                  'Review the plan' &&
              tester.view.viewInsets.bottom > 0,
          'native group message input with the Android keyboard open',
        );
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        fixture.sendLost = true;
        await tester.tap(find.byTooltip('Send group message'));
        await until(
          () =>
              visible(find.byTooltip('Retry same message')) &&
              tester.widget<TextField>(groupComposer).readOnly,
          'the retry control for the uncertain group message',
        );
        expect(find.byTooltip('Retry same message'), findsOneWidget);
        expect(tester.widget<TextField>(groupComposer).readOnly, true);
        await _native(tester, '$label-group-hide', action: 'hide-keyboard');
        await keyboardClosed();
        expect(tester.view.viewInsets.bottom, 0);
        await _native(tester, '$label-retry');
        await tester.tap(find.byTooltip('Retry same message'));
        await until(
          () =>
              fixture.events.length == 1 &&
              !tester.widget<TextField>(groupComposer).readOnly &&
              tester
                  .widget<TextField>(groupComposer)
                  .controller!
                  .text
                  .isEmpty &&
              find.byTooltip('Retry same message').evaluate().isEmpty,
          'one accepted group message and an editable empty composer',
        );
        expect(fixture.events, hasLength(1));
        await _native(tester, '$label-group-back', action: 'back');
        await until(
          () =>
              find.byType(BotGroupScreen).evaluate().isEmpty ||
              tester.view.viewInsets.bottom == 0,
          'Android Back to dismiss the keyboard or leave the group',
        );
        // Successful retry makes the focused composer editable again. Android
        // Back first dismisses its restored IME, then leaves the room.
        if (find.byType(BotGroupScreen).evaluate().isNotEmpty) {
          expect(tester.view.viewInsets.bottom, 0);
          await _native(tester, '$label-group-route-back', action: 'back');
        }
        await roster();
        expect(find.byType(BotsContent), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Groups'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _native(tester, '$label-complete');
      });
    }
  }
}
