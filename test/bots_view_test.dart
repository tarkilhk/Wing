import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/transcript_message.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/widgets/bot_avatar.dart';
import 'package:wing/core/widgets/playful_portrait.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/screens/bots/bots_content.dart';
import 'package:wing/core/screens/bots/bot_profile_editor.dart';
import 'package:wing/core/screens/bots/bot_settings_screen.dart';
import 'package:wing/core/screens/bots/bots_create_screen.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/bots_fixture.dart';
import 'support/administration_fixture.dart';
import 'support/profile_browser_fixture.dart';
import 'helpers/pump_markdown_widget.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';

const _export = bool.fromEnvironment('STUDIO_REVIEW');

class _BotConversationBrowser extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    ...super.sessions(profile),
    {
      'id': 'canonical-root',
      'title': 'Bot Chat',
      'profile': profile,
      'last_active': now,
      'unread': false,
    },
    {
      'id': 'canonical-tip',
      'title': 'Compacted conversation',
      'profile': profile,
      'last_active': now,
      'unread': false,
    },
    {
      'id': 'ordinary',
      'title': 'Bot Chat',
      'profile': profile,
      'last_active': now,
      'unread': false,
    },
  ];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {'id': 1, 'role': 'user', 'content': 'Can you help me plan my week?'},
    {
      'id': 2,
      'role': 'assistant',
      'content': 'Of course. What would you like to make time for this week?',
    },
  ];
}

class _ReviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

Future<void> _capture(WidgetTester tester, GlobalKey frame, String name) async {
  if (!_export) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/bots-review')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  if (_export) _ReviewBinding();
  setUpAll(() async {
    if (!_export) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
      'monospace': 'build/studio-mono.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets(
    'settings reopens acknowledged avatar after save, removal and shape selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII=';
      final administration = AdministrationFixture('Home server');
      administration.configs['atlas'] = {};
      final fixture = BotsFixture(server: administration.server);
      fixture.commandHook = (_, method, _) async => method == 'image.generate'
          ? {'success': true, 'image_data': png}
          : null;
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      await session.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          home: BotSettingsScreen(
            profile: administration.server.profile('atlas'),
            bot: session.state.bots.first,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openEditor() async {
        await tester.tap(find.text('Edit name & appearance'));
        await tester.pumpAndSettle();
      }

      BotAvatar preview() => tester
          .widgetList<BotAvatar>(
            find.descendant(
              of: find.byType(BotProfileEditor),
              matching: find.byType(BotAvatar),
            ),
          )
          .singleWhere((avatar) => avatar.size == 88);
      Future<void> generate() async {
        await tester.scrollUntilVisible(
          find.byTooltip('Generate avatar'),
          240,
          scrollable: find
              .descendant(
                of: find.byType(BotProfileEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.byTooltip('Generate avatar'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await openEditor();
      await generate();
      await openEditor();
      expect(preview().image, orderedEquals(base64Decode(png)));
      await tester.scrollUntilVisible(
        find.byTooltip('Remove avatar'),
        240,
        scrollable: find
            .descendant(
              of: find.byType(BotProfileEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byTooltip('Remove avatar'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openEditor();
      expect(preview().image, isNull);
      await generate();
      await openEditor();
      await tester.ensureVisible(find.byTooltip('triangle'));
      await tester.tap(find.byTooltip('triangle'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(fixture.commands.last.$3['clear'], true);
      await openEditor();
      expect(preview().image, isNull);
      expect(preview().shape, 'triangle');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact roster, tabs, pinning and appearance in ${brightness.name} at $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final administration = AdministrationFixture('Home server');
          administration.configs['atlas'] = {};
          final fixture = BotsFixture(server: administration.server);
          final session = BotsSession((_) async => [fixture.repository]);
          await session.refresh();
          var view = const BotsViewState();
          final opened = <String>[];
          final frame = GlobalKey();
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          addTearDown(session.dispose);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: frame, child: child!),
              ),
              home: StatefulBuilder(
                builder: (context, setState) => BotsContent(
                  session: session,
                  viewState: view,
                  onViewChanged: (next) => setState(() => view = next),
                  onOpenMenu: () {},
                  onOpenChat: (key) async => opened.add(key.sessionId),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final atlas = find.byKey(const ValueKey('bot-instance-1/atlas'));
          final forge = find.byKey(const ValueKey('bot-instance-1/forge'));
          expect(
            tester.getTopLeft(atlas).dy,
            lessThan(tester.getTopLeft(forge).dy),
          );
          expect(find.text('All saved instances'), findsNothing);
          expect(find.byIcon(Icons.refresh), findsNothing);
          expect(find.byType(FloatingActionButton), findsOneWidget);
          expect(find.byTooltip('Create bot'), findsOneWidget);
          expect(
            tester.getBottomRight(find.byType(FloatingActionButton)).dy,
            closeTo(828, 1),
          );
          expect(find.byType(RefreshIndicator), findsNothing);
          expect(find.text('Pinned'), findsNothing);
          expect(find.byTooltip('Pinned'), findsOneWidget);
          final previews = tester
              .widgetList<Text>(find.byType(Text))
              .where((text) => text.data?.startsWith('I found three') == true);
          expect(previews.single.overflow, TextOverflow.ellipsis);
          await _capture(tester, frame, 'bots-${brightness.name}-$scale');
          await tester.drag(
            find.byType(ListView).first,
            const Offset(0, -1200),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .getBottomRight(
                  find.byKey(const ValueKey('bot-instance-1/mira')),
                )
                .dy,
            lessThan(tester.getTopLeft(find.byType(FloatingActionButton)).dy),
          );
          expect(
            find.byTooltip('Actions for Mira').hitTestable(),
            findsOneWidget,
          );
          await _capture(
            tester,
            frame,
            'bots-bottom-${brightness.name}-$scale',
          );
          await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Groups').first);
          await tester.pumpAndSettle();
          expect(find.text('Research team'), findsOneWidget);
          expect(find.byTooltip('Create group'), findsOneWidget);
          expect(find.text('Atlas'), findsNothing);
          await _capture(tester, frame, 'groups-${brightness.name}-$scale');
          await tester.tap(find.widgetWithText(Tab, 'Bots'));
          await tester.pumpAndSettle();
          final avatar = find.byTooltip('Edit name & appearance for Atlas');
          expect(tester.getSize(avatar).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(avatar).height, greaterThanOrEqualTo(48));
          await tester.tap(avatar);
          await tester.pumpAndSettle();
          expect(find.byType(BotProfileEditor), findsOneWidget);
          expect(opened, isEmpty);
          expect(fixture.commands, isEmpty);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Atlas').last);
          await tester.pumpAndSettle();
          expect(opened, ['atlas-chat']);
          await tester.tap(find.byTooltip('Actions for Atlas'));
          await tester.pumpAndSettle();
          await _capture(tester, frame, 'menu-${brightness.name}-$scale');
          expect(
            tester
                .widgetList<PopupMenuItem<String>>(
                  find.byType(PopupMenuItem<String>),
                )
                .map((item) => item.value)
                .whereType<String>()
                .toList(),
            ['screen', 'pin', 'hide', 'settings'],
          );
          await tester.tap(find.byKey(const ValueKey('bot-menu-settings')));
          await tester.pumpAndSettle();
          expect(find.text('Bot settings'), findsOneWidget);
          expect(find.text('Rename profile'), findsNothing);
          await _capture(tester, frame, 'settings-${brightness.name}-$scale');
          await tester.tap(find.text('Edit name & appearance'));
          await tester.pumpAndSettle();
          expect(find.byType(BotProfileEditor), findsOneWidget);
          expect(find.byTooltip('Save appearance'), findsNothing);
          await tester.tap(find.byTooltip('Reload saved appearance'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Saved appearance reloaded'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await _capture(tester, frame, 'editor-${brightness.name}-$scale');
          fixture.conflict = true;
          await tester.enterText(
            find.widgetWithText(TextField, 'Bot name'),
            'Atlas draft',
          );
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('This bot changed in another client'),
            findsOneWidget,
          );
          await _capture(
            tester,
            frame,
            'editor-conflict-${brightness.name}-$scale',
          );
          fixture.conflict = false;
          await tester.tap(find.byTooltip('Reload saved appearance'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('This bot changed in another client'),
            findsNothing,
          );
          expect(
            find.text('Review your edits before retrying.'),
            findsOneWidget,
          );
          await _capture(
            tester,
            frame,
            'editor-review-${brightness.name}-$scale',
          );
          await tester.tap(find.byTooltip('Retry saving appearance'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Retry saving appearance'), findsNothing);
          await tester.scrollUntilVisible(
            find.byTooltip('Generate avatar'),
            240,
            scrollable: find
                .descendant(
                  of: find.byType(BotProfileEditor),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await _capture(
            tester,
            frame,
            'editor-bottom-${brightness.name}-$scale',
          );
          expect(find.byTooltip('Upload avatar'), findsOneWidget);
          expect(find.byTooltip('Generate avatar'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.widgetWithText(TextField, 'Bot name'),
            -300,
            scrollable: find
                .descendant(
                  of: find.byType(BotProfileEditor),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Bot name'),
            'Atlas revised',
          );
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Discard edits?'), findsNothing);
          expect(find.byType(BotProfileEditor), findsNothing);
          expect(fixture.commands.last.$2, 'profiles.configure');
          // Reopening from settings uses the acknowledged appearance, not the
          // roster snapshot captured when this settings route was opened.
          await tester.tap(find.text('Edit name & appearance'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, 'Bot name'))
                .controller!
                .text,
            'Atlas revised',
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('Duplicate bot'), 240);
          await tester.ensureVisible(find.text('Duplicate bot'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Duplicate bot'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<BotsCreateScreen>(find.byType(BotsCreateScreen))
                .clone!
                .profile
                .name,
            'atlas',
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('Advanced'), 240);
          await tester.tap(find.text('Advanced'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('Rename profile'), 240);
          expect(
            find.text('Change the underlying profile name'),
            findsOneWidget,
          );
          await tester.tap(find.text('Rename profile'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Cancel').last);
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Bot settings'), findsOneWidget);
          await tester.scrollUntilVisible(find.byTooltip('Delete bot'), 240);
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton && widget.tooltip == 'Delete bot',
                  ),
                )
                .onPressed,
            isNotNull,
          );
          await _capture(
            tester,
            frame,
            'settings-bottom-${brightness.name}-$scale',
          );
          await tester.tap(find.byTooltip('Delete bot'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Cancel').last);
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Bot settings'), findsOneWidget);
          expect(
            administration.requests.where((request) => request.$1 != 'GET'),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
          session.setVisible(false);
          await tester.tap(find.byTooltip('Create bot'));
          await tester.pumpAndSettle();
          expect(find.byType(BotsCreateScreen), findsOneWidget);
          await _capture(tester, frame, 'create-${brightness.name}-$scale');
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(Tab, 'Groups'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Create group'));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            frame,
            'create-group-${brightness.name}-$scale',
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Research team'));
          await tester.pumpAndSettle();
          fixture.sendLost = true;
          await tester.enterText(
            find.byType(TextField),
            'Please review the plan',
          );
          await tester.tap(find.byTooltip('Send group message'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Retry same message'), findsOneWidget);
          expect(
            tester.widget<TextField>(find.byType(TextField)).readOnly,
            true,
          );
          expect(
            tester
                .widgetList<ActionChip>(find.byType(ActionChip))
                .every((chip) => chip.onPressed == null),
            true,
          );
          await _capture(
            tester,
            frame,
            'group-retry-${brightness.name}-$scale',
          );
          await tester.tap(find.byTooltip('Retry same message'));
          await tester.pumpAndSettle();
          expect(fixture.events, hasLength(1));
          await _capture(tester, frame, 'group-chat-${brightness.name}-$scale');
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(Tab, 'Bots'));
          await tester.pumpAndSettle();
          fixture.readHook = (_, method, _) async =>
              method == 'display.thumbnail'
              ? {'data_url': null, 'suppressed': 'human_has_control'}
              : null;
          await tester.tap(find.byTooltip('Actions for Atlas revised'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('bot-menu-screen')));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Preview is paused for privacy'),
            findsOneWidget,
          );
          await _capture(
            tester,
            frame,
            'screen-privacy-${brightness.name}-$scale',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('search filters and hidden bots never write profiles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fixture = BotsFixture();
    var rosterReads = 0;
    fixture.readHook = (_, method, _) async {
      if (method == 'profiles.list') rosterReads++;
      return null;
    };
    fixture.profiles.first['ui_meta']['hermes-bots']['hidden'] = true;
    final session = BotsSession((_) async => [fixture.repository]);
    addTearDown(session.dispose);
    await session.refresh();
    var view = const BotsViewState();
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        home: StatefulBuilder(
          builder: (context, setState) => BotsContent(
            session: session,
            viewState: view,
            onViewChanged: (next) => setState(() => view = next),
            onOpenMenu: () {},
            onOpenChat: (_) async {},
          ),
        ),
      ),
    );
    expect(find.text('Atlas'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('bots-search')), 'Mira');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bot-instance-1/mira')), findsOneWidget);
    expect(find.text('Forge'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Working'));
    await tester.pumpAndSettle();
    expect(find.text('Forge'), findsOneWidget);
    expect(find.text('Mira'), findsNothing);
    final beforeMenu = rosterReads;
    await tester.tap(find.byTooltip('Roster options'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh bots and groups'), findsNothing);
    await tester.tap(find.byType(CheckedPopupMenuItem<String>));
    await tester.pumpAndSettle();
    expect(view.showHidden, true);
    expect(rosterReads, beforeMenu);
    expect(find.text('Forge'), findsOneWidget);
    expect(view.filter, BotPresence.working);
    await tester.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(rosterReads, beforeMenu);
    expect(fixture.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  for (final action in ['default', 'rename', 'delete']) {
    testWidgets(
      'Bot settings protects or retires the captured profile: $action',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final administration = AdministrationFixture('Captured server');
        final name = action == 'default' ? 'default' : 'atlas';
        administration.configs[name] = {};
        final fixture = BotsFixture(server: administration.server);
        fixture.profiles
          ..clear()
          ..add(BotsFixture.profile(name, 'Atlas'));
        final session = BotsSession((_) async => [fixture.repository]);
        addTearDown(session.dispose);
        await session.refresh();
        var writes = 0;
        administration.mutationOverride =
            (method, path, query, body, canDispatch, onDispatched) async {
              expect(canDispatch(), true);
              onDispatched();
              writes++;
              expect(path, 'profiles/atlas');
              expect(method, action == 'rename' ? 'PATCH' : 'DELETE');
              administration.configs.remove('atlas');
              if (action == 'rename') administration.configs['renamed'] = {};
              return {'ok': true, 'path': '/profiles/atlas', 'name': 'renamed'};
            };
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: IconButton(
                  tooltip: 'Open settings',
                  icon: const Icon(Icons.tune),
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BotSettingsScreen(
                        profile: administration.server.profile(name),
                        bot: session.state.bots.single,
                        session: session,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Open settings'));
        await tester.pumpAndSettle();
        if (action == 'default') {
          await tester.scrollUntilVisible(find.byTooltip('Delete bot'), 240);
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton && widget.tooltip == 'Delete bot',
                  ),
                )
                .onPressed,
            isNull,
          );
          expect(
            find.text('The default profile cannot be deleted'),
            findsOneWidget,
          );
          expect(writes, 0);
        } else {
          if (action == 'rename') {
            await tester.scrollUntilVisible(find.text('Advanced'), 240);
            await tester.tap(find.text('Advanced'));
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(find.text('Rename profile'), 240);
            await tester.tap(find.text('Rename profile'));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextFormField), 'renamed');
            await tester.pumpAndSettle();
            await tester.tap(find.text('Continue'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Rename').last);
          } else {
            await tester.scrollUntilVisible(find.byTooltip('Delete bot'), 240);
            await tester.tap(find.byTooltip('Delete bot'));
            await tester.pumpAndSettle();
            expect(writes, 0);
            await tester.tap(find.text('Delete profile'));
          }
          await tester.pumpAndSettle();
          expect(writes, 1);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(BotSettingsScreen), findsNothing);
          expect(find.byTooltip('Open settings'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Bots drawer opens a canonical chat and Back retains the roster search',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      final browser = _BotConversationBrowser();
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: SavedConnection(
            id: 'host',
            label: 'Home server',
            host: 'localhost',
            port: 1,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'instance-1',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: browser.gateway,
      );
      await controller.initialize();
      final bots = BotsFixture();
      bots.profiles
        ..clear()
        ..add(
          BotsFixture.profile(
            'personal',
            'Atlas',
            pinned: true,
            preview: 'The continuing bot chat',
          ),
        );
      bots.profiles.single['canonical_session']['id'] = 'pin-one';
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: ProfileWorkspaceScreen(
            controller: controller,
            createBotsSession: () =>
                BotsSession((_) async => [bots.repository]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffold.openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-bots')));
      await tester.pumpAndSettle();
      expect(find.byType(BotsContent), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('bots-search')),
        'Atlas',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atlas').last);
      await tester.pumpAndSettle();
      expect(controller.current!.chat!.key.sessionId, 'pin-one');
      expect(controller.current!.chat!.key.workspace.profileName, 'personal');
      expect(find.byType(BotAvatar), findsOneWidget);
      final chatScaffold = tester.state<ScaffoldState>(
        find.byType(Scaffold).first,
      );
      chatScaffold.openDrawer();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppDrawer>(find.byType(AppDrawer)).selected,
        AppDestination.chats,
      );
      await tester.tap(find.byKey(const ValueKey('nav-bots')));
      await tester.pumpAndSettle();
      bots.profiles.single['ui_meta']['hermes-bots']['shape'] = 'triangle';
      await tester.tap(find.text('Atlas').last);
      await tester.pumpAndSettle();
      expect(find.byType(BotAvatar), findsOneWidget);
      expect(
        tester.widget<BotAvatar>(find.byType(BotAvatar)).shape,
        'triangle',
      );
      expect(find.text('Atlas'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BotsContent), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('bots-search')))
            .controller!
            .text,
        'Atlas',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      appPreferences.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'canonical bot avatar and name without repeated reply header in ${brightness.name} at $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final preferences = await SharedPreferences.getInstance();
          final appPreferences = AppPreferences(preferences);
          final browser = _BotConversationBrowser();
          final controller = ProfileWorkspaceController(
            access: ConnectionAccess(
              connection: SavedConnection(
                id: 'host',
                label: 'Home server',
                host: 'localhost',
                port: 1,
                apiKey: '',
              ),
              dashboardOAuth: null,
            ),
            connectionIdentity: 'instance-1',
            preferences: preferences,
            appPreferences: appPreferences,
            gatewayFactory: browser.gateway,
          );
          await controller.initialize();
          final scope = controller.current!.scope;
          await controller.openSession(
            ProfileSessionKey(scope, 'canonical-root'),
          );
          final botName = scale == 1
              ? 'Atlas'
              : 'Atlas with a very long bot display name';
          const avatarPng =
              'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAJUlEQVR4nGNwCj/ynxLMMGoApgH/byeBMbHiw9GAgY+FUQNIxwDOD2oPx3g6jQAAAABJRU5ErkJggg==';
          final bots = BotsFixture();
          bots.profiles
            ..clear()
            ..add(BotsFixture.profile('personal', botName));
          bots.profiles.single['canonical_session'] = {
            'id': 'canonical-root',
            'resolved_id': 'canonical-tip',
          };
          bots.profiles.single['has_avatar'] = scale == 2;
          var rosterReads = 0;
          Completer<Map<String, dynamic>?>? heldRoster;
          bots.readHook = (_, method, _) async {
            if (method == 'profiles.list') {
              rosterReads++;
              if (heldRoster != null) return heldRoster.future;
            }
            if (method == 'profiles.get_asset') {
              return {'found': true, 'data': avatarPng};
            }
            return null;
          };
          final frame = GlobalKey();
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: frame, child: child!),
              ),
              home: ProfileWorkspaceScreen(
                controller: controller,
                createBotsSession: () =>
                    BotsSession((_) async => [bots.repository]),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Bot Chat'), findsNothing);
          expect(find.text(botName), findsOneWidget);
          final avatar = find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(BotAvatar),
          );
          expect(avatar, findsOneWidget);
          final face = tester.widget<BotAvatar>(avatar);
          expect(face.name, botName);
          expect(face.shape, 'squircle');
          expect(face.color, '#65c7bc');
          expect(face.image, scale == 2 ? base64Decode(avatarPng) : isNull);
          if (scale == 2) {
            final uploaded = find.descendant(
              of: avatar,
              matching: find.byType(Image),
            );
            await tester.runAsync(
              () => precacheImage(
                tester.widget<Image>(uploaded).image,
                tester.element(avatar),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<RawImage>(
                    find.descendant(
                      of: avatar,
                      matching: find.byType(RawImage),
                    ),
                  )
                  .image,
              isNotNull,
            );
          }
          expect(tester.getSize(avatar), const Size(32, 32));
          expect(
            tester.getRect(avatar).right + 8,
            closeTo(tester.getRect(find.text(botName)).left, 0.1),
          );
          expect(
            tester.getCenter(avatar).dy,
            closeTo(tester.getCenter(find.text(botName)).dy, 0.1),
          );
          final reply = find.byWidgetPredicate(
            (widget) =>
                widget is ProfileMessage && widget.message.role == 'assistant',
          );
          expect(
            find.descendant(of: reply, matching: find.byType(BotAvatar)),
            findsNothing,
          );
          expect(
            find.descendant(of: reply, matching: find.text(botName)),
            findsNothing,
          );
          final copy = find.descendant(
            of: reply,
            matching: find.byTooltip('Copy message'),
          );
          expect(
            tester.getRect(copy).right,
            closeTo(tester.getRect(reply).right, 1),
          );
          expect(find.byType(PlayfulPortrait), findsNothing);
          expect(find.text('Hermes'), findsNothing);
          expect(find.byTooltip('Open navigation menu'), findsOneWidget);
          expect(find.byTooltip('Chat actions'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('chat-project-picker')),
            findsOneWidget,
          );
          await tester.settleMarkdown();
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Of course. What would you like to make time for this week?',
              findRichText: true,
            ),
            findsOneWidget,
          );
          await _capture(tester, frame, 'bot-chat-${brightness.name}-$scale');
          final reads = rosterReads;
          await controller.updateDraft(
            controller.current!.chat!,
            'Hello Atlas',
          );
          await tester.pumpAndSettle();
          expect(rosterReads, reads);
          await controller.openSession(
            ProfileSessionKey(scope, 'canonical-tip'),
          );
          await tester.pumpAndSettle();
          expect(avatar, findsOneWidget);
          expect(find.text('Compacted conversation'), findsNothing);
          // A delayed lookup for one chat must not decorate a different chat.
          heldRoster = Completer<Map<String, dynamic>?>();
          await controller.openSession(
            ProfileSessionKey(scope, 'canonical-root'),
          );
          await tester.pumpAndSettle();
          // The root and tip share the same confirmed bot identity.
          expect(find.text(botName), findsOneWidget);
          await controller.openSession(ProfileSessionKey(scope, 'ordinary'));
          await tester.pumpAndSettle();
          expect(find.byType(BotAvatar), findsNothing);
          expect(find.text('Hermes'), findsNothing);
          heldRoster.complete(null);
          heldRoster = null;
          await tester.pumpAndSettle();
          expect(find.byType(BotAvatar), findsNothing);
          expect(find.text('Bot Chat'), findsOneWidget);
          expect(find.text('Hermes'), findsNothing);
          expect(tester.takeException(), isNull);
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          appPreferences.dispose();
        },
      );
    }
  }

  testWidgets('saved and streaming replies omit repeated author headers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final scale in [1.0, 2.0]) {
      for (final streaming in [false, true]) {
        await tester.pumpMarkdownWidget(
          MaterialApp(
            theme: wingTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ProfileMessage(
                message: TranscriptMessage.fromRow({
                  'id': 1,
                  'role': 'assistant',
                  'content': 'I can help with that.',
                }),
                streaming: streaming,
                onReadAloud: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Hermes'), findsNothing);
        expect(find.byType(BotAvatar), findsNothing);
        expect(find.byType(PlayfulPortrait), findsNothing);
        expect(
          find.byTooltip('Copy message'),
          streaming ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
