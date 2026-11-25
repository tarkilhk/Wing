import 'support/wing_client_identity_fixture.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/context_ring.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;
import 'support/profile_intelligence_fixture.dart';
import 'support/composer_fixture.dart' show emitChatEvent;
import 'package:wing/core/models/chat_intelligence.dart';
import 'package:wing/core/models/model_choice.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_ACTIVE_CONTEXT');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'Ahem': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });
  late Host host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  Completer<Map<String, dynamic>>? pending;
  late Map<String, dynamic> breakdownResponse;
  const snapshot = {
    'context_used': 250,
    'context_max': 1000,
    'context_percent': 25,
  };
  const cacheReport = {
    'guaranteed_until': 1795566600,
    'estimated_until': 1795569900,
    'refreshed_at': 1795566300,
    'tier': '5m',
    'confidence': 'assumed',
    'coverage': {'5m': 1795566600, '1h': 1795569900},
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = Host();
    pending = null;
    breakdownResponse = snapshot;
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'context-test',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: (scope) {
        final base = host.gateway(scope);
        late final ProfileGateway gateway;
        gateway = ProfileGateway(
          loadClientIdentity: loadTestWingClientIdentity,
          scope: scope,
          discover: base.discover,
          connect: () async {
            if (gateway.onEvent != null) {
              host.gateways[scope.profileName] = gateway;
            }
            await base.connect();
          },
          get: base.read,
          rpc: (method, params) {
            if (method == 'session.context_breakdown') {
              host.calls.add((scope.profileName, method, params));
              return pending?.future ?? Future.value(breakdownResponse);
            }
            return base.call(method, params);
          },
        );
        return gateway;
      },
    );
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  test(
    'cache publishes independently of unknown occupancy and newer invalid usage',
    () async {
      final chat = await controller.createChat(canDispatch: () => true);
      breakdownResponse = {'context_max': 0, 'prompt_cache': cacheReport};
      await controller.refreshContext(chat);
      expect(chat.context, isNull);
      expect(chat.promptCache!.tier, '5m');
      pending = Completer();
      final read = controller.refreshContext(chat);
      host.event('a', 'session.usage', {
        'usage': {'context_max': 0},
      });
      pending!.complete({
        ...snapshot,
        'prompt_cache': {...cacheReport, 'tier': '1h'},
      });
      await read;
      expect(chat.context, isNull);
      expect(chat.promptCache!.tier, '1h');
    },
  );

  test(
    'cache failure retains report, absent success clears it, usage never revives it',
    () async {
      final chat = await controller.createChat(canDispatch: () => true);
      breakdownResponse = {...snapshot, 'prompt_cache': cacheReport};
      await controller.refreshContext(chat);
      final report = chat.promptCache;
      pending = Completer();
      final failed = controller.refreshContext(chat);
      pending!.completeError(StateError('unavailable'));
      await failed;
      expect(chat.promptCache, same(report));
      expect(chat.contextError, isNotNull);
      pending = null;
      for (final response in [
        snapshot,
        {...snapshot, 'prompt_cache': null},
      ]) {
        breakdownResponse = {...snapshot, 'prompt_cache': cacheReport};
        await controller.refreshContext(chat);
        breakdownResponse = response;
        await controller.refreshContext(chat);
        expect(chat.promptCache, isNull);
        expect(chat.contextError, isNull);
        host.event('a', 'session.usage', {
          'usage': {'context_used': 300, 'prompt_cache': cacheReport},
        });
        expect(chat.promptCache, isNull);
      }
    },
  );

  for (final change in ['compression', 'model', 'provider', 'session.info']) {
    test(
      'cache retires before $change replacement and rejects old completion',
      () async {
        final chat = await controller.createChat(canDispatch: () => true);
        breakdownResponse = {...snapshot, 'prompt_cache': cacheReport};
        await controller.refreshContext(chat);
        host.event('a', 'session.usage', {
          'usage': {'compressions': 0},
        });
        final old = Completer<Map<String, dynamic>>();
        pending = old;
        final oldRead = controller.refreshContext(chat);
        final replacement = Completer<Map<String, dynamic>>();
        pending = replacement;
        if (change == 'compression') {
          host.event('a', 'session.usage', {
            'usage': {'compressions': 1},
          });
        } else if (change == 'session.info') {
          host.event('a', 'session.info', {'model': 'replacement-model'});
        } else {
          host.event('a', 'session.updated', {change: 'replacement-$change'});
        }
        expect(chat.promptCache, isNull);
        host.event('a', 'session.usage', {
          'usage': {
            'context_used': 900,
            'context_max': 1000,
            'context_percent': 90,
          },
        });
        old.complete({...snapshot, 'prompt_cache': cacheReport});
        await oldRead;
        expect(chat.promptCache, isNull);
        expect(chat.context!.used, 900);
        replacement.complete({
          ...snapshot,
          'prompt_cache': {...cacheReport, 'tier': '1h'},
        });
        await Future<void>.delayed(Duration.zero);
        expect(chat.promptCache!.tier, '1h');
        expect(chat.context!.used, 900);
      },
    );
  }

  test(
    'same session identifier in another profile has its own cache report',
    () async {
      host.running = false;
      breakdownResponse = {...snapshot, 'prompt_cache': cacheReport};
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'same'),
      );
      final first = controller.current!.chat!;
      await controller.refreshContext(first);
      final old = Completer<Map<String, dynamic>>();
      pending = old;
      final oldRead = controller.refreshContext(first);
      pending = null;
      breakdownResponse = {
        ...snapshot,
        'prompt_cache': {...cacheReport, 'tier': '1h'},
      };
      await controller.switchProfile('b');
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'same'),
      );
      final second = controller.current!.chat!;
      await controller.refreshContext(second);
      old.complete({...snapshot, 'prompt_cache': cacheReport});
      await oldRead;
      expect(second.promptCache!.tier, '1h');
      expect(first.promptCache!.tier, '5m');
    },
  );

  Future<(ProfileWorkspaceController, ProfileIntelligenceFixture)>
  intelligence() async {
    final fixture = ProfileIntelligenceFixture();
    final owner = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'cache-intelligence',
      preferences: await SharedPreferences.getInstance(),
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    addTearDown(owner.dispose);
    await owner.initialize();
    final chat = await owner.createChat(canDispatch: () => true);
    await owner.loadIntelligence(chat);
    fixture.contextResponse = Completer()
      ..complete({...snapshot, 'prompt_cache': cacheReport});
    await owner.refreshContext(chat);
    return (owner, fixture);
  }

  test(
    'confirmed model retires cache and account visit before a held failing Fast write',
    () async {
      final (owner, fixture) = await intelligence();
      final chat = owner.current!.chat!;
      final visit = owner.openAccountUsage(chat);
      final old = Completer<Map<String, dynamic>>();
      fixture.contextResponse = old;
      final oldRead = owner.refreshContext(chat);
      final replacement = Completer<Map<String, dynamic>>();
      fixture.contextResponse = replacement;
      final fastGate = Completer<void>();
      fixture.onAcceptedWrite = (params) {
        if (params['operation'] == 'model') fixture.configSetDelay = fastGate;
      };
      fixture.failFast = true;
      final write = owner.setIntelligence(
        chat,
        const ChatIntelligenceSelection(
          choice: ModelChoice(provider: 'openai-codex', model: 'gpt-5.6-sol'),
          reasoningEffort: 'high',
          fastMode: ChatFastMode.fast,
        ),
        confirmModelChange: (_) async => true,
      );
      final failure = expectLater(write, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(chat.model, 'gpt-5.6-sol');
      expect(chat.promptCache, isNull);
      expect(visit.retired, isTrue);
      fastGate.complete();
      await failure;
      old.complete({...snapshot, 'prompt_cache': cacheReport});
      await oldRead;
      expect(chat.promptCache, isNull);
      replacement.complete(snapshot);
      await Future<void>.delayed(Duration.zero);
      visit.dispose();
    },
  );

  test(
    'deferred model and reasoning or Fast-only changes preserve cache',
    () async {
      final (owner, fixture) = await intelligence();
      final chat = owner.current!.chat!;
      final report = chat.promptCache;
      for (final setting in [
        ChatIntelligenceSelection(
          choice: ModelChoice(provider: chat.provider!, model: chat.model!),
          reasoningEffort: 'low',
          fastMode: ChatFastMode.normal,
        ),
        ChatIntelligenceSelection(
          choice: ModelChoice(provider: chat.provider!, model: chat.model!),
          reasoningEffort: 'low',
          fastMode: ChatFastMode.fast,
        ),
      ]) {
        await owner.setIntelligence(
          chat,
          setting,
          confirmModelChange: (_) async => true,
        );
        expect(chat.promptCache, same(report));
      }
      fixture.deferMutation = true;
      await owner.setIntelligence(
        chat,
        const ChatIntelligenceSelection(
          choice: ModelChoice(provider: 'openai-codex', model: 'gpt-5.6-sol'),
          reasoningEffort: 'low',
          fastMode: ChatFastMode.fast,
        ),
        confirmModelChange: (_) async => true,
      );
      expect(chat.promptCache, same(report));
      expect(chat.model, 'gpt-6-astra');
      fixture.contextResponse = Completer();
      emitChatEvent(owner, chat, 'session.updated', {'model': 'gpt-5.6-sol'});
      expect(chat.promptCache, isNull);
      fixture.contextResponse!.complete(snapshot);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'runtime replacement retires cache and rejects a held former runtime read',
    () async {
      final (owner, fixture) = await intelligence();
      final chat = owner.current!.chat!;
      final old = Completer<Map<String, dynamic>>();
      fixture.contextResponse = old;
      final oldRead = owner.refreshContext(chat);
      fixture.contextResponse = Completer()..complete(snapshot);
      fixture.resumedRuntimeId = 'replacement-runtime';
      await owner.reconnect(chat.key.workspace);
      expect(chat.runtime.runtimeId, 'replacement-runtime');
      old.complete({...snapshot, 'prompt_cache': cacheReport});
      await oldRead;
      expect(chat.promptCache, isNull);
      expect(chat.contextError, isNull);
    },
  );

  test(
    'usage belongs to the original chat and partial events retain server limits',
    () async {
      final a = await controller.createChat(canDispatch: () => true);
      await controller.refreshContext(a);
      expect(a.context!.percent, 25);
      expect(host.calls.last.$3, {'session_id': 'a-runtime', 'profile': 'a'});
      await controller.switchProfile('b');
      final b = await controller.createChat(canDispatch: () => true);
      await controller.refreshContext(b);
      host.event('a', 'session.usage', {
        'usage': {'context_used': 750, 'context_percent': 75},
      });
      expect(a.context!.percent, 75);
      expect(a.context!.max, 1000);
      expect(b.context!.percent, 25);
    },
  );

  test('late breakdown cannot overwrite a newer live usage event', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    await controller.refreshContext(chat);
    pending = Completer();
    final refresh = controller.refreshContext(chat);
    host.event('a', 'session.usage', {
      'usage': {'context_used': 900, 'context_percent': 90},
    });
    pending!.complete(snapshot);
    await refresh;
    expect(chat.context!.percent, 90);
    host.event('a', 'session.usage', {
      'usage': {'context_max': 0},
    });
    expect(chat.context, isNull);
  });

  test(
    'refetches context when a resumed session becomes ready without a prompt',
    () async {
      // A cold resume can answer context_breakdown before the lazy agent exists.
      // Hermes returns an explicit zero/unknown breakdown in that phase, then
      // emits session.info after agent construction. The ready response has no
      // context_* fields until the next breakdown RPC.
      breakdownResponse = {
        'context_used': 0,
        'context_max': 0,
        'context_percent': 0,
        'context_estimated': false,
      };
      host.running = false;
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'same'),
      );
      final restored = controller.current!.chat!;
      await Future<void>.delayed(Duration.zero);
      expect(restored.context, isNull);
      expect(
        host.calls.where((call) => call.$2 == 'session.context_breakdown'),
        hasLength(1),
      );

      breakdownResponse = {
        'context_used': 1200,
        'context_max': 4000,
        'context_percent': 30,
        'context_estimated': true,
      };
      host.event('a', 'session.info', {
        'usage': {'calls': 0, 'input': 0, 'output': 0, 'total': 0},
      });
      await Future<void>.delayed(Duration.zero);

      expect(restored.context?.percent, 30);
      expect(restored.context?.estimated, isTrue);
      expect(restored.reading.messages, isNotEmpty);
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      expect(
        host.calls.where((call) => call.$2 == 'session.context_breakdown'),
        hasLength(2),
      );
    },
  );

  test(
    'late pre-ready breakdown cannot erase the ready session usage',
    () async {
      host.running = false;
      final beforeReady = Completer<Map<String, dynamic>>();
      pending = beforeReady;
      await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'same'),
      );
      final chat = controller.current!.chat!;
      pending = null;
      host.event('a', 'session.info', {
        'usage': {'calls': 0, 'input': 0, 'output': 0},
      });
      await Future<void>.delayed(Duration.zero);
      expect(chat.context?.percent, 25);
      beforeReady.complete({
        'context_used': 0,
        'context_max': 0,
        'context_percent': 0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(chat.context?.percent, 25);
    },
  );
  test('composition is chat-owned and survives live usage updates', () async {
    breakdownResponse = {
      ...snapshot,
      'categories': [
        {'id': 'conversation', 'label': 'Conversation', 'tokens': 200},
      ],
    };
    final a = await controller.createChat(canDispatch: () => true);
    await controller.refreshContext(a);
    await controller.switchProfile('b');
    final b = await controller.createChat(canDispatch: () => true);
    await controller.refreshContext(b);
    host.event('a', 'session.usage', {
      'usage': {'context_used': 750, 'context_percent': 75, 'compressions': 2},
    });
    expect(a.context!.used, 750);
    expect(a.context!.categories.single.tokens, 200);
    expect(a.contextCompressions, 2);
    expect(b.context!.categories.single.tokens, 200);
    expect(b.contextCompressions, isNull);
  });

  test('a new turn retains composition and a pending breakdown', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    await controller.refreshContext(chat);
    pending = Completer();
    final refresh = controller.refreshContext(chat);
    expect(chat.contextLoading, isTrue);
    host.event('a', 'message.start', {});
    expect(chat.contextLoading, isTrue);
    pending!.complete({
      ...snapshot,
      'categories': [
        {'id': 'conversation', 'label': 'Conversation', 'tokens': 200},
      ],
    });
    await refresh;
    expect(chat.context!.categories.single.tokens, 200);
    expect(chat.contextLoading, isFalse);
  });

  test('active turns admit breakdown reads and retry after failure', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    host.event('a', 'message.start', {});
    expect(chat.runtime.blocksTurnAdmission, isTrue);
    pending = Completer();
    final refresh = controller.refreshContext(chat);
    expect(chat.contextLoading, isTrue);
    pending!.completeError(StateError('fixture failure'));
    await refresh;
    expect(chat.contextError, isNotNull);
    pending = null;
    breakdownResponse = {
      ...snapshot,
      'categories': [
        {'id': 'conversation', 'label': 'Conversation', 'tokens': 200},
      ],
    };
    await controller.refreshContext(chat);
    expect(chat.contextError, isNull);
    expect(chat.context!.categories.single.tokens, 200);
    expect(chat.runtime.blocksTurnAdmission, isTrue);
  });

  test(
    'live totals do not cancel a held breakdown or erase its categories',
    () async {
      final chat = await controller.createChat(canDispatch: () => true);
      await controller.refreshContext(chat);
      host.event('a', 'message.start', {});
      pending = Completer();
      final refresh = controller.refreshContext(chat);
      host.event('a', 'session.usage', {
        'usage': {'context_used': 900, 'context_percent': 90},
      });
      expect(chat.contextLoading, isTrue);
      pending!.complete({
        ...snapshot,
        'categories': [
          {'id': 'conversation', 'label': 'Conversation', 'tokens': 200},
        ],
      });
      await refresh;
      expect(chat.context!.used, 900);
      expect(chat.context!.percent, 90);
      expect(chat.context!.categories.single.tokens, 200);
      host.event('a', 'session.usage', {
        'usage': {'context_used': 950, 'context_percent': 95},
      });
      expect(chat.context!.categories.single.tokens, 200);
      expect(chat.context!.percent, 95);
    },
  );

  test('compression-only usage refetches composition during a turn', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    host.event('a', 'message.start', {});
    host.event('a', 'session.usage', {
      'usage': {'compressions': 0},
    });
    breakdownResponse = {
      ...snapshot,
      'categories': [
        {'id': 'conversation', 'label': 'Conversation', 'tokens': 200},
      ],
    };
    await controller.refreshContext(chat);
    final before = host.calls
        .where((call) => call.$2 == 'session.context_breakdown')
        .length;
    breakdownResponse = {
      ...snapshot,
      'categories': [
        {'id': 'conversation', 'label': 'Conversation', 'tokens': 40},
      ],
    };
    host.event('a', 'session.usage', {
      'usage': {'compressions': 1},
    });
    expect(chat.context!.categories, isEmpty);
    expect(chat.contextLoading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(chat.context!.categories.single.tokens, 40);
    expect(chat.contextCompressions, 1);
    expect(chat.runtime.blocksTurnAdmission, isTrue);
    expect(
      host.calls.where((call) => call.$2 == 'session.context_breakdown'),
      hasLength(before + 1),
    );
  });

  test('failed composition read has an explicit retry state', () async {
    final chat = await controller.createChat(canDispatch: () => true);
    pending = Completer();
    final refresh = controller.refreshContext(chat);
    expect(chat.contextLoading, isTrue);
    pending!.completeError(StateError('fixture failure'));
    await refresh;
    expect(chat.contextLoading, isFalse);
    expect(chat.context, isNull);
    expect(chat.contextError, 'Couldn’t load the context breakdown.');
    pending = null;
    await controller.refreshContext(chat);
    expect(chat.contextError, isNull);
    expect(chat.context!.used, 250);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('working chat opens, retries and retains context '
          '${brightness.name} at $scale text', (tester) async {
        final size = Size(scale == 1 ? 390 : 320, 844);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        breakdownResponse = {
          ...snapshot,
          'prompt_cache': {
            ...cacheReport,
            'warming_off': true,
            'tier_pending': true,
            'learned': 'short-lived',
          },
          'categories': [
            {'id': 'system_prompt', 'label': 'System prompt', 'tokens': 50},
            {'id': 'conversation', 'label': 'Conversation', 'tokens': 200},
          ],
        };
        final chat = await controller.createChat(canDispatch: () => true);
        await controller.refreshContext(chat);
        host.event('a', 'message.start', {});
        const frame = ValueKey('active-context-frame');
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: scale == 2,
                ),
                child: child!,
              ),
              home: ProfileWorkspaceScreen(
                createBotsSession: () => BotsSession((_) async => const []),
                controller: controller,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        Future<void> screenshot(String state) async {
          if (!capture) return;
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(frame))
                .toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory(
                'build/design-previews/active-context/site',
              );
              await dir.create(recursive: true);
              await File(
                '${dir.path}/${brightness.name}-$scale-$state.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }

        final ring = find.byKey(const ValueKey('context-ring-details'));
        final ringRect = tester.getRect(find.byType(ContextRing));
        pending = Completer();
        await tester.tap(ring);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final panel = find.byKey(const ValueKey('context-usage-popover'));
        final progress = find.descendant(
          of: panel,
          matching: find.byType(CircularProgressIndicator),
        );
        expect(chat.runtime.blocksTurnAdmission, isTrue);
        expect(chat.contextRefreshPending, isTrue);
        expect(find.text('Conversation'), findsOneWidget);
        expect(
          find.text('No composition breakdown available yet.'),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel('Loading context breakdown'),
          findsOneWidget,
        );
        expect(progress, scale == 1 ? findsOneWidget : findsNothing);
        host.event('a', 'session.usage', {
          'usage': {'context_used': 900, 'context_percent': 90},
        });
        await tester.pump();
        expect(find.text('90% full'), findsOneWidget);
        expect(chat.contextRefreshPending, isTrue);
        await tester.enterText(
          find.byType(TextField).first,
          'Draft stays editable',
        );
        await tester.pump();
        expect(chat.composer.observation.text, 'Draft stays editable');
        expect(tester.getRect(find.byType(ContextRing)), ringRect);
        await screenshot('pending');
        pending!.completeError(StateError('fixture failure'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(chat.contextRefreshPending, isFalse);
        expect(find.text('Conversation'), findsOneWidget);
        expect(
          find.text('Couldn’t load the context breakdown.'),
          findsOneWidget,
        );
        await screenshot('failed');
        pending = Completer();
        await tester.ensureVisible(find.byTooltip('Retry'));
        await tester.pump();
        await tester.tap(find.byTooltip('Retry'));
        await tester.pump();
        expect(chat.contextRefreshPending, isTrue);
        expect(
          find.text('Couldn’t load the context breakdown.'),
          findsOneWidget,
        );
        expect(
          find.byType(CircularProgressIndicator).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == 'Retry',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.bySemanticsLabel('Loading context breakdown'),
          findsNothing,
        );
        await screenshot('retry');
        pending!.completeError(StateError('retry still unavailable'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(chat.contextRefreshPending, isFalse);
        expect(chat.promptCache, isNotNull);
        expect(
          find.text('Couldn’t load the context breakdown.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == 'Retry',
                ),
              )
              .onPressed,
          isNotNull,
        );
        pending = Completer();
        await tester.tap(find.byTooltip('Retry'));
        await tester.pump();
        expect(
          find.byType(CircularProgressIndicator).hitTestable(),
          findsOneWidget,
        );
        pending!.complete({
          ...breakdownResponse,
          'context_used': 950,
          'context_percent': 95,
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(chat.contextRefreshPending, isFalse);
        expect(find.text('95% full'), findsOneWidget);
        expect(find.text('Conversation'), findsOneWidget);
        expect(find.text('Couldn’t load the context breakdown.'), findsNothing);
        expect(chat.runtime.blocksTurnAdmission, isTrue);
        await screenshot('complete');
        await tester.ensureVisible(find.text('Prompt cache'));
        await tester.pump();
        expect(find.text('Assumed'), findsOneWidget);
        expect(find.text('Retention upper bound'), findsOneWidget);
        await screenshot('cache-report');
        await tester.ensureVisible(
          find.text('Cache retention is shorter than expected.'),
        );
        await tester.pump();
        await screenshot('cache-lifecycle');
        await tester.ensureVisible(find.byTooltip('Close context window'));
        await tester.pump();

        // An automatic read remains quiet over available content.
        pending = Completer();
        final background = controller.refreshContext(chat);
        await tester.pump();
        expect(chat.contextLoading, isTrue);
        expect(chat.contextRefreshPending, isFalse);
        expect(
          find.bySemanticsLabel('Loading context breakdown'),
          findsNothing,
        );
        expect(find.text('Conversation'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Close context window'));
        await tester.pump();
        await tester.tap(find.byTooltip('Close context window'));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpWidget(const SizedBox.shrink());
        pending!.complete(breakdownResponse);
        await background;
        await tester.pump();
        expect(panel, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
