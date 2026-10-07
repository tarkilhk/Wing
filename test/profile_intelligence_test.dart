import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/models/chat_intelligence.dart';
import 'package:wing/core/models/model_choice.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_intelligence_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_INTELLIGENCE');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'Ahem': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
    }.entries) {
      final bytes = File(entry.value).readAsBytesSync();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  late ProfileIntelligenceFixture host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late SharedPreferences prefs;
  Future<ProfileWorkspaceController> open() async {
    final c = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'picker-test',
      preferences: prefs,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    await c.initialize();
    await c.createChat(canDispatch: () => true);
    return c;
  }

  const selection = ChatIntelligenceSelection(
    choice: ModelChoice(provider: 'openai-codex', model: 'gpt-5.6-sol'),
    reasoningEffort: 'xhigh',
    fastMode: ChatFastMode.normal,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(prefs);
    host = ProfileIntelligenceFixture();
    controller = await open();
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  test(
    'selection writes the session and reopen uses server settings',
    () async {
      final chat = controller.current!.chat!;
      final intelligence = await controller.loadIntelligence(chat);
      expect(intelligence.choices.first.providerLabel, 'OpenAI subscription');
      await controller.setIntelligence(
        chat,
        selection,
        confirmModelChange: (_) async => fail('Unexpected confirmation'),
      );
      expect(host.writes, hasLength(2));
      expect(
        host.writes.first['value'],
        'gpt-5.6-sol --provider openai-codex --session',
      );
      expect(
        host.writes.every(
          (p) => p['profile'] == 'personal' && p['session_id'] == 'runtime',
        ),
        isTrue,
      );
      final reopened = await open();
      addTearDown(reopened.dispose);
      final restored = reopened.current!.chat!;
      expect(restored.model, 'gpt-6-astra');
      expect(restored.reasoningEffort, 'high');
      restored.composer.editText('Verify settings');
      await reopened.send(restored);
      expect(host.writes, hasLength(2));
      await reopened.switchProfile('work');
      final other = await reopened.createChat(canDispatch: () => true);
      expect(other.model, 'gpt-6-astra');
      expect(other.reasoningEffort, 'high');
    },
  );

  for (final replacesRuntime in [false, true]) {
    test('a delayed intelligence read cannot overwrite newer hydration '
        '(runtime replaced: $replacesRuntime)', () async {
      final chat = controller.current!.chat!;
      final configStarted = Completer<void>();
      final configDelay = Completer<void>();
      host
        ..configGetStarted = configStarted
        ..configGetDelay = configDelay
        ..resumedRuntimeId = replacesRuntime ? 'replacement-runtime' : null
        ..resumedReasoningEffort = 'low';
      var notifications = 0;
      void countNotifications() => notifications++;

      controller.addListener(countNotifications);
      addTearDown(() => controller.removeListener(countNotifications));
      addTearDown(() {
        if (!configDelay.isCompleted) configDelay.complete();
      });

      final originalRuntime = chat.runtime.runtimeId;
      final pendingLoad = controller.loadIntelligence(chat);
      await configStarted.future;
      if (replacesRuntime) {
        await controller.reconnect(chat.key.workspace);
      } else {
        emitChatEvent(controller, chat, 'session.info', {
          'reasoning_effort': 'low',
        });
      }
      expect(
        chat.runtime.runtimeId,
        replacesRuntime ? 'replacement-runtime' : originalRuntime,
      );
      expect(chat.reasoningEffort, 'low');
      await Future<void>.delayed(Duration.zero);
      final notificationsAfterHydration = notifications;
      configDelay.complete();
      await expectLater(pendingLoad, throwsA(isA<StateError>()));

      expect(chat.reasoningEffort, 'low');
      expect(notifications, notificationsAfterHydration);
    });
  }

  test('a newer intelligence load supersedes an older held load', () async {
    final chat = controller.current!.chat!;
    final configStarted = Completer<void>();
    final configDelay = Completer<void>();
    host
      ..configGetStarted = configStarted
      ..configGetDelay = configDelay
      ..configGetValue = 'medium';
    addTearDown(() {
      if (!configDelay.isCompleted) configDelay.complete();
    });

    final olderLoad = controller.loadIntelligence(chat);
    await configStarted.future;
    final newerLoad = controller.loadIntelligence(chat);
    await Future<void>.delayed(Duration.zero);
    var notifications = 0;
    void countNotifications() => notifications++;

    controller.addListener(countNotifications);
    addTearDown(() => controller.removeListener(countNotifications));
    configDelay.complete();
    await expectLater(olderLoad, throwsA(isA<StateError>()));
    await newerLoad;

    expect(chat.reasoningEffort, 'medium');
    expect(notifications, 1);
  });

  test(
    'declining keeps settings and partial failure preserves confirmed effort',
    () async {
      final chat = controller.current!.chat!;
      host.confirmModel = true;
      await controller.setIntelligence(
        chat,
        selection,
        confirmModelChange: (_) async => false,
      );
      expect(host.writes, hasLength(1));
      expect(chat.model, 'gpt-6-astra');
      expect(chat.changingIntelligence, isFalse);
      host.confirmModel = false;
      host.failReasoning = true;
      await expectLater(
        controller.setIntelligence(
          chat,
          selection,
          confirmModelChange: (_) async => fail('Unexpected confirmation'),
        ),
        throwsStateError,
      );
      expect(chat.model, 'gpt-5.6-sol');
      expect(chat.reasoningEffort, 'high');
      expect(chat.changingIntelligence, isFalse);
    },
  );

  test(
    'model info emitted before its acknowledgement is accepted for the owned route',
    () async {
      final chat = controller.current!.chat!;
      host.onAcceptedWrite = (params) {
        if (params['key'] == 'model') {
          emitChatEvent(controller, chat, 'session.info', {
            'model': selection.choice.model,
            'provider': selection.choice.provider,
          });
        }
      };
      expect(
        await controller.setIntelligence(
          chat,
          selection,
          confirmModelChange: (_) async => true,
        ),
        isTrue,
      );
      expect(chat.model, selection.choice.model);
      expect(chat.reasoningEffort, selection.reasoningEffort);
    },
  );

  test(
    'fast changes are session owned; a failed fast save retries only fast',
    () async {
      final chat = controller.current!.chat!;
      await controller.loadIntelligence(chat);
      final chosen = ChatIntelligenceSelection(
        choice: selection.choice,
        reasoningEffort: selection.reasoningEffort,
        fastMode: ChatFastMode.fast,
      );
      host.failFast = true;
      await expectLater(
        controller.setIntelligence(
          chat,
          chosen,
          confirmModelChange: (_) async => true,
        ),
        throwsStateError,
      );
      expect(chat.model, selection.choice.model);
      expect(chat.reasoningEffort, 'xhigh');
      expect(chat.fastMode, ChatFastMode.normal);
      expect(host.writes.map((w) => w['key']), ['model', 'reasoning', 'fast']);
      host.failFast = false;
      await controller.setIntelligence(
        chat,
        chosen,
        confirmModelChange: (_) async => fail('Unexpected confirmation'),
      );
      expect(host.writes.map((w) => w['key']), [
        'model',
        'reasoning',
        'fast',
        'fast',
      ]);
      expect(host.writes.last['session_id'], 'runtime');
      expect(host.writes.last['profile'], 'personal');
      expect(chat.fastMode, ChatFastMode.fast);
    },
  );
  test('ultrafast survives an unchanged Apply; Off writes normal', () async {
    host.fastMode = 'ultrafast';
    final chat = controller.current!.chat!;
    final options = await controller.loadIntelligence(chat);
    final current = options.choices.first;
    await controller.setIntelligence(
      chat,
      ChatIntelligenceSelection(
        choice: current,
        reasoningEffort: chat.reasoningEffort!,
        fastMode: chat.fastMode!,
      ),
      confirmModelChange: (_) async => true,
    );
    expect(host.writes, isEmpty);
    await controller.setIntelligence(
      chat,
      ChatIntelligenceSelection(
        choice: current,
        reasoningEffort: chat.reasoningEffort!,
        fastMode: ChatFastMode.normal,
      ),
      confirmModelChange: (_) async => true,
    );
    expect(host.writes.single['key'], 'fast');
    expect(host.writes.single['value'], 'normal');
  });

  for (final staleChange in [
    'runtime',
    'model',
    'provider',
    'profile',
    'busy',
  ]) {
    test('confirmation cannot apply after $staleChange changes', () async {
      host.confirmModel = true;
      final chat = controller.current!.chat!;
      await expectLater(
        controller.setIntelligence(
          chat,
          selection,
          confirmModelChange: (_) async {
            switch (staleChange) {
              case 'runtime':
                host.resumedRuntimeId = 'replacement';
                await controller.reconnect(chat.key.workspace);
              case 'model':
                emitChatEvent(controller, chat, 'session.info', {
                  'model': 'gpt-5.4-mini',
                });
              case 'provider':
                emitChatEvent(controller, chat, 'session.info', {
                  'provider': 'other-provider',
                });
              case 'profile':
                await controller.switchProfile('work');
              case 'busy':
                emitChatEvent(controller, chat, 'message.start');
            }
            return true;
          },
        ),
        throwsStateError,
      );
      expect(host.writes, hasLength(1));
      expect(chat.reasoningEffort, 'high');
      expect(chat.changingIntelligence, isFalse);
    });
  }

  for (final repeatedGuard in [false, true]) {
    test(
      'confirmed failure does not retry (repeated guard: $repeatedGuard)',
      () async {
        host
          ..confirmModel = true
          ..repeatConfirmation = repeatedGuard
          ..failConfirmedModel = !repeatedGuard;
        final chat = controller.current!.chat!;
        var confirmations = 0;
        await expectLater(
          controller.setIntelligence(
            chat,
            selection,
            confirmModelChange: (message) async {
              expect(message, ProfileIntelligenceFixture.modelWarning);
              confirmations++;
              return true;
            },
          ),
          throwsStateError,
        );
        expect(confirmations, 1);
        expect(host.writes, hasLength(2));
        expect(chat.model, 'gpt-6-astra');
        expect(chat.reasoningEffort, 'high');
        expect(chat.changingIntelligence, isFalse);
      },
    );
  }

  test('pending confirmation blocks duplicate switches and sending', () async {
    host.confirmModel = true;
    final chat = controller.current!.chat!;
    final decision = Completer<bool>();
    final requested = Completer<void>();
    final applying = controller.setIntelligence(
      chat,
      selection,
      confirmModelChange: (_) {
        requested.complete();
        return decision.future;
      },
    );
    await requested.future;
    expect(chat.changingIntelligence, isTrue);
    await expectLater(
      controller.setIntelligence(
        chat,
        selection,
        confirmModelChange: (_) async => fail('Duplicate confirmation'),
      ),
      throwsStateError,
    );
    chat.composer.editText('Keep this draft');
    await controller.send(chat);
    expect(chat.composer.observation.text, 'Keep this draft');
    expect(host.writes, hasLength(1));
    decision.complete(false);
    await applying;
    expect(chat.changingIntelligence, isFalse);
  });

  testWidgets(
    'large-context model switch offers a confirmation before applying',
    (tester) async {
      host.confirmModel = true;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-intelligence-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('model-search')), 'sol');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-openai-codex-gpt-5.6-sol')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Confirm model change'), findsOneWidget);
      expect(
        find.text(ProfileIntelligenceFixture.modelWarning),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
        findsOneWidget,
      );
      expect(find.text('Switch model'), findsOneWidget);
      expect(host.writes, hasLength(1));
      expect(controller.current!.chat!.model, 'gpt-6-astra');
      await tester.tap(find.text('Switch model'));
      await tester.pumpAndSettle();
      expect(host.writes, hasLength(3));
      expect(host.writes[1], {
        ...host.writes[0],
        'confirm_expensive_model': true,
      });
      expect(host.writes.last['key'], 'reasoning');
      expect(controller.current!.chat!.model, 'gpt-5.6-sol');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('partial Chat save keeps the draft and retries reasoning alone', (
    tester,
  ) async {
    host.failReasoning = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-intelligence-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('model-search')), 'sol');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-openai-codex-gpt-5.6-sol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('model changed, but reasoning'), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
    expect(host.writes, hasLength(2));
    host.failReasoning = false;
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(host.writes, hasLength(3));
    expect(host.writes.last['key'], 'reasoning');
    expect(controller.current!.chat!.model, 'gpt-5.6-sol');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the shipped profile composer opens picker and applies both choices',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-intelligence-button')));
      await tester.pumpAndSettle();
      expect(find.text('Models'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('model-search')), 'sol');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-openai-codex-gpt-5.6-sol')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-reasoning-control')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reasoning-xhigh')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('5.6 Sol'), findsOneWidget);
      expect(controller.current!.chat!.reasoningEffort, 'xhigh');
      expect(host.writes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('model picker refreshes the current profile and reveals Codex', (
    tester,
  ) async {
    host.codexAppearsOnRefresh = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-intelligence-button')));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI subscription'), findsNothing);

    await tester.tap(find.byKey(const Key('refresh-chat-models')));
    await tester.pumpAndSettle();

    expect(
      host.modelOptionReads.every((q) => q['profile'] == 'personal'),
      isTrue,
    );
    expect(host.modelOptionReads.last, {'profile': 'personal', 'refresh': '1'});
    expect(find.text('OpenAI subscription'), findsWidgets);
    expect(
      find.byKey(const Key('review-model-provider-access')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('model-openai-codex-gpt-5.6-sol')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reopening uses the chat route rather than the profile default or first provider',
    (tester) async {
      host.mixedCatalog = true;
      final chat = controller.current!.chat!;
      emitChatEvent(controller, chat, 'session.info', {
        'model': 'gpt-6.1-sol',
        'provider': 'openai-codex',
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: ProfileWorkspaceScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      for (var opening = 0; opening < 2; opening++) {
        await tester.tap(find.byKey(const Key('chat-intelligence-button')));
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();
        final tab = find.byKey(const Key('model-filter-openai-codex'));
        final row = find.byKey(const Key('model-openai-codex-gpt-6.1-sol'));
        expect(tab.hitTestable(), findsOneWidget);
        expect(row.hitTestable(), findsOneWidget);
        expect(tester.getSemantics(tab), isSemantics(isSelected: true));
        expect(tester.getSemantics(row), isSemantics(isSelected: true));
        semantics.dispose();
        expect(
          find.byKey(const Key('model-openrouter-gpt-6.1-sol')),
          findsNothing,
        );
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(chat.model, 'gpt-6.1-sol');
        expect(chat.provider, 'openai-codex');
        expect(host.writes, isEmpty);
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 640), 2.0),
    ]) {
      testWidgets('composer controls fit $brightness $size at text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const frame = Key('composer-preview');
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: ProfileWorkspaceScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'chat-intelligence-button',
          'chat-reasoning-control',
          'chat-fast-control',
        ]) {
          expect(find.byKey(Key(key)).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(frame))
                .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/model-composer-${brightness.name}-${size.width.toInt()}-${scale == 2 ? 'large' : 'normal'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(const Key('chat-fast-control')));
        await tester.pumpAndSettle();
        expect(host.writes.single['key'], 'fast');
        expect(host.writes.single['value'], 'fast');
      });
    }
  }
}
