import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/composer_reference.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/widgets/bot_avatar.dart';
import 'package:wing/core/widgets/mention_suggestions.dart';
import 'support/bots_fixture.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'composer_references_test.dart' show ReferenceHost;
import 'profile_workspace_controller_test.dart' show Host;

class _ReferenceWorkspaceHost extends Host {
  final references = ReferenceHost();
  String? terminal = 'local';

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    late final ProfileGateway gateway;
    gateway = ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: () async {
        if (gateway.onEvent != null) gateways[scope.profileName] = gateway;
        await base.connect();
      },
      close: base.close,
      get: (path, query) => path == 'profiles' || path.startsWith('files')
          ? references.read(path, query)
          : base.read(path, query),
      rpc: (method, params) async {
        final result = await base.call(method, params);
        if (method == 'session.create' || method == 'session.resume') {
          return {
            ...result,
            'info': {
              ...result['info'] as Map,
              'cwd': '/work',
              if (terminal != null) 'terminal_backend': terminal,
            },
          };
        }
        if (method == 'session.context_breakdown') {
          return {
            'context_used': 0,
            'context_max': 32768,
            'context_percent': 0,
          };
        }
        if (method == 'session.history') {
          return {'messages': historyMessages ?? <Map<String, dynamic>>[]};
        }
        if (method == 'commands.catalog') {
          return {
            'pairs': [
              ['/bg', 'Background task'],
              ['/btw', 'Side question'],
            ],
          };
        }
        if (method == 'prompt.background' || method == 'prompt.btw') {
          return {'task_id': 'task-1', 'status': 'started'};
        }
        return result;
      },
    );
    return gateway;
  }
}

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['CAPTURE_REFERENCE_FONTS'];
    if (fonts == null) return;
    for (final font in {
      'Roboto': '$fonts/Roboto-Regular.ttf',
      'MaterialIcons': '$fonts/MaterialIcons-Regular.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      final loader = FontLoader(font.key)
        ..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  late _ReferenceWorkspaceHost host;
  late ProfileWorkspaceController controller;
  late AppPreferences preferences;
  late ProfileChat chat;
  late BotsSession bots;
  late BotsFixture botFixture;
  late BotsRepository botRepository;
  const ref = ComposerReference(
    kind: ComposerReferenceKind.file,
    token: '@file:/work/note.md',
    target: '/work/note.md',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    preferences = AppPreferences(prefs);
    host = _ReferenceWorkspaceHost()..running = false;
    controller = ProfileWorkspaceController(
      connectionIdentity: 'references',
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Host',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      preferences: prefs,
      appPreferences: preferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
    botFixture = BotsFixture();
    botFixture.profiles
      ..clear()
      ..addAll([
        BotsFixture.profile('hermes', 'Saved Hermes'),
        BotsFixture.profile('butler', 'Saved Butler'),
      ]);
    botFixture.profiles[1]['ui_meta']['hermes-bots']['shape'] = 'hexagon';
    botFixture.profiles[1]['ui_meta']['hermes-bots']['color'] = '#8b5cf6';
    botRepository = BotsRepository(
      scope: WorkspaceScope(
        connectionId: chat.key.workspace.connectionId,
        connectionIdentity: chat.key.workspace.connectionIdentity,
        profileName: 'default',
      ),
      instance: 'Host',
      read: botFixture.read,
      command: botFixture.command,
      ownership: botFixture.ownership,
      savedHistory: botFixture.savedHistory,
    );
    bots = BotsSession((_) async => [botRepository]);
  });
  tearDown(() {
    bots.dispose();
    controller.dispose();
    preferences.dispose();
  });

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(ready(), isTrue);
  }

  Map<String, dynamic> lastCall(String method) =>
      host.calls.lastWhere((c) => c.$2 == method).$3;

  const photo =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK7sAAAAASUVORK5CYII=';

  test(
    'ordinary references borrow canonical saved photos and reuse warm reads',
    () async {
      botFixture.profiles.first['has_avatar'] = true;
      var rosters = 0, assets = 0;
      botFixture.readHook = (profile, method, params) async {
        if (method == 'profiles.list') rosters++;
        if (method == 'profiles.get_asset') {
          expect(profile, 'hermes');
          expect(params['name'], 'hermes');
          assets++;
          return {'found': true, 'data': photo};
        }
        return null;
      };
      final query = MentionQuery.at('@herm', 5)!;
      for (var i = 0; i < 2; i++) {
        final completion = await controller.completeMention(
          chat,
          query,
          bots: bots,
          canRead: () => true,
        );
        final candidate = completion.items.single;
        expect(candidate.label, 'HERMES');
        expect(candidate.reference.token, '@hermes');
        expect(candidate.reference.target, 'hermes');
        expect(candidate.appearance!.title, 'Saved Hermes');
        expect(candidate.appearance!.avatar, base64Decode(photo));
        expect(
          candidate.appearance!.scope.connectionIdentity,
          chat.key.workspace.connectionIdentity,
        );
      }
      expect(rosters, 1);
      expect(assets, 1);
      expect(botFixture.commands, isEmpty);
    },
  );

  test(
    'retiring a reference query stops avatar admission and a fresh query recovers',
    () async {
      botFixture.profiles.first['has_avatar'] = true;
      final roster = Completer<Map<String, dynamic>?>();
      final started = Completer<void>();
      var allowed = true, assets = 0;
      botFixture.readHook = (_, method, _) async {
        if (method == 'profiles.list') {
          if (!started.isCompleted) started.complete();
          return roster.future;
        }
        if (method == 'profiles.get_asset') {
          assets++;
          return {'found': true, 'data': photo};
        }
        return null;
      };
      final query = MentionQuery.at('@herm', 5)!;
      final pending = controller.completeMention(
        chat,
        query,
        bots: bots,
        canRead: () => allowed,
      );
      final retired = expectLater(pending, throwsStateError);
      await started.future;
      allowed = false;
      roster.complete(null);
      await retired;
      expect(assets, 0);
      allowed = true;
      final fresh = await controller.completeMention(
        chat,
        query,
        bots: bots,
        canRead: () => allowed,
      );
      expect(fresh.items.single.appearance!.avatar, base64Decode(photo));
      expect(assets, 1);
    },
  );

  test(
    'appearance failure preserves discovery and explicit refresh recovers',
    () async {
      var unavailable = true;
      botFixture.readHook = (_, method, _) async {
        if (unavailable && method == 'profiles.list') {
          throw StateError('Unavailable appearance roster');
        }
        return null;
      };
      final query = MentionQuery.at('@', 1)!;
      final completion = await controller.completeMention(
        chat,
        query,
        bots: bots,
        canRead: () => true,
      );
      expect(
        completion.items
            .where((i) => i.reference.kind == ComposerReferenceKind.agent)
            .length,
        2,
      );
      expect(
        completion.items
            .where((i) => i.reference.kind == ComposerReferenceKind.file)
            .length,
        1,
      );
      expect(completion.items.every((i) => i.appearance == null), isTrue);
      unavailable = false;
      bots.invalidateAppearances();
      final recovered = await controller.completeMention(
        chat,
        query,
        bots: bots,
        canRead: () => true,
      );
      expect(
        recovered.items
            .where((i) => i.reference.kind == ComposerReferenceKind.agent)
            .every((i) => i.appearance != null),
        isTrue,
      );
      expect(
        recovered.items
            .where((i) => i.reference.kind == ComposerReferenceKind.file)
            .single
            .appearance,
        isNull,
      );
    },
  );

  test(
    'queued context reads at dispatch and unavailable context pauses the complete message',
    () async {
      host.event('a', 'message.start');
      await controller.updateDraft(chat, 'Read ${ref.token}', reference: ref);
      await controller.queuePrompt(chat, chat.composer.observation.text);
      expect(
        host.references.reads.where((r) => r.startsWith('files/read')),
        isEmpty,
      );
      host.references.files[ref.target] = 'changed at dispatch';
      host.event('a', 'turn.end', {'status': 'completed'});
      await until(
        () =>
            host.calls.any((c) => c.$2 == 'prompt.submit') &&
            !chat.composer.observation.draining,
      );
      final prepared = PreparedComposerMessage.parse(
        lastCall('prompt.submit')['text'],
      )!;
      expect(prepared.context, contains('changed at dispatch'));
      expect(prepared.references.single.target, ref.target);
      expect(
        host.references.reads.where((r) => r.startsWith('files/read')),
        hasLength(1),
      );
      await controller.updateDraft(
        chat,
        'Read ${ref.token} again',
        reference: ref,
      );
      await controller.queuePrompt(chat, chat.composer.observation.text);
      host.references.files.clear();
      host.event('a', 'turn.end', {'status': 'completed'});
      await until(
        () =>
            chat.composer.observation.paused &&
            !chat.composer.observation.draining,
      );
      expect(host.calls.where((c) => c.$2 == 'prompt.submit'), hasLength(1));
      expect(
        chat.composer.observation.queue.single.references.single.target,
        ref.target,
      );
      expect(
        chat.composer.observation.queue.single.text,
        'Read ${ref.token} again',
      );
    },
  );

  for (final command in {
    'bg': 'prompt.background',
    'btw': 'prompt.btw',
  }.entries) {
    test(
      '${command.key} prepares context while retaining authored task text',
      () async {
        await controller.updateDraft(
          chat,
          '/${command.key} Read ${ref.token}',
          reference: ref,
        );
        await controller.send(chat);
        final prepared = PreparedComposerMessage.parse(
          lastCall(command.value)['text'],
        )!;
        expect(prepared.message, 'Read ${ref.token}');
        expect(prepared.context, contains('original'));
        expect(
          chat.sideQuestionDeliveries.single.question,
          'Read ${ref.token}',
        );
        expect(chat.composer.observation.text, isEmpty);
      },
    );
  }

  test('steering uses the same scalar prepared transport', () async {
    host.event('a', 'message.start');
    await controller.updateDraft(chat, 'Read ${ref.token}', reference: ref);
    expect(
      await controller.steer(chat, chat.composer.observation.text),
      isTrue,
    );
    expect(
      PreparedComposerMessage.parse(
        lastCall('session.steer')['text'],
      )!.references.single.target,
      ref.target,
    );
    expect(chat.composer.observation.text, isEmpty);
  });

  test(
    'saved restore uses the captured canonical target before cutting history',
    () async {
      const selected = ComposerReference(
        kind: ComposerReferenceKind.file,
        token: '@file:note.md',
        target: '/work/note.md',
      );
      final old = PreparedComposerMessage(
        message: 'Read @file:note.md',
        context: 'old snapshot',
        references: const [selected],
      );
      host.historyMessages = [
        {'id': 6, 'row_id': 6, 'role': 'user', 'content': old.wireText},
        {'id': 7, 'row_id': 7, 'role': 'assistant', 'content': 'Old answer'},
      ];
      await controller.refreshHistory(chat);
      host.event('a', 'session.info', {
        'cwd': '/different',
        'terminal_backend': 'local',
      });
      host.references.files[selected.target] = 'fresh restore content';
      final prompt = chat.reading.messages.first;
      expect(
        await controller.restoreSavedPrompt(chat, prompt),
        isTrue,
        reason: chat.runtime.error,
      );
      final dispatch = lastCall('prompt.submit');
      final prepared = PreparedComposerMessage.parse(dispatch['text'])!;
      expect(prepared.context, contains('fresh restore content'));
      expect(prepared.references.single.target, selected.target);
      expect(dispatch['truncate_before_row_id'], 6);
    },
  );

  for (final terminal in ['docker', null]) {
    test(
      '$terminal namespace uses host browsing; relative context pauses',
      () async {
        host.terminal = terminal;
        host.runtimeForResume['a'] = 'a-runtime';
        await controller.reconnect(chat.key.workspace);
        final query = MentionQuery.at('@', 1)!;
        final result = await controller.completeMention(
          chat,
          query,
          bots: bots,
          canRead: () => true,
        );
        expect(result.directory, '/work');
        expect(host.references.reads, contains('files:'));
        await controller.updateDraft(chat, 'Read @file:note.md');
        await controller.send(chat);
        expect(host.calls.where((c) => c.$2 == 'prompt.submit'), isEmpty);
        expect(
          chat.composer.observation.queue.single.text,
          'Read @file:note.md',
        );
      },
    );
  }

  test('lazy cwd change retires a previous local namespace claim', () async {
    host.event('a', 'session.info', {'cwd': '/container'});
    await controller.completeMention(
      chat,
      MentionQuery.at('@', 1)!,
      bots: bots,
      canRead: () => true,
    );
    expect(host.references.reads, contains('files:'));
    expect(host.references.reads, isNot(contains('files:/container')));
    await controller.updateDraft(chat, 'Read @file:note.md');
    await controller.send(chat);
    expect(host.calls.where((c) => c.$2 == 'prompt.submit'), isEmpty);
    expect(chat.composer.observation.queue.single.text, 'Read @file:note.md');
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('workspace references ${brightness.name} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              theme: wingTheme(brightness),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 280),
                ),
                child: child!,
              ),
              home: ProfileWorkspaceScreen(
                controller: controller,
                createBotsSession: () =>
                    BotsSession((_) async => [botRepository]),
              ),
            ),
          ),
        );
        Future<void> captureFrame(String name) async {
          if (!Platform.environment.containsKey('CAPTURE_REFERENCES')) return;
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/references-review')
                ..createSync(recursive: true);
              await File(
                '${directory.path}/$name-${brightness.name}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }

        final input = find.byKey(const Key('profile-message-composer'));
        await tester.enterText(input, '@');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(find.text('HERMES'), findsOneWidget);
        final picker = find.byType(MentionSuggestions);
        final avatars = tester.widgetList<BotAvatar>(
          find.descendant(of: picker, matching: find.byType(BotAvatar)),
        );
        expect(avatars.map((a) => (a.name, a.shape, a.color, a.size)), [
          ('butler', 'hexagon', '#8b5cf6', 32.0),
          ('hermes', 'squircle', '#65c7bc', 32.0),
        ]);
        expect(
          find.descendant(
            of: picker,
            matching: find.byIcon(Icons.smart_toy_outlined),
          ),
          findsNothing,
        );
        await captureFrame('workspace-avatars');
        await tester.ensureVisible(find.text('HERMES'));
        await tester.tap(find.text('HERMES'));
        await tester.pumpAndSettle();
        expect(chat.composer.observation.references.single.target, 'hermes');
        await tester.enterText(input, '@');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Close references').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final file =
            '/work/${List.filled(4, 'long-directory').join('/')}/public_paths.py';
        host.references.files[file] = 'reference content';
        await tester.enterText(input, '@file:$file');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        final candidate = find.text('public_paths.py');
        expect(candidate.hitTestable(), findsOneWidget);
        await tester.tap(candidate);
        await tester.pumpAndSettle();
        expect(chat.composer.observation.references.single.target, file);
        expect(tester.takeException(), isNull);
        await captureFrame('workspace');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
