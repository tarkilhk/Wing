import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/widgets/server_connection_label.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/screens/bots/bots_content.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/bot_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bots_fixture.dart';

const _export = bool.fromEnvironment('CAPTURE_BOT_MOTION');
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII=';

Future<BotRecord> _bot({
  String? kind = 'shape',
  String? shape = 'circle',
}) async {
  final fixture = BotsFixture();
  final meta = fixture.profiles.first['ui_meta']['hermes-bots'];
  meta.remove('shape');
  if (shape != null) meta['shape'] = shape;
  if (kind != null) meta['imageKind'] = kind;
  return (await fixture.repository.bots()).first;
}

Widget _host(Widget child, {bool reduced = false, bool ticking = true}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduced,
        ),
        child: TickerMode(
          enabled: ticking,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

Future<Uint8List> _pixels(
  WidgetTester tester,
  GlobalKey key, {
  String? filename,
}) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final result = Uint8List.fromList(bytes!.buffer.asUint8List());
    if (_export && filename != null) {
      final dir = Directory('build/design-previews/bot-motion')
        ..createSync(recursive: true);
      await File('${dir.path}/$filename.png').writeAsBytes(result);
    }
    return result;
  }))!;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  setUpAll(() async {
    if (!_export) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'active group reaches member bot rows ${brightness.name} $scale',
        (tester) async {
          final fixture = BotsFixture();
          for (final row in fixture.profiles) {
            row['ui_meta']['hermes-bots']['imageKind'] = 'shape';
          }
          var working = true;
          fixture.readHook = (_, method, _) async => switch (method) {
            'session.active_list' => {'sessions': []},
            'groups.state' => {
              'room': {...fixture.room, 'latest_seq': 0},
              'driver_status': {
                'working': working,
                'blocked': false,
                'counts': working ? {'running': 1} : {'completed': 1},
                'pending_actions': [],
              },
            },
            _ => null,
          };
          final session = BotsSession((_) async => [fixture.repository]);
          addTearDown(session.dispose);
          await session.refresh();
          expect(session.state.groups.single.working, true);
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final frame = GlobalKey();
          var view = const BotsViewState();
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: frame, child: child!),
              ),
              home: StatefulBuilder(
                builder: (context, setState) => BotsContent(
                  instanceHeader: const Text('Claw'),
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
          await tester.pump();
          final atlas = find.byWidgetPredicate(
            (w) => w is LiveBotAvatar && w.bot.profile.name == 'atlas',
          );
          expect(
            find.text('Group running'),
            scale == 1 ? findsNWidgets(2) : findsWidgets,
          );
          expect(tester.widget<LiveBotAvatar>(atlas).mood, BotAvatarMood.idle);
          Future<Uint8List> pixels() async => (await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.descendant(
                of: atlas,
                matching: find.byType(RepaintBoundary),
              ),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            image.dispose();
            return Uint8List.fromList(bytes!.buffer.asUint8List());
          }))!;
          await tester.pump(const Duration(milliseconds: 150));
          final before = await pixels();
          await tester.pump(const Duration(milliseconds: 700));
          expect(await pixels(), isNot(orderedEquals(before)));
          await _pixels(
            tester,
            frame,
            filename: 'active-group-bots-${brightness.name}-$scale',
          );
          working = false;
          await session.refresh();
          await tester.pump();
          expect(find.text('Group running'), findsNothing);
          expect(tester.widget<LiveBotAvatar>(atlas).mood, BotAvatarMood.idle);
          expect(fixture.commands, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  test(
    'eligibility requires an explicit saved classic shape, even with an asset',
    () async {
      for (final shape in botShapes) {
        expect(
          (await _bot(
            shape: shape,
          )).withAvatar(base64Decode(_png)).hasExplicitClassicShape,
          true,
        );
      }
      for (final bot in [
        await _bot(kind: null),
        await _bot(kind: 'photo'),
        await _bot(kind: 'unexpected'),
        await _bot(shape: null),
        await _bot(shape: 'blobatar:abc:round'),
        await _bot(shape: 'sigil-1'),
        await _bot(shape: 'unknown'),
      ]) {
        expect(bot.hasExplicitClassicShape, false);
      }
    },
  );

  testWidgets(
    'ambiguous images stay images; explicit shape snapshots animate',
    (tester) async {
      final ambiguous = (await _bot(kind: null)).withAvatar(base64Decode(_png));
      await tester.pumpWidget(
        _host(
          LiveBotAvatar(
            bot: ambiguous,
            name: 'Atlas',
            mood: BotAvatarMood.work,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      final explicit = (await _bot()).withAvatar(base64Decode(_png));
      await tester.pumpWidget(
        _host(
          LiveBotAvatar(bot: explicit, name: 'Atlas', mood: BotAvatarMood.work),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'motion repaints without rebuilding its parent and blends mood changes',
    (tester) async {
      final bot = await _bot();
      final frame = GlobalKey();
      var builds = 0;
      Widget face(BotAvatarMood mood) => _host(
        RepaintBoundary(
          key: frame,
          child: Builder(
            builder: (_) {
              builds++;
              return LiveBotAvatar(bot: bot, name: 'Atlas', mood: mood);
            },
          ),
        ),
      );
      await tester.pumpWidget(face(BotAvatarMood.idle));
      await tester.pump();
      final before = await _pixels(tester, frame);
      final count = builds;
      await tester.pump(const Duration(milliseconds: 800));
      final after = await _pixels(tester, frame);
      expect(after, isNot(orderedEquals(before)));
      expect(builds, count);
      await tester.pumpWidget(face(BotAvatarMood.think));
      final initial = await _pixels(tester, frame);
      await tester.pump(const Duration(milliseconds: 200));
      final during = await _pixels(tester, frame);
      await tester.pump(const Duration(milliseconds: 300));
      final settled = await _pixels(tester, frame);
      expect(during, isNot(orderedEquals(initial)));
      expect(settled, isNot(orderedEquals(during)));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reduced motion and disabled ticker mode park on a stable frame',
    (tester) async {
      final bot = await _bot();
      final frame = GlobalKey();
      Widget face({bool reduced = false, bool ticking = true}) => _host(
        RepaintBoundary(
          key: frame,
          child: LiveBotAvatar(
            bot: bot,
            name: 'Atlas',
            mood: BotAvatarMood.work,
          ),
        ),
        reduced: reduced,
        ticking: ticking,
      );
      for (final mode in [(true, true), (false, false)]) {
        await tester.pumpWidget(face(reduced: mode.$1, ticking: mode.$2));
        await tester.pumpAndSettle();
        final before = await _pixels(tester, frame);
        await tester.pump(const Duration(seconds: 2));
        expect(await _pixels(tester, frame), orderedEquals(before));
        expect(tester.binding.transientCallbackCount, 0);
      }
      await tester.pumpWidget(face());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(face(reduced: true));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('paint updates are capped during continuous motion', (
    tester,
  ) async {
    final bot = await _bot();
    await tester.pumpWidget(
      _host(LiveBotAvatar(bot: bot, name: 'Atlas', mood: BotAvatarMood.work)),
    );
    await tester.pump();
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(LiveBotAvatar),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    var updates = 0;
    void count() => updates++;
    painter.addListener(count);
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(updates, greaterThan(0));
    expect(updates, lessThanOrEqualTo(8));
    painter.removeListener(count);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounding stops motion and returning resumes it', (
    tester,
  ) async {
    final bot = await _bot();
    await tester.pumpWidget(
      _host(LiveBotAvatar(bot: bot, name: 'Atlas', mood: BotAvatarMood.work)),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'offscreen mounted roster faces stop ticking until scrolled back',
    (tester) async {
      final bot = await _bot();
      final scroll = ScrollController();
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 120,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  LiveBotAvatar(
                    bot: bot,
                    name: 'Atlas',
                    mood: BotAvatarMood.work,
                  ),
                  const SizedBox(height: 800),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      scroll.jumpTo(300);
      await tester.pump();
      await tester.pump();
      expect(find.byType(LiveBotAvatar), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      scroll.jumpTo(0);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets('covered route stops motion and popping resumes it', (
    tester,
  ) async {
    final bot = await _bot();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
          body: LiveBotAvatar(
            bot: bot,
            name: 'Atlas',
            mood: BotAvatarMood.work,
          ),
        ),
      ),
    );
    await tester.pump();
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Settings')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'passive canonical title remains still even for an explicit shape',
    (tester) async {
      final bot = await _bot();
      await tester.pumpWidget(
        _host(BotConversationTitle(title: 'Bot Chat', bot: bot, mood: null)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BotAvatar), findsOneWidget);
      expect(find.byType(LiveBotAvatar), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'roster and header motion at ${brightness.name} $scale text',
        (tester) async {
          var now = DateTime.utc(2026, 10, 12, 12);
          final fixture = BotsFixture(now: () => now);
          fixture.profiles.first['worker_session'] = {
            'id': 'private-worker',
            'source': 'kanban',
            'last_active': now.millisecondsSinceEpoch / 1000,
          };
          for (final row in fixture.profiles) {
            row['ui_meta']['hermes-bots']['imageKind'] = 'shape';
          }
          fixture.profiles.first['ui_meta']['hermes-bots']['shape'] =
              'triangle';
          final session = BotsSession((_) async => [fixture.repository]);
          await session.refresh();
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final frame = GlobalKey();
          var view = const BotsViewState();
          final opened = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              debugShowCheckedModeBanner: false,
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
                  onOpenGroup: (_) async {},
                ),
              ),
            ),
          );
          await tester.pump();
          final writes = fixture.commands.length;
          final workerAvatar = find.byWidgetPredicate(
            (widget) =>
                widget is LiveBotAvatar && widget.bot.profile.name == 'atlas',
          );
          expect(
            tester.widget<LiveBotAvatar>(workerAvatar).mood,
            BotAvatarMood.idle,
          );
          expect(find.text('Running'), findsNWidgets(2));
          Future<Uint8List> workerPixels() async =>
              (await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.descendant(
                    of: workerAvatar,
                    matching: find.byType(RepaintBoundary),
                  ),
                );
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                );
                image.dispose();
                return Uint8List.fromList(bytes!.buffer.asUint8List());
              }))!;
          await tester.pump(const Duration(milliseconds: 150));
          final before = await workerPixels();
          for (final elapsed in [150, 450, 950]) {
            await tester.pump(Duration(milliseconds: elapsed));
            await _pixels(
              tester,
              frame,
              filename: 'roster-${brightness.name}-$scale-$elapsed',
            );
          }
          expect(await workerPixels(), isNot(orderedEquals(before)));
          now = now.add(const Duration(seconds: 150));
          await session.refresh();
          await tester.pump();
          expect(
            tester.widget<LiveBotAvatar>(workerAvatar).mood,
            BotAvatarMood.idle,
          );
          expect(find.text('Ready'), findsOneWidget);
          expect(fixture.commands.length, writes);
          expect(
            tester
                .widget<LiveBotAvatar>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is LiveBotAvatar &&
                        widget.bot.profile.name == 'forge',
                  ),
                )
                .mood,
            BotAvatarMood.idle,
          );
          final avatarAction = find.byTooltip(
            'Edit name & appearance for Atlas',
          );
          expect(tester.getSize(avatarAction), const Size(56, 56));
          await tester.tap(find.text('Atlas').last);
          await tester.pump();
          expect(opened, ['atlas-chat']);
          final bot = session.state.bots.first;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              debugShowCheckedModeBanner: false,
              home: MediaQuery(
                data: MediaQueryData(
                  size: tester.view.physicalSize,
                  textScaler: TextScaler.linear(scale),
                ),
                child: RepaintBoundary(
                  key: frame,
                  child: Scaffold(
                    appBar: AppBar(
                      title: BotConversationTitle(
                        title: 'Bot Chat',
                        bot: bot,
                        mood: BotAvatarMood.think,
                      ),
                    ),
                    body: const Text('Conversation reply'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 750));
          expect(
            tester.getSize(find.byType(LiveBotAvatar)),
            const Size(32, 32),
          );
          await _pixels(
            tester,
            frame,
            filename: 'header-${brightness.name}-$scale',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          session.dispose();
        },
      );
    }
  }
}
