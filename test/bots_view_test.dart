import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/bots/bots_content.dart';
import 'package:wing/core/screens/bots/bot_profile_editor.dart';
import 'package:wing/core/screens/bots/bots_create_screen.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/bots_fixture.dart';
import 'support/administration_fixture.dart';
import 'support/profile_browser_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';

const _export = bool.fromEnvironment('STUDIO_REVIEW');

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
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact roster, tabs, pinning and appearance in ${brightness.name} at $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final administration = AdministrationFixture('Home server');
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
          expect(find.text('Pinned'), findsNothing);
          expect(find.byTooltip('Pinned'), findsOneWidget);
          final previews = tester
              .widgetList<Text>(find.byType(Text))
              .where((text) => text.data?.startsWith('I found three') == true);
          expect(previews.single.overflow, TextOverflow.ellipsis);
          await _capture(tester, frame, 'bots-${brightness.name}-$scale');
          await tester.tap(find.text('Groups').first);
          await tester.pumpAndSettle();
          expect(find.text('Research team'), findsOneWidget);
          expect(find.text('Atlas'), findsNothing);
          await _capture(tester, frame, 'groups-${brightness.name}-$scale');
          await tester.tap(find.widgetWithText(Tab, 'Bots'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Actions for Atlas'));
          await tester.pumpAndSettle();
          await _capture(tester, frame, 'menu-${brightness.name}-$scale');
          await tester.tap(find.byKey(const ValueKey('bot-menu-edit')));
          await tester.pumpAndSettle();
          expect(find.byType(BotProfileEditor), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capture(tester, frame, 'editor-${brightness.name}-$scale');
          await tester.scrollUntilVisible(
            find.text('Profile settings'),
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
          await tester.tap(find.text('Profile settings'));
          await tester.pumpAndSettle();
          expect(find.text('Role & instructions'), findsOneWidget);
          await _capture(tester, frame, 'settings-${brightness.name}-$scale');
          await tester.pageBack();
          await tester.pumpAndSettle();
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
          expect(find.text('Discard edits?'), findsOneWidget);
          await _capture(tester, frame, 'discard-${brightness.name}-$scale');
          await tester.tap(find.text('Keep editing'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Save appearance'));
          await tester.pumpAndSettle();
          expect(find.byType(BotProfileEditor), findsNothing);
          expect(fixture.commands.last.$2, 'profiles.configure');
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
    expect(fixture.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Bots drawer opens a canonical chat and Back retains the roster search',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      final browser = ProfileBrowserFixture();
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
}
