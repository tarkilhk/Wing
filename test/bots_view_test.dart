import 'package:wing/core/models/voice_processing_settings.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/widgets/server_connection_label.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/profile_colors.dart';
import 'package:wing/core/services/attachment_image_worker.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
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
import 'package:wing/core/services/bot_group_draft_session.dart';
import 'package:wing/core/services/bot_avatar_io.dart';
import 'package:wing/core/widgets/bot_group_picture.dart';
import 'package:wing/core/widgets/bot_group_identity.dart';
import 'package:wing/core/services/bot_screen_window.dart';
import 'package:wing/core/services/bot_profile_edit_session.dart';
import 'package:wing/core/theme/profile_colors.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/bots_fixture.dart';
import 'support/composer_fixture.dart' show emitChatEvent;
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

class _RoomPicturePicker extends BotAvatarIo {
  @override
  Future<Uint8List?> pick() => File('assets/icon/icon.png').readAsBytes();
}

class _ReviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey frame,
  String name, {
  bool motion = false,
}) async {
  if (!_export) return;
  if (motion) {
    await tester.pump(const Duration(milliseconds: 100));
  } else {
    await tester.pumpAndSettle();
  }
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

Future<void> _revealGroup(
  WidgetTester tester,
  Finder target, {
  double delta = 120,
}) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  if (_export) _ReviewBinding();
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'group avatar collage fits every member ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = scale == 1
              ? const Size(390, 844)
              : const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          fixture.profiles.addAll([
            for (var index = 0; index < 4; index++)
              BotsFixture.profile('bot$index', 'Bot $index'),
          ]);
          for (final (index, profile) in fixture.profiles.indexed) {
            profile['ui_meta']['hermes-bots']['shape'] = botShapes[index];
          }
          final bots = await fixture.repository.bots();
          final saved = (await fixture.repository.groups(
            groupMessages: null,
          )).single;
          final frame = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: frame,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: BotGroupIdentity(
                          group: saved.withIcon(
                            color: ProfileColorChoice.cyan,
                            revision: 1,
                          ),
                          bots: bots,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var count = 2; count <= 6; count++) ...[
                        Text('$count bots'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final size in [32.0, 40.0, 48.0, 64.0]) ...[
                              BotGroupPicture(
                                key: ValueKey('collage-$count-$size'),
                                avatars: bots.take(count).toList(),
                                color: ProfileColorChoice.cyan,
                                size: size,
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (var count = 2; count <= 6; count++) {
            for (final size in [32.0, 40.0, 48.0, 64.0]) {
              final icon = find.byKey(ValueKey('collage-$count-$size'));
              await tester.ensureVisible(icon);
              await tester.pumpAndSettle();
              final avatars = find.descendant(
                of: icon,
                matching: find.byType(BotAvatar),
              );
              expect(avatars, findsNWidgets(count));
              final bounds = tester.getRect(icon);
              final faces = avatars.evaluate().toList();
              final rectangles = [
                for (final face in faces)
                  tester.getRect(find.byWidget(face.widget)),
              ];
              for (final rect in rectangles) {
                expect(
                  rectangles.where(
                    (other) => other != rect && rect.overlaps(other),
                  ),
                  isNotEmpty,
                );
              }
              final centers = rectangles.map((rect) => rect.center).toList();
              if (count == 3) {
                final byY = [...centers]..sort((a, b) => a.dy.compareTo(b.dy));
                expect(byY[0].dy, lessThan(byY[1].dy));
                expect(byY[1].dy, closeTo(byY[2].dy, .01));
                expect(byY[0].dx, closeTo((byY[1].dx + byY[2].dx) / 2, .01));
              } else if (count == 4) {
                final xs = centers.map((point) => point.dx.round()).toSet();
                final ys = centers.map((point) => point.dy.round()).toSet();
                expect(xs.length, 2);
                expect(ys.length, 2);
              } else if (count >= 5) {
                final center =
                    centers.reduce((a, b) => a + b) / count.toDouble();
                final distances = centers
                    .map((point) => (point - center).distance)
                    .toList();
                for (final distance in distances) {
                  expect(distance, closeTo(distances.first, .01));
                }
              }
              for (final avatar in faces) {
                final rect = tester.getRect(find.byWidget(avatar.widget));
                expect(bounds.contains(rect.topLeft), true);
                expect(bounds.contains(rect.bottomRight), true);
              }
            }
          }
          final identity = find.byType(BotGroupIdentity);
          await _capture(
            tester,
            frame,
            'group-collage-bottom-${brightness.name}-$scale',
          );
          await _revealGroup(tester, identity, delta: -200);
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: identity, matching: find.byType(BotAvatar)),
            findsNWidgets(2),
          );
          expect(
            find.descendant(of: identity, matching: find.byType(Text)),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            frame,
            'group-collage-${brightness.name}-$scale',
          );
        },
      );
    }
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BotScreenWindow.channel, (_) async => null);
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
        'roster refresh stays clear of tabs in ${brightness.name} at $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final fixture = BotsFixture();
          final session = BotsSession((_) async => [fixture.repository]);
          addTearDown(session.dispose);
          await session.refresh();
          final held = Completer<Map<String, dynamic>?>();
          fixture.readHook = (_, method, _) async =>
              method == 'profiles.list' ? held.future : null;
          final refresh = session.refresh();
          var view = const BotsViewState();
          final frame = GlobalKey();
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
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
                child: RepaintBoundary(key: frame, child: child!),
              ),
              home: StatefulBuilder(
                builder: (context, setState) => BotsContent(
                  instanceHeader: const Align(
                    alignment: Alignment.centerLeft,
                    child: ServerConnectionLabel(label: 'Home server'),
                  ),
                  session: session,
                  viewState: view,
                  onViewChanged: (next) => setState(() => view = next),
                  onOpenMenu: () {},
                  onOpenChat: (_) async {},
                  onOpenGroup: (_) async {},
                ),
              ),
            ),
          );
          for (final tab in ['Bots', 'Groups']) {
            await tester.tap(find.widgetWithText(Tab, tab));
            await tester.pump(const Duration(milliseconds: 300));
            final progress = find.byType(LinearProgressIndicator);
            expect(progress, findsOneWidget);
            expect(
              tester.getTopLeft(progress).dy -
                  tester.getBottomLeft(find.byType(TabBar)).dy,
              greaterThanOrEqualTo(8),
            );
            expect(
              tester.getTopLeft(find.byKey(const ValueKey('bots-search'))).dy -
                  tester.getBottomLeft(progress).dy,
              greaterThanOrEqualTo(16),
            );
            expect(
              tester.widget<LinearProgressIndicator>(progress).semanticsLabel,
              'Loading bots and groups',
            );
            expect(
              find.text(tab == 'Bots' ? 'Atlas' : 'Research team'),
              findsOneWidget,
            );
            await _capture(
              tester,
              frame,
              'loading-${tab.toLowerCase()}-${brightness.name}-$scale',
              motion: true,
            );
            expect(tester.takeException(), isNull);
          }
          held.complete(null);
          await refresh;
          await tester.pumpAndSettle();
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.text('Research team'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'group editing saved details, palette and keyboard ${brightness.name} $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = scale == 1
              ? const Size(390, 844)
              : const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          final Map<String, dynamic> profile = jsonDecode(
            jsonEncode(BotsFixture.profile('default', 'Hermes')),
          );
          final photo = encodeRoomThumbnail((
            File('assets/icon/icon.png').readAsBytesSync(),
            45000,
          ));
          profile['ui_meta']['wing-group-icon:room-1'] = {
            'version': 1,
            'color': ProfileColorChoice.cyan.slot,
            'data': base64Encode(photo),
          };
          profile['ui_meta_revisions']['wing-group-icon:room-1'] = 3;
          fixture.profiles.add(profile);
          fixture.commandHook = (_, method, params) async {
            if (method != 'profiles.configure') return null;
            final meta = params['ui_meta'] as Map;
            final revisions = <String, int>{};
            (profile['ui_meta'] as Map).addAll(meta);
            for (final key in meta.keys) {
              revisions[key as String] = profile['ui_meta_revisions'][key] =
                  (profile['ui_meta_revisions'][key] as int? ?? 0) + 1;
            }
            return {
              'applied': {'ui_meta': true, 'ui_meta_revisions': revisions},
            };
          };
          final session = BotsSession((_) async => [fixture.repository]);
          addTearDown(session.dispose);
          await session.refresh();
          final group = session.state.groups.single;
          final draft = BotGroupDraftSession(
            session,
            existing: group,
            pictureIo: _RoomPicturePicker(),
          );
          final frame = GlobalKey();
          var keyboard = false;
          late StateSetter setMedia;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => StatefulBuilder(
                builder: (context, setState) {
                  setMedia = setState;
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      viewInsets: EdgeInsets.only(bottom: keyboard ? 240 : 0),
                    ),
                    child: RepaintBoundary(key: frame, child: child),
                  );
                },
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BotsCreateScreen(
                          session: session,
                          group: true,
                          editGroup: group,
                          createGroupDraft: () => draft,
                        ),
                      ),
                    ),
                    child: const Text('Open editor'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open editor'));
          await tester.pumpAndSettle();
          final name = find.byKey(const ValueKey('group-name'));
          final save = find.byKey(const ValueKey('group-save'));
          expect(
            tester.widget<TextField>(name).controller!.text,
            'Research team',
          );
          expect(tester.widget<IconButton>(save).onPressed, isNull);
          expect(find.text('Search bots'), findsNothing);
          final memberNote = find.text(
            'Members are fixed when the group is created.',
          );
          await _revealGroup(tester, memberNote);
          expect(memberNote, findsOneWidget);
          await _revealGroup(tester, name, delta: -120);
          await tester.runAsync(
            () => precacheImage(
              MemoryImage(photo),
              tester.element(find.byType(BotGroupPicture).first),
            ),
          );
          await tester.pumpAndSettle();
          await _capture(
            tester,
            frame,
            'group-editing-saved-${brightness.name}-$scale',
          );
          await _revealGroup(
            tester,
            find.byTooltip('Choose icon color'),
            delta: -120,
          );
          await tester.tap(find.byTooltip('Choose icon color'));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            frame,
            'group-editing-palette-${brightness.name}-$scale',
          );
          await tester.tap(find.byKey(const ValueKey('group-color-rose')));
          await tester.pumpAndSettle();
          expect(draft.iconColor, ProfileColorChoice.rose);
          await tester.tap(find.byTooltip('Remove room picture'));
          await tester.pumpAndSettle();
          expect(draft.picture, isNull);
          await tester.runAsync(() async {
            await tester.tap(find.byTooltip('Upload room picture'));
            while (draft.pictureBusy) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();
          expect(draft.picture, isNotNull);
          await tester.tap(find.byTooltip('Remove room picture'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Generate room picture'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField))
                .initialValue,
            contains('Atlas, Mira'),
          );
          await _capture(
            tester,
            frame,
            'group-editing-prompt-${brightness.name}-$scale',
          );
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(fixture.commands, isEmpty);
          await _revealGroup(tester, name, delta: -120);
          await tester.enterText(
            name,
            scale == 1 ? 'Field team' : 'Research and evidence review team',
          );
          setMedia(() => keyboard = true);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(save).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height - 240),
          );
          await _capture(
            tester,
            frame,
            'group-editing-keyboard-${brightness.name}-$scale',
          );
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(find.text('Edit group'), findsNothing);
          expect(session.state.groups.single.name, draft.name);
          expect(
            session.state.groups.single.iconColor,
            ProfileColorChoice.rose,
          );
          expect(session.state.groups.single.picture, isNull);
          expect(fixture.commands.map((c) => c.$2), [
            'profiles.configure',
            'groups.rename',
          ]);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'group editing is reachable from roster and discussion and updates the open room',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = BotsFixture();
      final Map<String, dynamic> profile = jsonDecode(
        jsonEncode(BotsFixture.profile('default', 'Hermes')),
      );
      fixture.profiles.add(profile);
      fixture.commandHook = (_, method, params) async {
        if (method != 'profiles.configure') return null;
        (profile['ui_meta'] as Map).addAll(params['ui_meta'] as Map);
        final key = (params['ui_meta'] as Map).keys.single;
        profile['ui_meta_revisions'][key] = 1;
        return {
          'applied': {
            'ui_meta': true,
            'ui_meta_revisions': {key: 1},
          },
        };
      };
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      await session.refresh();
      var state = const BotsViewState(tab: 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          home: StatefulBuilder(
            builder: (context, setState) => BotsContent(
              session: session,
              viewState: state,
              onViewChanged: (next) => setState(() => state = next),
              onOpenMenu: () {},
              onOpenChat: (_) async {},
              onOpenGroup: (group) => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => BotGroupScreen(
                    stopVoicePlayback: () async {},
                    voiceInputSettings: () =>
                        const LocalVoiceInputSettings(language: ''),
                    createSession: () => session.openGroup(group),
                    onEdit: (group) => openGroupEditor(context, session, group),
                  ),
                ),
              ),
              instanceHeader: const Align(
                alignment: Alignment.centerLeft,
                child: ServerConnectionLabel(label: 'Home server'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit group Research team'));
      await tester.pumpAndSettle();
      expect(find.byType(BotsCreateScreen), findsOneWidget);
      expect(find.byType(BotGroupScreen), findsNothing);
      expect(fixture.commands, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions for Research team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit group'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-save')), findsOneWidget);
      expect(fixture.commands, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Research team').first);
      await tester.pumpAndSettle();
      expect(find.byType(BotGroupScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Group options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('group-name')),
        'Updated discussion',
      );
      await tester.pump();
      expect(session.state.groups.single.iconRevision, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('group-name')))
            .enabled,
        true,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('group-save')))
            .onPressed,
        isNotNull,
      );
      expect(session.state.busy, false);
      await tester.tap(find.byTooltip('Save changes'));
      await tester.pumpAndSettle();
      expect(session.state.errors, isEmpty);
      expect(
        fixture.room['name'],
        'Updated discussion',
        reason: fixture.commands.map((c) => c.$2).join(', '),
      );
      expect(find.byType(BotsCreateScreen), findsNothing);
      expect(find.byType(BotGroupScreen), findsOneWidget);
      expect(find.text('Updated discussion'), findsOneWidget);
      expect(find.text('Research team'), findsNothing);
      expect(fixture.commands.where((c) => c.$2 == 'groups.create'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('group creation layout ${brightness.name} $scale', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final semantics = tester.ensureSemantics();
        final size = scale == 1 ? const Size(390, 844) : const Size(320, 640);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = BotsFixture();
        fixture.profiles.addAll([
          BotsFixture.profile('pace', 'Pace'),
          BotsFixture.profile('butler', 'Butler'),
          BotsFixture.profile('reminder', 'Reminder inbox'),
        ]);
        for (var index = 0; index < fixture.profiles.length; index++) {
          fixture.profiles[index]['ui_meta']['hermes-bots']['shape'] =
              botShapes[index];
        }
        if (scale == 2) {
          fixture.profiles.last['ui_meta']['hermes-bots']['title'] =
              'Reminder inbox with a long name';
        }
        final session = BotsSession((_) async => [fixture.repository]);
        addTearDown(session.dispose);
        await session.refresh();
        final frame = GlobalKey();
        var keyboard = false;
        late StateSetter setMedia;
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => StatefulBuilder(
              builder: (context, setState) {
                setMedia = setState;
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: EdgeInsets.only(bottom: keyboard ? 240 : 0),
                  ),
                  child: RepaintBoundary(key: frame, child: child),
                );
              },
            ),
            home: BotsCreateScreen(session: session, group: true),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.byKey(const ValueKey('group-create'));
        IconButton create() => tester.widget<IconButton>(action);
        expect(create().onPressed, isNull);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('group-name')))
              .autofocus,
          false,
        );
        await _capture(
          tester,
          frame,
          'group-creation-empty-${brightness.name}-$scale',
        );
        await _revealGroup(tester, find.text('0 of 6 selected'));
        expect(find.text('0 of 6 selected'), findsOneWidget);
        await _revealGroup(
          tester,
          find.byKey(const ValueKey('group-name')),
          delta: -120,
        );
        await tester.enterText(
          find.byKey(const ValueKey('group-name')),
          'Launch team',
        );
        for (final profile in ['atlas', 'mira']) {
          final row = find.byKey(ValueKey('group-member-instance-1/$profile'));
          await _revealGroup(tester, row);
          await tester.pumpAndSettle();
          await tester.tapAt(
            tester
                .getRect(row)
                .intersect(tester.getRect(find.byType(ListView)))
                .center,
          );
          await tester.pumpAndSettle();
          expect(row, findsNothing);
          final picked = find.byKey(
            ValueKey('group-picked-instance-1/$profile'),
          );
          await _revealGroup(tester, picked, delta: -120);
          expect(picked, findsOneWidget);
          expect(
            tester.getSemantics(picked).flagsCollection.isSelected,
            ui.Tristate.isTrue,
          );
          final remove = find.byTooltip(
            'Remove ${profile == 'atlas' ? 'Atlas' : 'Mira'}',
          );
          expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
          final search = find.byKey(
            const ValueKey('group-member-search-instance-1'),
          );
          expect(
            tester.getRect(picked).bottom,
            lessThanOrEqualTo(tester.getRect(search).top),
          );
        }
        expect(create().onPressed, isNotNull);
        final icon = tester.widget<BotGroupPicture>(
          find.byType(BotGroupPicture).last,
        );
        expect(icon.avatars.map((bot) => bot?.profile.name), ['atlas', 'mira']);
        expect(icon.color?.slot, isNotNull);
        expect(
          find.descendant(
            of: find.byType(BotGroupPicture).last,
            matching: find.byType(BotAvatar),
          ),
          findsNWidgets(2),
        );
        await _revealGroup(tester, find.text('Members'), delta: -120);
        expect(find.text('2 of 6 selected'), findsOneWidget);
        expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        await _revealGroup(
          tester,
          find.byKey(const ValueKey('group-member-instance-1/reminder')),
        );
        await _capture(
          tester,
          frame,
          'group-creation-members-${brightness.name}-$scale',
        );
        await tester.drag(find.byType(ListView), const Offset(0, 1400));
        await tester.pumpAndSettle();
        await _capture(
          tester,
          frame,
          'group-creation-selected-${brightness.name}-$scale',
        );
        setMedia(() => keyboard = true);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(action).bottom,
          lessThanOrEqualTo(size.height - 240),
        );
        await _capture(
          tester,
          frame,
          'group-creation-keyboard-${brightness.name}-$scale',
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('group creation picture options ${brightness.name} $scale', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = scale == 1
            ? const Size(390, 844)
            : const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = BotsFixture();
        final session = BotsSession((_) async => [fixture.repository]);
        addTearDown(session.dispose);
        await session.refresh();
        final draft = BotGroupDraftSession(
          session,
          pictureIo: _RoomPicturePicker(),
        );
        for (final bot in draft.bots.take(2)) {
          draft.select(bot, true);
        }
        final frame = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: frame, child: child),
            ),
            home: BotsCreateScreen(
              session: session,
              group: true,
              createGroupDraft: () => draft,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('group-create')))
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('group-name')))
              .controller!
              .text,
          isEmpty,
        );
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Upload room picture'));
          while (draft.pictureBusy) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(draft.picture, isNotNull);
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(draft.picture!),
            tester.element(find.byType(BotGroupPicture).first),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<BotGroupPicture>(find.byType(BotGroupPicture))
              .every((picture) => picture.image != null),
          true,
        );
        expect(find.byTooltip('Remove room picture'), findsOneWidget);
        await _capture(
          tester,
          frame,
          'group-creation-picture-${brightness.name}-$scale',
        );
        await tester.tap(find.byTooltip('Generate room picture'));
        await tester.pumpAndSettle();
        expect(find.text('Room picture'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Room picture')).style!.fontSize,
          WingTypography.ramp(brightness).section.fontSize,
        );
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byType(TextFormField),
                  matching: find.byType(TextField),
                ),
              )
              .style!
              .fontSize,
          16,
        );
        for (final tooltip in ['Close', 'Generate picture']) {
          final target = tester.getRect(find.byTooltip(tooltip));
          expect(target.width, greaterThanOrEqualTo(48));
          expect(target.height, greaterThanOrEqualTo(48));
        }
        final panel = tester.getRect(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        );
        final promptField = tester.getRect(find.byType(TextFormField));
        expect(promptField.left - panel.left, WingSpacing.lg);
        expect(panel.right - promptField.right, WingSpacing.lg);
        expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
          contains('Atlas, Mira'),
        );
        await _capture(
          tester,
          frame,
          'group-creation-prompt-${brightness.name}-$scale',
        );
        const editedPrompt = 'Two friendly robots beside a teal wing, no text.';
        await tester.enterText(find.byType(TextFormField), editedPrompt);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Generate room picture'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
          editedPrompt,
          reason: 'Closing the prompt must retain the text for the next edit.',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byTooltip('Generate picture')).bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height - 240),
        );
        await _capture(
          tester,
          frame,
          'group-prompt-keyboard-${brightness.name}-$scale',
        );
        await tester.enterText(find.byType(TextFormField), '   ');
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Generate picture',
                ),
              )
              .onPressed,
          isNull,
        );
        await _capture(
          tester,
          frame,
          'group-prompt-empty-${brightness.name}-$scale',
        );
        await tester.enterText(find.byType(TextFormField), editedPrompt);
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Generate picture',
                ),
              )
              .onPressed,
          isNotNull,
        );
        for (final tooltip in ['Close', 'Generate picture']) {
          final target = tester.getRect(find.byTooltip(tooltip));
          expect(target.top, greaterThanOrEqualTo(0));
          expect(
            target.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height - 240),
          );
          expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
        }
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        fixture.commandHook = (_, method, _) async {
          if (method == 'image.generate') {
            throw StateError('Provider unavailable');
          }
          return null;
        };
        await tester.tap(find.byTooltip('Generate room picture'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Generate picture'));
        await tester.pumpAndSettle();
        expect(draft.error, contains('could not be prepared'));
        expect(draft.picture, isNotNull);
        expect(fixture.commands.single.$3['prompt'], editedPrompt);
        await _capture(
          tester,
          frame,
          'group-prompt-error-${brightness.name}-$scale',
        );
        await _revealGroup(
          tester,
          find.byTooltip('Generate room picture'),
        );
        await tester.tap(find.byTooltip('Generate room picture'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
          editedPrompt,
        );
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await _revealGroup(tester, find.byTooltip('Remove Atlas'));
        await tester.tap(find.byTooltip('Remove Atlas'));
        await tester.pumpAndSettle();
        expect(draft.selected.single.title, 'Mira');
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('group-create')))
              .onPressed,
          isNull,
        );
        await _revealGroup(
          tester,
          find.byTooltip('Remove room picture'),
          delta: -120,
        );
        await tester.tap(find.byTooltip('Remove room picture'));
        await tester.pumpAndSettle();
        expect(draft.picture, isNull);
        expect(fixture.commands.single.$2, 'image.generate');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
    'group creation search retains selection and enforces six members',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fixture = BotsFixture();
      fixture.profiles.addAll([
        for (final name in ['pace', 'butler', 'reminder', 'memory'])
          BotsFixture.profile(
            name,
            name == 'reminder' ? 'Reminder inbox with a long name' : name,
          ),
      ]);
      final session = BotsSession((_) async => [fixture.repository]);
      addTearDown(session.dispose);
      await session.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: BotsCreateScreen(session: session, group: true),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(
        const ValueKey('group-member-search-instance-1'),
      );
      for (final profile in [
        'atlas',
        'mira',
        'forge',
        'pace',
        'butler',
        'reminder',
      ]) {
        final row = find.byKey(ValueKey('group-member-instance-1/$profile'));
        await _revealGroup(tester, row);
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester
              .getRect(row)
              .intersect(tester.getRect(find.byType(ListView)))
              .center,
        );
        await tester.pumpAndSettle();
      }
      await _revealGroup(tester, find.text('Members'), delta: -120);
      expect(find.text('6 of 6 selected'), findsOneWidget);
      final extra = find.byKey(
        const ValueKey('group-member-instance-1/memory'),
      );
      await _revealGroup(tester, extra);
      expect(tester.widget<ListTile>(extra).onTap, isNull);
      await _revealGroup(tester, search, delta: -120);
      await tester.enterText(search, '@bot_atlas');
      await tester.pumpAndSettle();
      final atlas = find.byKey(const ValueKey('group-member-instance-1/atlas'));
      expect(atlas, findsNothing);
      final pickedAtlas = find.byKey(
        const ValueKey('group-picked-instance-1/atlas'),
      );
      expect(pickedAtlas, findsOneWidget);
      await _revealGroup(tester, find.byTooltip('Remove Atlas'), delta: -120);
      await tester.tap(find.byTooltip('Remove Atlas'));
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(atlas).selected, false);
      expect(tester.widget<ListTile>(atlas).onTap, isNotNull);
      expect(find.text('5 of 6 selected'), findsOneWidget);
      await tester.enterText(search, 'no matching bot');
      await tester.pumpAndSettle();
      expect(find.text('No bots match your search.'), findsOneWidget);
      expect(find.text('5 of 6 selected'), findsOneWidget);
      await tester.enterText(search, 'memory');
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(extra).onTap, isNotNull);
      await tester.tap(extra);
      await tester.pumpAndSettle();
      expect(find.text('6 of 6 selected'), findsOneWidget);
      expect(fixture.commands, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'group creation holds inputs and retries the same room ${brightness.name} $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = scale == 1
              ? const Size(390, 844)
              : const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          final held = Completer<Map<String, dynamic>>();
          final iconMeta = <String, dynamic>{};
          final iconRevisions = <String, int>{};
          fixture.readHook = (_, method, params) async =>
              method == 'profiles.list' && params['include_sessions'] == false
              ? {
                  'profiles': [
                    {
                      'name': 'default',
                      'ui_meta': iconMeta,
                      'ui_meta_revisions': iconRevisions,
                    },
                  ],
                }
              : null;
          Future<Map<String, dynamic>?> saveIcon(
            String _,
            String method,
            Map<String, dynamic> params,
          ) async {
            if (method != 'profiles.configure') return null;
            final incoming = params['ui_meta'] as Map;
            final expected = params['ui_meta_expected_revisions'] as Map;
            final written = <String, int>{};
            for (final key in incoming.keys.cast<String>()) {
              expect(expected[key], iconRevisions[key] ?? 0);
              iconMeta[key] = incoming[key];
              written[key] = iconRevisions[key] = (iconRevisions[key] ?? 0) + 1;
            }
            return {
              'applied': {'ui_meta': true, 'ui_meta_revisions': written},
            };
          }

          fixture.commandHook = (profile, method, params) async =>
              method == 'groups.create'
              ? held.future
              : saveIcon(profile, method, params);
          final session = BotsSession((_) async => [fixture.repository]);
          addTearDown(session.dispose);
          await session.refresh();
          final frame = GlobalKey();
          bool? result;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: frame, child: child),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Open group'),
                    onPressed: () async =>
                        result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) =>
                                BotsCreateScreen(session: session, group: true),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open group'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('group-name')),
            'Launch team',
          );
          for (final profile in ['atlas', 'mira']) {
            final row = find.byKey(
              ValueKey('group-member-instance-1/$profile'),
            );
            await _revealGroup(tester, row);
            await tester.pumpAndSettle();
            await tester.tapAt(
              tester
                  .getRect(row)
                  .intersect(tester.getRect(find.byType(ListView)))
                  .center,
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byTooltip('Create group'));
          await tester.pump();
          await tester.drag(find.byType(ListView), const Offset(0, 1400));
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(find.byKey(const ValueKey('group-create')))
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('group-name')))
                .enabled,
            false,
          );
          expect(
            tester
                .widgetList<ListTile>(find.byType(ListTile))
                .every((row) => row.onTap == null),
            true,
          );
          await tester.drag(find.byType(ListView), const Offset(0, 1400));
          await tester.pump();
          await _capture(
            tester,
            frame,
            'group-creation-pending-${brightness.name}-$scale',
            motion: true,
          );
          held.completeError(StateError('Connection lost before confirmation'));
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text(session.state.errors.first), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(find.byKey(const ValueKey('group-create')))
                .onPressed,
            isNotNull,
          );
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('group-name')),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('group-name')))
                .enabled,
            false,
          );
          await tester.drag(find.byType(ListView), const Offset(0, 1400));
          await tester.pumpAndSettle();
          await _capture(
            tester,
            frame,
            'group-creation-failed-${brightness.name}-$scale',
          );
          fixture.commandHook = saveIcon;
          await tester.tap(find.byTooltip('Create group'));
          await tester.pumpAndSettle();
          final creates = fixture.commands
              .where((c) => c.$2 == 'groups.create')
              .toList();
          expect(creates, hasLength(2));
          expect(creates.last.$3, creates.first.$3);
          expect(creates.first.$3['name'], 'Launch team');
          expect(
            (creates.first.$3['members'] as List).map((m) => m['profile']),
            ['atlas', 'mira'],
          );
          expect(result, true);
          expect(find.text('Open group'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'color taps repaint the saved shape preview before autosave in ${brightness.name}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = BotsFixture();
        final meta = fixture.profiles.first['ui_meta']['hermes-bots'];
        meta['shape'] = 'cloud';
        meta['imageKind'] = 'shape';
        const png =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII=';
        final bot = (await fixture.repository.bots()).first.withAvatar(
          base64Decode(png),
        );
        final frame = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            home: RepaintBoundary(
              key: frame,
              child: BotProfileEditor(
                createSession: () =>
                    BotProfileEditSession(fixture.repository, bot),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final preview = find.byWidgetPredicate(
          (widget) => widget is BotAvatar && widget.size == 88,
        );
        Future<void> expectPreviewColor(Color expected) async {
          final rect = tester.getRect(preview);
          final sample = Offset(rect.center.dx, rect.top + rect.height * .65);
          final rendered = await tester.runAsync(() async {
            final boundary =
                frame.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final rgba = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final offset =
                (sample.dy.floor() * image.width + sample.dx.floor()) * 4;
            final color = Color.fromARGB(
              rgba!.getUint8(offset + 3),
              rgba.getUint8(offset),
              rgba.getUint8(offset + 1),
              rgba.getUint8(offset + 2),
            );
            image.dispose();
            return color;
          });
          expect(rendered!.toARGB32(), expected.toARGB32());
          expect(tester.widget<BotAvatar>(preview).image, isNull);
        }

        for (final index in [0, 8, 7]) {
          await tester.tap(find.byTooltip('Color ${index + 1}'));
          await tester.pump();
          expect(
            fixture.commands,
            isEmpty,
            reason: 'Preview precedes autosave',
          );
          await expectPreviewColor(desktopProfileSwatches[index]);
        }
        await tester.tap(find.byTooltip('Match profile color'));
        await tester.pump();
        await expectPreviewColor(BotAvatar.resolveColor('', bot.profile.name));
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        await expectPreviewColor(BotAvatar.resolveColor('', bot.profile.name));
        expect(
          fixture.commands.single.$3['ui_meta']['hermes-bots']['color'],
          '',
        );
        await _capture(tester, frame, 'editor-live-color-${brightness.name}');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
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
  testWidgets(
    'canonical header borrows only its own live activity for motion',
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
      await controller.openSession(ProfileSessionKey(scope, 'canonical-root'));
      final bots = BotsFixture();
      bots.profiles
        ..clear()
        ..add(BotsFixture.profile(scope.profileName, 'Atlas'));
      bots.profiles.single['canonical_session'] = {
        'id': 'canonical-root',
        'resolved_id': 'canonical-tip',
      };
      bots.profiles.single['ui_meta']['hermes-bots']['imageKind'] = 'shape';
      var reads = 0;
      bots.readHook = (_, _, _) async {
        reads++;
        return null;
      };
      final frame = GlobalKey();
      var brightness = Brightness.dark;
      var scale = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget host() => MaterialApp(
        theme: wingTheme(brightness),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: frame,
          child: ProfileWorkspaceScreen(
            controller: controller,
            createBotsSession: () =>
                BotsSession((_) async => [bots.repository]),
          ),
        ),
      );
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.settleMarkdown();
      final face = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(LiveBotAvatar),
      );
      expect(face, findsOneWidget);
      BotAvatarMood mood() => tester.widget<LiveBotAvatar>(face).mood;
      expect(mood(), BotAvatarMood.idle);
      final chat = controller.current!.chat!;
      emitChatEvent(controller, chat, 'message.start');
      await tester.pump();
      expect(mood(), BotAvatarMood.work);
      emitChatEvent(controller, chat, 'reasoning.delta', {
        'text': 'Considering the plan.',
      });
      await tester.pump();
      expect(mood(), BotAvatarMood.think);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.settleMarkdown();
      await _capture(tester, frame, 'animated-canonical-header', motion: true);
      for (final theme in Brightness.values) {
        for (final textScale in [1.0, 2.0]) {
          brightness = theme;
          scale = textScale;
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          await tester.pumpWidget(host());
          await tester.pump(const Duration(milliseconds: 450));
          await tester.settleMarkdown();
          expect(tester.getSize(face), const Size(32, 32));
          await _capture(
            tester,
            frame,
            'animated-canonical-header-${theme.name}-$scale',
            motion: true,
          );
          expect(tester.takeException(), isNull);
        }
      }
      emitChatEvent(controller, chat, 'message.complete', {
        'text': 'The plan is ready.',
      });
      await tester.pump();
      expect(mood(), BotAvatarMood.idle);
      final before = reads;
      await tester.pump(const Duration(seconds: 1));
      expect(reads, before);
      expect(bots.commands, isEmpty);
      expect(tester.getSize(face), const Size(32, 32));
      await controller.openSession(ProfileSessionKey(scope, 'ordinary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(LiveBotAvatar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      appPreferences.dispose();
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
                  instanceHeader: const Align(
                    alignment: Alignment.centerLeft,
                    child: ServerConnectionLabel(label: 'Home server'),
                  ),
                  session: session,
                  viewState: view,
                  onViewChanged: (next) => setState(() => view = next),
                  onOpenMenu: () {},
                  onOpenChat: (key) async => opened.add(key.sessionId),
                  onOpenGroup: (group) => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => BotGroupScreen(
                        stopVoicePlayback: () async {},
                        voiceInputSettings: () =>
                            const LocalVoiceInputSettings(language: ''),
                        createSession: () => session.openGroup(group),
                        onEdit: (group) =>
                            openGroupEditor(context, session, group),
                      ),
                    ),
                  ),
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
          expect(find.byType(ServerConnectionLabel), findsOneWidget);
          expect(
            tester.getBottomLeft(find.byType(ServerConnectionLabel)).dy,
            lessThanOrEqualTo(tester.getTopLeft(find.byType(TabBar)).dy),
          );
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
          final groupIcon = find.byTooltip('Edit group Research team');
          expect(tester.getSize(groupIcon).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(groupIcon).height, greaterThanOrEqualTo(48));
          await _capture(tester, frame, 'groups-${brightness.name}-$scale');
          await tester.tap(groupIcon);
          await tester.pumpAndSettle();
          expect(find.byType(BotsCreateScreen), findsOneWidget);
          expect(find.byType(BotGroupScreen), findsNothing);
          expect(fixture.commands, isEmpty);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Research team'), findsOneWidget);
          expect(find.byTooltip('Create group'), findsOneWidget);
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
          await tester.pump();
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
          fixture.readHook = (_, method, _) async => method == 'display.status'
              ? {
                  'supported': true,
                  'installed': true,
                  'running': false,
                  'lease': {
                    'holder': 'human',
                    'viewer_hash': 'abcd1234abcd',
                    'epoch': 1,
                  },
                }
              : null;
          await tester.tap(find.byTooltip('Actions for Atlas revised'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('bot-menu-screen')));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Human has control'), findsOneWidget);
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
  testWidgets('search and hidden bots never write profiles', (tester) async {
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
            instanceHeader: const Align(
              alignment: Alignment.centerLeft,
              child: ServerConnectionLabel(label: 'Home server'),
            ),
            session: session,
            viewState: view,
            onViewChanged: (next) => setState(() => view = next),
            onOpenMenu: () {},
            onOpenChat: (_) async {},
            onOpenGroup: (group) => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => BotGroupScreen(
                  stopVoicePlayback: () async {},
                  voiceInputSettings: () =>
                      const LocalVoiceInputSettings(language: ''),
                  createSession: () => session.openGroup(group),
                  onEdit: (group) => openGroupEditor(context, session, group),
                ),
              ),
            ),
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
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Forge'), findsOneWidget);
    expect(find.text('Mira'), findsOneWidget);
    final beforeMenu = rosterReads;
    await tester.tap(find.byTooltip('Roster options'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh bots and groups'), findsNothing);
    await tester.tap(find.byType(CheckedPopupMenuItem<String>));
    await tester.pumpAndSettle();
    expect(view.showHidden, true);
    expect(rosterReads, beforeMenu);
    expect(find.text('Forge'), findsOneWidget);
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
