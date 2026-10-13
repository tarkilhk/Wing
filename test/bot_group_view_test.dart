import 'package:wing/core/widgets/studio_loading.dart';
import 'package:wing/core/widgets/wing_app_bar.dart';
import 'package:wing/core/models/connection.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/widgets/server_connection_label.dart';
import 'package:wing/core/widgets/workspace_picker.dart';
import 'package:wing/core/services/recent_conversation_snapshots.dart';
import 'package:wing/core/widgets/bot_group_conversation.dart';
import 'package:wing/core/models/voice_processing_settings.dart';
import 'dart:async';
import 'package:wing/core/services/bot_group_read_state.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/bot_avatar.dart';
import 'package:wing/core/widgets/bot_group_picture.dart';
import 'package:wing/core/widgets/bot_group_identity.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/services/bot_group_session.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/widgets/mention_suggestions.dart';
import 'support/bots_fixture.dart';
import 'package:wing/core/widgets/conversation_activity_status.dart';
import 'package:wing/core/widgets/composer_icon_button.dart';
import 'helpers/pump_markdown_widget.dart';
import 'package:wing/core/widgets/voice_input_activity.dart';
import 'package:wing/core/widgets/recent_conversations/conversation_route_scope.dart';
import 'support/voice_fixture.dart';
import 'support/administration_fixture.dart';

const _capture = bool.fromEnvironment('CAPTURE_BOT_GROUPS');

Map<String, dynamic> _event(int seq, String kind, String actor, String text) =>
    {
      'room_id': 'room-1',
      'seq': seq,
      'kind': kind,
      'actor': {
        'kind': kind == 'message.user' ? 'user' : 'member',
        'id': actor,
        'profile': actor,
      },
      'payload': {'text': text},
      'created_at': 1791756000.0 + seq * 60,
    };

Future<void> _settleGroupMarkdown(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 300));
    final pending = tester
        .stateList<BackgroundMarkdownContentState>(
          find.byType(BackgroundMarkdownContent, skipOffstage: false),
        )
        .any((state) => state.pending);
    if (!pending) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Group Markdown did not settle, including lazy-list cache children.');
}

Future<void> _render(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  for (var pass = 0; pass < 4; pass++) {
    await _settleGroupMarkdown(tester);
  }
  final shadows = debugDisableShadows;
  debugDisableShadows = false;
  try {
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    repaint(key.currentContext!.findRenderObject()!);
    await tester.pump();
    await tester.runAsync(() async {
      final frame =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await frame.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/design-previews/bot-groups')
        ..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = shadows;
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'manual group refresh is visible and automatic reads stay quiet ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          fixture.events.add(
            _event(1, 'message.member', 'atlas', 'Saved group reply'),
          );
          final group = (await fixture.repository.groups(
            groupMessages: null,
          )).first;
          final frame = GlobalKey();
          final reduced = ValueNotifier(false);
          addTearDown(reduced.dispose);
          late BotGroupSession session;
          await tester.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: wingTheme(brightness),
                builder: (context, child) => ValueListenableBuilder<bool>(
                  valueListenable: reduced,
                  builder: (_, value, _) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: value,
                    ),
                    child: child!,
                  ),
                ),
                home: BotGroupScreen(
                  stopVoicePlayback: () async {},
                  voiceInputSettings: () =>
                      const LocalVoiceInputSettings(language: ''),
                  createSession: () => session = BotGroupSession(
                    fixture.repository,
                    group,
                    reads: BotGroupReadState(),
                    groupMessages: null,
                    appearances: FixedGroupAppearances(const []),
                  ),
                ),
              ),
            ),
          );
          await _settleGroupMarkdown(tester);
          await tester.pumpAndSettle();
          final input = find.byType(TextField);
          await tester.enterText(input, 'Keep this draft');
          await tester.pumpAndSettle();
          final transcript = find.byKey(const ValueKey('group-transcript'));
          final transcriptRect = tester.getRect(transcript);
          final composerRect = tester.getRect(input);
          final menuRect = tester.getRect(find.byTooltip('Group options'));
          final stateGate = Completer<void>();
          final logGate = Completer<void>();
          final stateStarted = Completer<void>();
          final logStarted = Completer<void>();
          var stateReads = 0;
          fixture.readHook = (_, method, _) async {
            if (method == 'groups.state') {
              stateReads++;
              if (!stateStarted.isCompleted) stateStarted.complete();
              await stateGate.future;
            }
            if (method == 'groups.log') {
              if (!logStarted.isCompleted) logStarted.complete();
              await logGate.future;
            }
            return null;
          };
          final automatic = session.refresh();
          await tester.pump();
          expect(find.byType(StudioLoading), findsNothing);
          await tester.tap(find.byTooltip('Group options'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('Refresh group'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(stateStarted.isCompleted, isTrue);
          expect(stateReads, 1);
          // Wait for the dismissed popup to release its semantics scope.
          for (
            var frame = 0;
            frame < 10 &&
                find.bySemanticsLabel('Refreshing group').evaluate().isEmpty;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(find.bySemanticsLabel('Refreshing group'), findsOneWidget);
          expect(find.byType(StudioLoading), findsOneWidget);
          expect(find.text('Refreshing group'), findsNothing);
          expect(find.byIcon(Icons.more_horiz), findsOneWidget);
          expect(tester.getRect(transcript), transcriptRect);
          expect(tester.getRect(input), composerRect);
          expect(tester.getRect(find.byTooltip('Group options')), menuRect);
          expect(tester.widget<TextField>(input).readOnly, isFalse);
          await _render(tester, frame, 'refreshing-${brightness.name}-$scale');
          reduced.value = true;
          await tester.pump();
          expect(find.byType(StudioLoading), findsOneWidget);
          expect(tester.binding.transientCallbackCount, 0);
          await tester.tap(find.byTooltip('Group options'));
          await tester.pumpAndSettle();
          final item = tester.widget<StudioPopupMenuItem<String>>(
            find.widgetWithText(StudioPopupMenuItem<String>, 'Refresh group'),
          );
          expect(item.enabled, isFalse);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          fixture.events.add(
            _event(2, 'message.member', 'mira', 'Fresh group reply'),
          );
          stateGate.complete();
          await tester.pump();
          expect(logStarted.isCompleted, isTrue);
          expect(find.bySemanticsLabel('Refreshing group'), findsOneWidget);
          logGate.complete();
          await automatic;
          await _settleGroupMarkdown(tester);
          await tester.pumpAndSettle();
          expect(find.byType(StudioLoading), findsNothing);
          expect(find.text('Fresh group reply'), findsOneWidget);
          expect(
            tester.widget<TextField>(input).controller!.text,
            'Keep this draft',
          );
          expect(tester.getRect(transcript), transcriptRect);
          expect(tester.getRect(input), composerRect);
          expect(tester.getRect(find.byTooltip('Group options')), menuRect);
          expect(fixture.commands, isEmpty);
          fixture.readHook = (_, method, _) async {
            if (method == 'groups.state') throw StateError('Offline');
            return null;
          };
          await tester.tap(find.byTooltip('Group options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Refresh group'));
          await tester.pumpAndSettle();
          expect(find.byType(StudioLoading), findsNothing);
          expect(find.textContaining('could not refresh'), findsOneWidget);
          expect(find.text('Fresh group reply'), findsOneWidget);
          fixture.readHook = null;
          await tester.tap(find.byTooltip('Group options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Refresh group'));
          await tester.pumpAndSettle();
          expect(find.textContaining('could not refresh'), findsNothing);
          expect(
            tester.widget<TextField>(input).controller!.text,
            'Keep this draft',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
      testWidgets(
        'discussion instance position matches standard header ${brightness.name} $scale',
        (tester) async {
          final size = Size(scale == 1 ? 390 : 320, 844);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          final group = (await fixture.repository.groups(
            groupMessages: null,
          )).first;
          final status = ServerConnectionStatus('Claw')
            ..accessAvailable()
            ..liveChanged('discussion', true);
          addTearDown(status.dispose);
          final frame = GlobalKey();
          Widget identity() => ServerConnectionLabel(
            label: 'Claw',
            icon: ConnectionIcon.cloud,
            status: status,
          );
          Future<void> show({
            required bool discussion,
            required bool keyboard,
          }) async {
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.only(top: 24),
                    viewInsets: EdgeInsets.only(bottom: keyboard ? 280 : 0),
                  ),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: frame,
                  child: Builder(
                    builder: (context) {
                      final actions = [
                        IconButton(
                          tooltip: 'Group options',
                          onPressed: () {},
                          icon: const Icon(Icons.more_horiz),
                        ),
                      ];
                      return discussion
                          ? BotGroupConversation(
                              group: group,
                              appearances: const [],
                              instanceHeader: identity(),
                              transcript: const Center(
                                child: Text('Discussion'),
                              ),
                              composer: const SizedBox(height: 64),
                              actions: actions,
                              onBack: () {},
                              onMembers: () {},
                              showMembers: !keyboard,
                            )
                          : Scaffold(
                              appBar: WingAppBar(
                                context: context,
                                leading: const BackButton(),
                                title: WingConversationTitle(
                                  title: group.name,
                                  avatar: BotGroupIdentity(
                                    group: group,
                                    bots: const [],
                                    size: 32,
                                  ),
                                ),
                                actions: actions,
                                contextRow: Align(
                                  alignment: Alignment.centerLeft,
                                  child: identity(),
                                ),
                              ),
                              body: const Center(
                                child: Text('Standard screen'),
                              ),
                            );
                    },
                  ),
                ),
              ),
            );
            await tester.pump();
          }

          Map<String, Rect> geometry() => {
            'icon': tester.getRect(find.byIcon(Icons.cloud_outlined)),
            'led': tester.getRect(
              find.byKey(const ValueKey('server-connection-led')),
            ),
            'name': tester.getRect(find.text('Claw')),
            'details': tester.getRect(
              find.byKey(const ValueKey('connection-status-target')),
            ),
          };
          await show(discussion: false, keyboard: false);
          final standard = geometry();
          await _render(
            tester,
            frame,
            'instance-standard-${brightness.name}-$scale',
          );
          for (final keyboard in [false, true]) {
            await show(discussion: true, keyboard: keyboard);
            expect(find.byType(ServerConnectionLabel), findsOneWidget);
            expect(
              geometry(),
              standard,
              reason:
                  'The shared instance identity must occupy the standard screen position, including with the keyboard open.',
            );
            expect(tester.takeException(), isNull);
            await _render(
              tester,
              frame,
              'instance-position-${brightness.name}-$scale-keyboard-$keyboard',
            );
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'group cached landing keeps viewport geometry across first runtime refresh reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = BotsFixture();
        fixture.events.add(
          _event(
            1,
            'message.member',
            'atlas',
            'Cached reply with **bold** text.',
          ),
        );
        final cache = RecentGroupMessages();
        addTearDown(cache.dispose);
        final group = (await fixture.repository.groups(
          groupMessages: cache,
        )).single;
        final waiting = Completer<void>();
        fixture.readHook = (_, method, _) async {
          if (method == 'groups.state') await waiting.future;
          return null;
        };
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: BotGroupScreen(
              stopVoicePlayback: () async {},
              voiceInputSettings: () => null,
              createSession: () => BotGroupSession(
                fixture.repository,
                group,
                reads: BotGroupReadState(),
                groupMessages: cache,
                appearances: FixedGroupAppearances(const []),
              ),
            ),
          ),
        );
        final viewport = find.byKey(const ValueKey('group-transcript'));
        final reply = find.byKey(const ValueKey(('group-message', 1)));
        final before = tester.getRect(viewport);
        final bottom = tester.getRect(reply).bottom;
        await _settleGroupMarkdown(tester);
        expect(tester.getRect(viewport), before);
        expect(tester.getRect(reply).bottom, closeTo(bottom, .01));
        expect(find.text('Loading conversation…'), findsNothing);
        expect(find.byType(StudioLoading), findsNothing);
        expect(find.bySemanticsLabel('Loading conversation'), findsNothing);
        waiting.complete();
        await _settleGroupMarkdown(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(StudioLoading), findsNothing);
        expect(tester.getRect(viewport), before);
        expect(tester.getRect(reply).bottom, closeTo(bottom, .01));
      },
    );
  }

  testWidgets('live group prepares only the bottom on its first loaded frame', (
    tester,
  ) async {
    final fixture = BotsFixture();
    fixture.events.addAll([
      for (var i = 1; i <= 100; i++)
        _event(i, 'message.member', 'atlas', 'Message $i\n' * 20),
    ]);
    final group = (await fixture.repository.groups(groupMessages: null)).single;
    await tester.pumpWidget(
      MaterialApp(
        home: BotGroupScreen(
          stopVoicePlayback: () async {},
          voiceInputSettings: () => null,
          createSession: () => BotGroupSession(
            fixture.repository,
            group,
            reads: BotGroupReadState(),
            groupMessages: null,
            appearances: FixedGroupAppearances(const []),
          ),
        ),
      ),
    );
    await tester.pump();
    final messages = tester
        .widgetList<BotGroupMessage>(find.byType(BotGroupMessage))
        .toList();
    expect(
      messages.any((message) => message.message.id == 'room-1:100'),
      isTrue,
    );
    expect(
      messages.every(
        (message) =>
            int.parse(message.message.id.toString().split(':').last) > 90,
      ),
      isTrue,
    );
    expect(messages.length, lessThan(10));
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'group dictation shares chat controls ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          final group = (await fixture.repository.groups(
            groupMessages: null,
          )).single;
          final device = VoiceDeviceFixture();
          addTearDown(device.stream.close);
          final frame = GlobalKey();
          var playbackStops = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: frame,
                child: BotGroupScreen(
                  voiceInputSettings: () =>
                      const LocalVoiceInputSettings(language: 'fr-FR'),
                  stopVoicePlayback: () async {
                    playbackStops++;
                  },
                  voiceDevice: device,
                  createSession: () => BotGroupSession(
                    fixture.repository,
                    group,
                    groupMessages: null,
                    appearances: FixedGroupAppearances(const []),
                    reads: BotGroupReadState(),
                  ),
                ),
              ),
            ),
          );
          await _settleGroupMarkdown(tester);
          final titleBounds = tester.getRect(find.text(group.name));
          final artworkBounds = tester.getRect(find.byType(BotGroupIdentity));
          expect(artworkBounds.size, const Size(32, 32));
          expect(titleBounds.left - artworkBounds.right, closeTo(8, .01));
          expect(titleBounds.center.dy, closeTo(artworkBounds.center.dy, .01));
          final input = find.byKey(const ValueKey('group-message-composer'));
          await tester.enterText(input, 'Plan: replace later');
          final editing = tester.widget<TextField>(input).controller!;
          editing.selection = const TextSelection(
            baseOffset: 6,
            extentOffset: 13,
          );
          await tester.pump();
          await _render(tester, frame, 'voice-idle-${brightness.name}-$scale');
          expect(find.byType(VoiceInputButton), findsOneWidget);
          await tester.tap(find.byTooltip('Dictate message'));
          await tester.pump();
          expect(device.language, 'fr-FR');
          expect(device.local, isTrue);
          expect(playbackStops, 1);
          expect(tester.widget<TextField>(input).readOnly, isTrue);
          expect(find.byType(VoiceInputActivity), findsOneWidget);
          expect(find.byTooltip('Stop recording'), findsOneWidget);
          expect(find.byTooltip('Cancel recording'), findsOneWidget);
          expect(find.text('Cancel recording'), findsNothing);
          final send = tester.widget<ComposerIconButton>(
            find.byType(ComposerIconButton),
          );
          expect(send.onPressed, isNull);
          device.stream.add({
            'id': device.recording,
            'text': 'spoken',
            'final': false,
          });
          await tester.pump();
          await _render(
            tester,
            frame,
            'voice-recording-${brightness.name}-$scale',
          );
          final oldText = editing.text;
          await tester.tap(find.byTooltip('Cancel recording'));
          await tester.pump();
          expect(editing.text, oldText);
          expect(
            editing.selection,
            const TextSelection(baseOffset: 6, extentOffset: 13),
          );
          await tester.tap(find.byTooltip('Dictate message'));
          await tester.pump();
          device.stream.add({
            'id': device.recording,
            'text': 'spoken',
            'final': true,
          });
          await tester.pump();
          expect(editing.text, 'Plan: spoken later');
          expect(editing.selection.extentOffset, 12);
          expect(fixture.commands, isEmpty);
          final speechError = List.filled(
            3,
            'Speech processing failed. Check your connection and profile speech settings, then retry.',
          ).join(' ');
          device.startError = StateError(speechError);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pump();
          await tester.tap(find.byTooltip('Dictate message'));
          await tester.pump();
          expect(find.text(speechError), findsOneWidget);
          expect(editing.text, 'Plan: spoken later');
          expect(
            tester.getRect(find.byTooltip('Dictate message')).bottom,
            lessThanOrEqualTo(844 - 280),
          );
          await _render(tester, frame, 'voice-error-${brightness.name}-$scale');
          final errorScroll = find.descendant(
            of: find.byType(VoiceInputActivity),
            matching: find.byType(Scrollable),
          );
          final errorPosition = tester
              .state<ScrollableState>(errorScroll)
              .position;
          expect(errorPosition.maxScrollExtent, greaterThan(0));
          await tester.drag(
            find.descendant(
              of: find.byType(VoiceInputActivity),
              matching: find.byType(SingleChildScrollView),
            ),
            const Offset(0, -60),
          );
          await tester.pump();
          expect(errorPosition.pixels, greaterThan(0));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('group dictation cancels when Recents obscures the discussion', (
    tester,
  ) async {
    final fixture = BotsFixture();
    final group = (await fixture.repository.groups(groupMessages: null)).single;
    final device = VoiceDeviceFixture();
    addTearDown(device.stream.close);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final screen = BotGroupScreen(
      voiceInputSettings: () => const LocalVoiceInputSettings(language: ''),
      stopVoicePlayback: () async {},
      voiceDevice: device,
      createSession: () => BotGroupSession(
        fixture.repository,
        group,
        groupMessages: null,
        appearances: FixedGroupAppearances(const []),
        reads: BotGroupReadState(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: visible,
          builder: (_, value, child) => ConversationPresentationScope(
            visible: value,
            onInputActivityChanged: (_) {},
            child: child!,
          ),
          child: screen,
        ),
      ),
    );
    await _settleGroupMarkdown(tester);
    final input = find.byKey(const ValueKey('group-message-composer'));
    await tester.enterText(input, 'Keep this draft');
    await tester.tap(find.byTooltip('Dictate message'));
    await tester.pump();
    final id = device.recording;
    visible.value = false;
    await tester.pump();
    expect(device.cancelled, contains(id));
    device.stream.add({'id': id, 'text': 'late speech', 'final': true});
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, 'Keep this draft');
    visible.value = true;
    await tester.pump();
    expect(find.byTooltip('Cancel recording'), findsNothing);
    await tester.tap(find.byTooltip('Dictate message'));
    await tester.pump();
    final backgroundId = device.recording;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(device.cancelled, contains(backgroundId));
    device.stream.add({
      'id': backgroundId,
      'text': 'background speech',
      'final': true,
    });
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, 'Keep this draft');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'group dictation uses Hermes and preserves drafts after microphone failure',
    (tester) async {
      final server = AdministrationFixture();
      final fixture = BotsFixture(server: server.server);
      final group = (await fixture.repository.groups(
        groupMessages: null,
      )).single;
      final device = VoiceDeviceFixture()
        ..startError = StateError('Microphone unavailable');
      addTearDown(device.stream.close);
      final transcript = Completer<Map<String, dynamic>>();
      server.mutationOverride =
          (method, path, query, body, canDispatch, onDispatched) async {
            expect(canDispatch(), isTrue);
            onDispatched();
            server.requests.add((method, path, query, body));
            return transcript.future;
          };
      await tester.pumpWidget(
        MaterialApp(
          home: BotGroupScreen(
            voiceInputSettings: () => const HermesVoiceInputSettings(),
            stopVoicePlayback: () async {},
            voiceDevice: device,
            createSession: () => BotGroupSession(
              fixture.repository,
              group,
              groupMessages: null,
              appearances: FixedGroupAppearances(const []),
              reads: BotGroupReadState(),
            ),
          ),
        ),
      );
      await _settleGroupMarkdown(tester);
      final input = find.byKey(const ValueKey('group-message-composer'));
      await tester.enterText(input, 'Draft');
      await tester.tap(find.byTooltip('Dictate message'));
      await tester.pump();
      expect(find.text('Microphone unavailable'), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, 'Draft');
      device.startError = null;
      await tester.tap(find.byTooltip('Dictate message'));
      await tester.pump();
      expect(device.local, isFalse);
      await tester.tap(find.byTooltip('Stop recording'));
      await tester.pump();
      expect(find.text('Transcribing…'), findsOneWidget);
      expect(server.requests.single.$3, {'profile': 'default'});
      expect(server.requests.single.$4, {
        'data_url': 'data:audio/mp4;base64,AQID',
        'mime_type': 'audio/mp4',
      });
      transcript.complete({'ok': true, 'transcript': 'spoken'});
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, 'Draft spoken');
      expect(fixture.commands, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('covered group editor stays paused across app resume', (
    tester,
  ) async {
    final fixture = BotsFixture();
    final group = (await fixture.repository.groups(groupMessages: null)).first;
    final appearances = await fixture.repository.bots();
    var reads = 0;
    fixture.readHook = (_, method, _) async {
      if (method == 'groups.state') reads++;
      return null;
    };
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: BotGroupScreen(
          stopVoicePlayback: () async {},
          voiceInputSettings: () => const LocalVoiceInputSettings(language: ''),
          createSession: () => BotGroupSession(
            fixture.repository,
            group,
            reads: BotGroupReadState(),
            groupMessages: null,
            appearances: FixedGroupAppearances(appearances),
          ),
          onEdit: (_) async {
            await navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Group editor')),
              ),
            );
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Group options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit group'));
    await tester.pumpAndSettle();
    expect(find.text('Group editor'), findsOneWidget);
    final coveredReads = reads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    expect(reads, coveredReads);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(reads, greaterThan(coveredReads));
    expect(tester.takeException(), isNull);
  });

  setUpAll(() async {
    if (!_capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'monospace': 'build/studio-mono.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets('group replies use shared formatted sender bubbles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = BotsFixture();
    fixture.events.add({
      'room_id': 'room-1',
      'seq': 1,
      'kind': 'message.member',
      'actor': {'kind': 'member', 'id': 'atlas', 'profile': 'atlas'},
      'payload': {
        'text':
            '**Read-only sources.**\n\n- [Mission](https://example.com/mission)\n- `verified`',
      },
      'created_at': 1791756000.0,
    });
    fixture.events.add(
      _event(2, 'message.user', 'you', '**Literal user text** @bot_atlas'),
    );
    final group = (await fixture.repository.groups(groupMessages: null)).first;
    final appearances = await fixture.repository.bots();
    await tester.pumpWidget(
      MaterialApp(
        home: BotGroupScreen(
          stopVoicePlayback: () async {},
          voiceInputSettings: () => const LocalVoiceInputSettings(language: ''),
          createSession: () => BotGroupSession(
            fixture.repository,
            group,
            reads: BotGroupReadState(),
            groupMessages: null,
            appearances: FixedGroupAppearances(appearances),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.settleMarkdown();
    expect(find.byType(ProfileMessage), findsNWidgets(2));
    expect(find.text('User'), findsOneWidget);
    final userText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .firstWhere(
          (text) =>
              text.textSpan?.toPlainText().contains('Literal user') ?? false,
        );
    expect(userText.textSpan!.toPlainText(), '**Literal user text** @Atlas');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<(String, Object?)>((
            'user-message-bubble',
            'room-1:2',
          )),
        ),
        matching: find.byTooltip('Copy message'),
      ),
    );
    expect(copied, '**Literal user text** @bot_atlas');

    for (final (kind, id, speaker) in [
      ('bot-message-bubble', 'room-1:1', 'Atlas'),
      ('user-message-bubble', 'room-1:2', 'User'),
    ]) {
      final bubble = find.byKey(ValueKey<(String, Object?)>((kind, id)));
      final copy = find.descendant(
        of: bubble,
        matching: find.byTooltip('Copy message'),
      );
      final label = find.descendant(of: bubble, matching: find.text(speaker));
      expect(copy, findsOneWidget);
      expect(
        tester.getCenter(copy).dy,
        closeTo(tester.getCenter(label).dy, .1),
      );
      expect(
        tester.getRect(bubble).right,
        closeTo(kind == 'bot-message-bubble' ? 350 : 366, .1),
      );
    }
    expect(find.text('Atlas'), findsWidgets);
    expect(find.textContaining('**Read-only'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'group composer, sender identity and recovery ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          fixture.events.addAll([
            _event(
              1,
              'message.user',
              'you',
              'Let’s build Pace Health Analysis. @bot_atlas will build it; @bot_mira will review the evidence.',
            ),
            _event(
              2,
              'message.member',
              'atlas',
              'Saved our shared mission in [docs/mission.md](https://example.com/mission).\n\n**Acceptance gates**\n- Read-only sources\n- Reproducible calculations\n- Every conclusion links to evidence',
            ),
            _event(
              3,
              'message.member',
              'mira',
              'I’ll review the scientific assumptions before implementation. The comparison windows and missing-data rules need your approval.',
            ),
          ]);
          final group = (await fixture.repository.groups(groupMessages: null))
              .first
              .withIcon(
                picture: File('assets/icon/icon.png').readAsBytesSync(),
              );
          final appearances = await fixture.repository.bots();
          final frame = GlobalKey();
          final keyboard = ValueNotifier<bool>(false);
          addTearDown(keyboard.dispose);
          late BotGroupSession session;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => ValueListenableBuilder<bool>(
                valueListenable: keyboard,
                builder: (context, shown, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: EdgeInsets.only(bottom: shown ? 280 : 0),
                  ),
                  child: child!,
                ),
              ),
              home: RepaintBoundary(
                key: frame,
                child: BotGroupScreen(
                  stopVoicePlayback: () async {},
                  voiceInputSettings: () =>
                      const LocalVoiceInputSettings(language: ''),
                  createSession: () => session = BotGroupSession(
                    fixture.repository,
                    group,
                    reads: BotGroupReadState(),
                    groupMessages: null,
                    appearances: FixedGroupAppearances(appearances),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _settleGroupMarkdown(tester);
          expect(
            tester.widget<BotGroupPicture>(find.byType(BotGroupPicture)).image,
            group.picture,
          );
          expect(tester.takeException(), isNull);
          if (scale == 1) expect(find.byType(BotAvatar), findsWidgets);
          final input = find.byKey(const ValueKey('group-message-composer'));
          final send = find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Send group message',
          );
          expect(tester.widget<IconButton>(send).onPressed, isNull);
          await _render(
            tester,
            frame,
            'conversation-${brightness.name}-$scale',
          );
          expect(find.byType(ActionChip), findsNothing);
          await tester.enterText(input, 'Review @at this evidence');
          final controller = tester.widget<TextField>(input).controller!;
          controller.selection = const TextSelection.collapsed(offset: 10);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(MentionSuggestions),
              matching: find.text('Atlas'),
            ),
          );
          await tester.pump();
          expect(controller.text, 'Review @Atlas this evidence');
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
          final transcript = tester
              .widget<ListView>(find.byKey(const ValueKey('group-transcript')))
              .controller!;
          fixture.events.add(
            _event(
              4,
              'message.member',
              'atlas',
              'Evidence review\n\n${List.filled(8, 'The approved source list and calculation definitions are recorded in our shared mission.').join('\n\n')}',
            ),
          );
          await session.refresh();
          await tester.pumpAndSettle();
          await _settleGroupMarkdown(tester);
          transcript.jumpTo(transcript.position.maxScrollExtent);
          await tester.pumpAndSettle();
          final anchor = find.byKey(const ValueKey(('group-message', 1)));
          final before = tester.getRect(anchor);
          fixture.events.add(
            _event(
              5,
              'message.member',
              'atlas',
              'Another reply while you read earlier messages.',
            ),
          );
          await session.refresh();
          await tester.pumpAndSettle();
          await _settleGroupMarkdown(tester);
          expect(tester.getRect(anchor).top, closeTo(before.top, 1));
          expect(find.byTooltip('Jump to latest messages'), findsOneWidget);
          await _render(tester, frame, 'reading-${brightness.name}-$scale');
          await tester.tap(find.byTooltip('Jump to latest messages'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(transcript.offset, greaterThan(0));
          expect(
            transcript.offset,
            lessThan(transcript.position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey(('group-message', 5))),
            findsOneWidget,
          );
          expect(transcript.offset, closeTo(0, .01));
          await _render(tester, frame, 'draft-${brightness.name}-$scale');
          fixture.sendLost = true;
          await tester.tap(send);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(input).readOnly, isTrue);
          expect(controller.text, 'Review @Atlas this evidence');
          expect(find.byTooltip('Retry same message'), findsOneWidget);
          expect(find.byType(ActionChip), findsNothing);
          await _render(tester, frame, 'uncertain-${brightness.name}-$scale');
          await tester.tap(find.byTooltip('Retry same message'));
          await tester.pumpAndSettle();
          expect(controller.text, isEmpty);
          expect(
            fixture.commands.where((command) => command.$2 == 'groups.send'),
            hasLength(2),
          );
          expect(
            fixture.events.where((event) => event['kind'] == 'message.user'),
            hasLength(2),
          );
          final details = find.byKey(
            const ValueKey('connection-status-target'),
          );
          final standardDetails = tester.getRect(details);
          keyboard.value = true;
          await tester.enterText(
            input,
            List.filled(8, 'Please review the evidence.').join('\n'),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(send).bottom, lessThanOrEqualTo(844 - 280));
          expect(details, findsOneWidget);
          expect(tester.getRect(details), standardDetails);
          expect(tester.takeException(), isNull);
          await _render(tester, frame, 'keyboard-${brightness.name}-$scale');
          await tester.pumpWidget(const SizedBox());
        },
      );
      testWidgets('group status and members ${brightness.name} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = BotsFixture();
        fixture.events.addAll([
          _event(
            1,
            'message.member',
            'atlas',
            '@bot_mira, I’m checking the evidence before the build. ${List.filled(8, 'The approved sources and calculation definitions are in our shared mission.').join(' ')}',
          ),
          _event(
            2,
            'message.user',
            'you',
            '@bot_atlas, please review this evidence and explain what I need to do next.',
          ),
        ]);
        final group = (await fixture.repository.groups(
          groupMessages: null,
        )).first;
        final appearances = await fixture.repository.bots();
        var working = true, approval = false;
        final initialRead = Completer<void>();
        fixture.readHook = (profile, method, params) async {
          if (method != 'groups.state') return null;
          await initialRead.future;
          return {
            'room': fixture.room,
            'driver_status': {
              'working': working,
              'blocked': approval,
              'pending_actions': approval
                  ? [
                      {
                        'kind': 'approval',
                        'task_id': 'task-1',
                        'member_id': 'atlas',
                        'request_id': 'approval-1',
                        'execution_generation': 1,
                        'approval': {
                          'command': 'build',
                          'choices': ['once', 'deny'],
                        },
                      },
                    ]
                  : [],
            },
          };
        };
        final connectionStatus = ServerConnectionStatus(group.instance)
          ..accessAvailable()
          ..liveChanged('discussion', true);
        addTearDown(connectionStatus.dispose);
        WorkspacePickerMode? pickedMode;
        final frame = GlobalKey();
        final reduced = ValueNotifier<bool>(false);
        addTearDown(reduced.dispose);
        late BotGroupSession session;
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => ValueListenableBuilder<bool>(
                valueListenable: reduced,
                builder: (context, value, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: value,
                  ),
                  child: ServerConnectionScope(
                    status: connectionStatus,
                    icon: ConnectionIcon.cloud,
                    onPickWorkspace: (_, {required mode}) => pickedMode = mode,
                    child: child!,
                  ),
                ),
              ),
              home: BotGroupScreen(
                stopVoicePlayback: () async {},
                voiceInputSettings: () =>
                    const LocalVoiceInputSettings(language: ''),
                createSession: () => session = BotGroupSession(
                  fixture.repository,
                  group,
                  reads: BotGroupReadState(),
                  groupMessages: null,
                  appearances: FixedGroupAppearances(appearances),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Loading conversation…'), findsNothing);
        expect(find.byType(StudioLoading), findsOneWidget);
        expect(find.bySemanticsLabel('Loading conversation'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await _render(tester, frame, 'loading-${brightness.name}-$scale');
        initialRead.complete();
        await _settleGroupMarkdown(tester);
        await _settleGroupMarkdown(tester);
        expect(find.text('Bots are working…'), findsOneWidget);
        expect(find.byType(ConversationActivityStatus), findsOneWidget);
        expect(find.byType(StudioLoading), findsOneWidget);
        expect(find.byTooltip('Refresh group'), findsNothing);
        expect(find.byTooltip('Stop group work'), findsOneWidget);
        expect(find.byType(ComposerIconButton), findsOneWidget);
        expect(find.text('R'), findsNothing);
        final identity = find.byType(ServerConnectionLabel);
        expect(identity, findsOneWidget);
        expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
        expect(find.text(group.instance), findsOneWidget);
        expect(find.text('${group.instance} · 2 bots'), findsNothing);
        final led = find.byKey(const ValueKey('server-connection-led'));
        expect(led, findsOneWidget);
        Color ledColor() =>
            (tester.widget<Container>(led).decoration! as BoxDecoration).color!;
        final context = tester.element(identity);
        expect(ledColor(), WingTokens.of(context).success);
        connectionStatus.accessFailed(const SocketException('Offline'));
        connectionStatus.liveChanged('discussion', false);
        await tester.pump();
        expect(ledColor(), WingTokens.of(context).danger);
        await tester.tap(
          find.byKey(const ValueKey('connection-status-target')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Disconnected'), findsOneWidget);
        expect(
          find.byKey(const ValueKey(('group-member', 'atlas'))),
          findsNothing,
        );
        await tester.tap(find.byTooltip('Close connection details'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        connectionStatus.accessAvailable();
        connectionStatus.liveChanged('discussion', true);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('workspace-picker-target')));
        await tester.pump();
        expect(pickedMode, WorkspacePickerMode.connections);
        final memberButton = find.byKey(const ValueKey('group-members-entry'));
        expect(tester.getSize(memberButton), const Size(48, 48));
        expect(
          tester.widget<IconButton>(memberButton).tooltip,
          'Show group members · 2 bots',
        );
        await _render(tester, frame, 'working-${brightness.name}-$scale');
        final transcript = tester
            .widget<ListView>(find.byKey(const ValueKey('group-transcript')))
            .controller!;
        transcript.jumpTo(transcript.position.maxScrollExtent);
        await tester.pump();
        final readingOffset = transcript.offset;
        approval = true;
        await session.refresh();
        await tester.pump(const Duration(milliseconds: 300));
        expect(transcript.offset, readingOffset);
        expect(find.text('Waiting for your approval'), findsOneWidget);
        expect(find.byType(ShaderMask), findsNothing);
        expect(find.byType(StudioLoading), findsNothing);
        await _render(tester, frame, 'approval-${brightness.name}-$scale');
        approval = false;
        await session.refresh();
        await tester.pump(const Duration(milliseconds: 300));
        reduced.value = true;
        await tester.pump();
        expect(find.byType(StudioLoading), findsOneWidget);
        expect(find.text('Bots are working…'), findsOneWidget);
        reduced.value = false;
        await tester.pump();
        final input = find.byKey(const ValueKey('group-message-composer'));
        await tester.enterText(input, 'Keep this draft');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byTooltip('Send group message'), findsOneWidget);
        final entry = find.byKey(const ValueKey('group-members-entry'));
        final anchorRect = tester.getRect(entry);
        await tester.tap(entry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(Dialog), findsNothing);
        final atlas = find.byKey(const ValueKey(('group-member', 'atlas')));
        final mira = find.byKey(const ValueKey(('group-member', 'mira')));
        expect(
          find.descendant(of: atlas, matching: find.text('Atlas')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: mira, matching: find.text('Mira')),
          findsOneWidget,
        );
        final firstRect = tester.getRect(atlas);
        expect(firstRect.top, closeTo(anchorRect.bottom + 8, 1));
        expect(firstRect.right, closeTo(anchorRect.right, 1));
        expect(firstRect.width, lessThanOrEqualTo(280));
        if (scale == 1) expect(firstRect.height, lessThanOrEqualTo(36));
        expect(find.text('Group members'), findsNothing);
        await _render(tester, frame, 'members-${brightness.name}-$scale');
        await tester.tapAt(const Offset(10, 500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(atlas, findsNothing);
        await tester.tap(entry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(atlas, findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(atlas, findsNothing);
        await tester.tap(find.byTooltip('Group options'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Group members'), findsNothing);
        expect(find.text('Refresh group'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Keep this draft',
        );
        expect(fixture.commands, isEmpty);
        final sending = Completer<void>();
        fixture.commandHook = (profile, method, params) async {
          if (method == 'groups.send') await sending.future;
          return null;
        };
        await tester.tap(find.byTooltip('Send group message'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Sending message…'), findsOneWidget);
        expect(tester.widget<TextField>(input).readOnly, isTrue);
        expect(find.byType(StudioLoading), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ComposerIconButton),
            matching: find.byType(StudioLoading),
          ),
          findsNothing,
        );
        await _render(tester, frame, 'sending-${brightness.name}-$scale');
        sending.complete();
        await _settleGroupMarkdown(tester);
        working = false;
        await session.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Bots are working…'), findsNothing);
        expect(find.byType(StudioLoading), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
