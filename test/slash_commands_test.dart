import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/models/slash_command.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/side_question_delivery.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/widgets/slash_command_suggestions.dart';
import 'package:wing/core/widgets/activity/skill_document_viewer.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

class CommandHost extends Host {
  final skillReads = <Map<String, String>>[];
  Future<Map<String, dynamic>> Function()? readSkill;
  final commandCalls = <(String, Map<String, dynamic>)>[];
  final extraSkillNames = <String>[];
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? respond;
  String yolo = '0';
  bool reportYolo = true;
  String warning = '';
  String? yoloSetResult;
  final List<String> sideQuestionTaskIds = ['side-task-1'];
  final List<String> backgroundTaskIds = ['background-task-1'];
  FutureOr<Map<String, dynamic>> Function(Map<String, dynamic>)?
  backgroundRespond;
  Completer<void>? sensitiveResponseDelay;
  Object? sensitiveResponseError;
  Map<String, dynamic> catalog(String profile) => {
    'pairs': [
      ['/$profile-skill', 'Profile $profile skill'],
      for (final name in extraSkillNames) [name, 'Another skill'],
      ['/model', 'Choose model'],
      ['/approvals', 'Manage approval mode'],
      ['/undo', 'Edit last prompt'],
      ['/clear', 'Clear the terminal'],
    ],
    'categories': [
      {
        'name': 'Skills',
        'pairs': [
          ['/$profile-skill', 'Profile $profile skill'],
        ],
      },
    ],
    'canon': {'/short': '/$profile-skill'},
    'skills': {for (final name in extraSkillNames) name: <String, dynamic>{}},
    'commands': {
      '/clear': {'desktop': 'terminal'},
    },
    'warning': warning,
  };

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    late final ProfileGateway gateway;
    gateway = ProfileGateway(
      scope: scope,
      discover: discover,
      connect: () async {
        if (gateway.onEvent != null) gateways[scope.profileName] = gateway;
        await base.connect();
      },
      get: (endpoint, query) async {
        if (endpoint == 'skills/content') {
          skillReads.add(Map.of(query));
          return readSkill == null
              ? {
                  'name': query['name'],
                  'content':
                      '# Skill instructions\n\nInspect the original sources.',
                  'path':
                      '/profiles/${scope.profileName}/skills/${query['name']}/SKILL.md',
                }
              : await readSkill!();
        }
        final result = await base.read(endpoint, query);
        if (!endpoint.endsWith('/messages') || historyMessages != null) {
          return result;
        }
        // Command tests start with the same empty history over REST and RPC.
        return {
          ...result,
          'messages': <Map<String, dynamic>>[],
          'pagination': {...result['pagination'] as Map, 'returned': 0},
        };
      },
      rpc: (method, params) async {
        commandCalls.add((method, params));
        if (method == 'request.answer') {
          await sensitiveResponseDelay?.future;
          final error = sensitiveResponseError;
          if (error != null) throw error;
        }
        if (method == 'commands.catalog') return catalog(scope.profileName);
        if (method == 'config.set' && params['key'] == 'yolo') {
          yolo = params['value']!.toString();
          return {'value': yoloSetResult ?? yolo};
        }
        if (method == 'prompt.btw') {
          return {'task_id': sideQuestionTaskIds.removeAt(0)};
        }
        if (method == 'prompt.background') {
          return await backgroundRespond?.call(params) ??
              {'task_id': backgroundTaskIds.removeAt(0)};
        }
        // Stock accepts text plus session_id/profile; an owned runtime supplies
        // the profile/workspace, so no additional profile is needed here.
        // Verified at upstream f42f579cf8bac4918ac9599bece71618afadd846:
        // tui_gateway/contracts/profiles_vault_complete_foreign_subagents.py.
        if (method == 'complete.slash') {
          if (params.keys.any(
            (key) => !{'text', 'session_id', 'profile'}.contains(key),
          )) {
            throw JsonRpcError(
              method,
              'Extra inputs are not permitted',
              code: 4000,
            );
          }
          return await respond?.call(method, params) ??
              {
                'items': [
                  if (params['text'] == '/approvals ')
                    for (final mode in ['manual', 'smart', 'off'])
                      {'text': mode, 'meta': ''},
                ],
                'replace_from': (params['text'] as String).runes.length,
              };
        }
        if (method == 'command.dispatch' || method == 'slash.exec') {
          return await respond?.call(method, params) ??
              {'type': 'exec', 'output': 'Done'};
        }
        if (method == 'session.history') {
          return {'messages': <Map<String, dynamic>>[]};
        }
        final result = await base.call(method, params);
        if (method == 'session.create' || method == 'session.resume') {
          return {
            ...result,
            'info': {
              ...result['info'] as Map,
              if (reportYolo) 'yolo': yolo == '1',
            },
          };
        }
        return result;
      },
    );
    return gateway;
  }
}

class _HeldPromptDraftStore extends ComposerDraftStore {
  _HeldPromptDraftStore(super.preferences, {required super.connectionIdentity});
  String? holdPrompt;
  final preparing = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write({
    required String profileName,
    required String sessionId,
    required String text,
    required Iterable<AttachmentDraft> attachments,
    bool submissionUncertain = false,
    Iterable<QueuedPromptDraft> queuedPrompts = const [],
    bool queuePaused = false,
  }) async {
    final files = attachments.toList();
    final queue = queuedPrompts.toList();
    if (holdPrompt != null && queue.any((entry) => entry.text == holdPrompt)) {
      holdPrompt = null;
      preparing.complete();
      await release.future;
    }
    await super.write(
      profileName: profileName,
      sessionId: sessionId,
      text: text,
      attachments: files,
      submissionUncertain: submissionUncertain,
      queuedPrompts: queue,
      queuePaused: queuePaused,
    );
  }
}

void main() {
  late CommandHost host;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late ProfileChat chat;
  late _HeldPromptDraftStore draftStore;
  setUpAll(() async {
    final fonts = Platform.environment['CAPTURE_SKILL_COMPOSER_FONTS'];
    if (fonts == null) return;
    for (final entry in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final font in entry.value) {
        loader.addFont(
          File('$fonts/$font').readAsBytes().then((b) => b.buffer.asByteData()),
        );
      }
      await loader.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = CommandHost();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    draftStore = _HeldPromptDraftStore(
      preferences,
      connectionIdentity: 'slash-test-host',
    );
    controller = ProfileWorkspaceController(
      connectionIdentity: 'slash-test-host',
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
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
      draftStore: draftStore,
    );
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
  });
  tearDown(() {
    controller.dispose();
    appPreferences.dispose();
  });

  test('catalog includes custom skills, aliases and no fixed size limit', () {
    final value = host.catalog('a');
    value['pairs'] = [
      ...value['pairs'] as List,
      ...List<List<String>>.generate(
        300,
        (i) => ['/skill-$i', 'Custom skill $i'],
      ),
    ];
    final catalog = SlashCatalog.fromJson(value);
    expect(catalog.search('/').length, 305);
    expect(catalog.search('/short').single.text, '/a-skill');
    expect(catalog.unavailable('clear'), contains('terminal'));
    expect(
      SlashInvocation.parse('/skill first\nsecond')!.argument,
      'first\nsecond',
    );
    expect(SlashInvocation.parse('/'), isNull);
  });

  test(
    'skill dispatch expands once and retains visible invocation and arguments',
    () async {
      host.respond = (_, params) async => {
        'type': 'skill',
        'message': 'Expanded skill body',
        'display': '/a-skill first\nsecond',
      };
      chat.composer.editText('/short first\nsecond');
      await controller.send(chat);
      final dispatch = host.commandCalls
          .singleWhere((c) => c.$1 == 'command.dispatch')
          .$2;
      expect(dispatch, containsPair('name', 'a-skill'));
      expect(dispatch['arg'], 'first\nsecond');
      final prompt = host.commandCalls
          .singleWhere((c) => c.$1 == 'prompt.submit')
          .$2;
      expect(prompt['text'], 'Expanded skill body');
      expect(prompt['profile'], 'a');
      expect(prompt['session_id'], 'a-runtime');
      expect(
        chat.reading.messages.single['display_content'],
        '/a-skill first\nsecond',
      );
      expect(chat.composer.observation.text, isEmpty);
      expect(chat.runtime.execution, ChatExecution.running);
    },
  );

  test(
    'late skill reply submits to original owner after a profile switch',
    () async {
      final reply = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => reply.future;
      chat.composer.editText('/a-skill task');
      final send = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      await controller.switchProfile('b');
      final other = await controller.createChat(canDispatch: () => true);
      other.composer.editText('Keep this draft');
      reply.complete({
        'type': 'send',
        'message': 'Expanded bundle',
        'display': '/a-skill task',
        'notice': 'Loading bundle',
      });
      await send;
      expect(controller.current!.chat, same(other));
      expect(other.composer.observation.text, 'Keep this draft');
      expect(other.reading.messages, isEmpty);
      expect(
        chat.reading.messages
            .where((row) => row['_command_notice'] == true)
            .map((row) => row['content']),
        ['Loading bundle'],
      );
      expect(
        host.commandCalls
            .singleWhere((c) => c.$1 == 'prompt.submit')
            .$2['profile'],
        'a',
      );
      expect(
        (await controller.commandCatalog(other)).commands.first.text,
        '/b-skill',
      );
    },
  );

  test(
    'skill dispatch resumes after its secret preflight is cancelled',
    () async {
      final reply = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => reply.future;
      chat.composer.editText('/a-skill needs setup');

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret', {
        'request_id': 'skill-secret',
        'env_var': 'FIXTURE_TOKEN',
        'prompt': 'Optional fixture token',
      });
      final request = chat.runtime.secureInput!;
      expect(chat.runtime.needsInput, isTrue);

      await controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: request,
      );
      reply.complete({
        'type': 'skill',
        'message': 'Expanded skill prompt after skipped setup',
        'display': '/a-skill needs setup',
      });
      await sending;

      final submissions = host.commandCalls
          .where((call) => call.$1 == 'prompt.submit')
          .toList();
      expect(submissions, hasLength(1));
      expect(
        submissions.single.$2['text'],
        'Expanded skill prompt after skipped setup',
      );
      expect(
        chat.reading.messages.single['display_content'],
        '/a-skill needs setup',
      );
      expect(chat.composer.observation.text, isEmpty);
      expect(chat.runtime.execution, ChatExecution.running);
    },
  );

  test(
    'late secret response acknowledgement does not block the expanded skill prompt',
    () async {
      final dispatch = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => dispatch.future;
      host.sensitiveResponseDelay = Completer<void>();
      chat.composer.editText('/a-skill delayed cancel');

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret', {
        'request_id': 'delayed-secret',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.runtime.secureInput!;
      final cancelling = controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: request,
      );
      dispatch.complete({
        'type': 'skill',
        'message': 'Expanded while cancel acknowledgement is pending',
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(1),
      );
      expect(chat.runtime.execution, ChatExecution.running);
      host.sensitiveResponseDelay!.complete();
      await cancelling;
      await sending;
      expect(chat.runtime.execution, ChatExecution.running);
      expect(chat.runtime.secureInput, isNull);
    },
  );

  for (final crossing in ['failed answer', 'new request']) {
    test(
      'returned command prompt is refused after $crossing during preparation',
      () async {
        final dispatch = Completer<Map<String, dynamic>>();
        host.respond = (_, _) => dispatch.future;
        host.sensitiveResponseDelay = Completer<void>();
        draftStore.holdPrompt = 'Captured expanded prompt';
        addTearDown(() {
          if (!draftStore.release.isCompleted) draftStore.release.complete();
          if (!host.sensitiveResponseDelay!.isCompleted) {
            host.sensitiveResponseDelay!.complete();
          }
        });
        await controller.updateDraft(chat, '/a-skill captured continuation');
        final sending = controller.send(chat);
        await Future<void>.delayed(Duration.zero);
        host.event('a', 'secret', {'request_id': 'preflight-a'});
        final answering = controller.respondSensitivePrompt(
          chat,
          'synthetic-secret',
          expectedRequest: chat.runtime.secureInput!,
        );
        Object? answerError;
        final settledAnswer = answering.catchError((Object error) {
          answerError = error;
        });
        dispatch.complete({
          'type': 'skill',
          'message': 'Captured expanded prompt',
        });
        await draftStore.preparing.future;
        expect(
          host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
          isEmpty,
        );
        expect(chat.runtime.secureResponding, isTrue);
        if (crossing == 'failed answer') {
          host.sensitiveResponseError = StateError('Definite answer refusal');
        } else {
          host.event('a', 'secret', {'request_id': 'preflight-b'});
        }
        host.sensitiveResponseDelay!.complete();
        await settledAnswer;
        draftStore.release.complete();
        await sending;
        expect(
          host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
          isEmpty,
        );
        expect(
          host.commandCalls.where((call) => call.$1 == 'command.dispatch'),
          hasLength(1),
        );
        expect(
          chat.runtime.secureInput?.requestId,
          crossing == 'failed answer' ? 'preflight-a' : 'preflight-b',
        );
        expect(chat.runtime.secureResponding, isFalse);
        expect(chat.composer.observation.submissionUncertain, isFalse);
        if (crossing == 'failed answer') {
          expect(answerError, isStateError);
        } else {
          expect(answerError, isNull);
        }
      },
    );
  }

  test(
    'secret request during prompt acknowledgement remains a live turn',
    () async {
      host.respond = (_, _) async => {
        'type': 'skill',
        'message': 'Expanded prompt',
      };
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      chat.composer.editText('/a-skill live prompt secret');

      final sending = controller.send(chat);
      await host.promptSubmitStarted!.future;
      host.event('a', 'secret', {
        'request_id': 'live-turn-secret',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.runtime.secureInput!;
      expect(chat.runtime.needsInput, isTrue);
      await controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: request,
      );
      expect(chat.runtime.execution, ChatExecution.running);

      host.promptSubmitDelay!.complete();
      await sending;
      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(1),
      );
      expect(chat.runtime.execution, ChatExecution.running);
    },
  );

  test(
    'failed preflight secret response can be retried before skill submit',
    () async {
      final dispatch = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => dispatch.future;
      host.sensitiveResponseError = TimeoutException('retry response');
      chat.composer.editText('/a-skill retry secret');

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret', {
        'request_id': 'retry-secret',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.runtime.secureInput!;
      await expectLater(
        controller.respondSensitivePrompt(chat, '', expectedRequest: request),
        throwsA(isA<TimeoutException>()),
      );
      expect(chat.runtime.needsInput, isTrue);
      expect(chat.runtime.secureInput, same(request));

      host.sensitiveResponseError = null;
      await controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: request,
      );
      dispatch.complete({
        'type': 'skill',
        'message': 'Expanded after secret retry',
      });
      await sending;

      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(1),
        reason: chat.runtime.error,
      );
      expect(chat.runtime.execution, ChatExecution.running);
    },
  );

  test(
    'replacement preflight request keeps the original return state',
    () async {
      final dispatch = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => dispatch.future;
      emitChatEvent(controller, chat, 'message.start');
      emitChatEvent(controller, chat, 'session.info', {
        'open_requests': [],
        'running': false,
      });
      await restoreComposerFixture(
        chat: chat,
        preferences: controller.preferences,
        text: '/a-skill replacement secret',
      );

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret', {
        'request_id': 'first-secret',
        'env_var': 'FIRST_TOKEN',
      });
      host.event('a', 'secret', {
        'request_id': 'replacement-secret',
        'env_var': 'SECOND_TOKEN',
      });
      final replacement = chat.runtime.secureInput!;
      await controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: replacement,
      );
      expect(chat.runtime.execution, ChatExecution.completed);

      dispatch.complete({
        'type': 'skill',
        'message': 'Expanded after replacement secret',
      });
      await sending;
      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(1),
      );
      expect(chat.runtime.execution, ChatExecution.running);
    },
  );

  test(
    'sensitive preflight expiry releases every stock request kind',
    () async {
      const cases = [
        'sudo',
        'secret',
        'vault.unlock_prompt',
        'vault.save_login',
        'vault.code',
      ];

      for (var index = 0; index < cases.length; index++) {
        final dispatch = Completer<Map<String, dynamic>>();
        host.respond = (_, _) => dispatch.future;
        emitChatEvent(controller, chat, 'message.start');
        emitChatEvent(controller, chat, 'session.info', {
          'open_requests': [],
          'running': false,
        });
        await restoreComposerFixture(
          chat: chat,
          preferences: controller.preferences,
          text: '/a-skill expiring request $index',
        );
        final sending = controller.send(chat);
        await Future<void>.delayed(Duration.zero);
        final requestId = 'expiring-$index';
        host.event('a', cases[index], {'request_id': requestId});
        expect(chat.runtime.needsInput, isTrue);

        host.event('a', 'request.cancel', {
          'id': requestId,
          'method': cases[index],
          'reason': 'timeout',
        });
        expect(chat.runtime.secureInput, isNull);
        expect(chat.runtime.execution, ChatExecution.completed);
        dispatch.complete({
          'type': 'skill',
          'message': 'Expanded after expiry $index',
        });
        await sending;
        expect(chat.runtime.execution, ChatExecution.running);
      }

      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(cases.length),
      );
    },
  );

  test('sensitive expiry during an active turn stays running', () async {
    emitChatEvent(controller, chat, 'message.start');
    host.event('a', 'secret', {'request_id': 'active-secret-expiry'});
    expect(chat.runtime.needsInput, isTrue);

    host.event('a', 'request.cancel', {
      'id': 'active-secret-expiry',
      'method': 'secret',
      'reason': 'timeout',
    });

    expect(chat.runtime.secureInput, isNull);
    expect(chat.runtime.execution, ChatExecution.running);
  });

  test('duplicate taps do not execute a command twice', () async {
    final reply = Completer<Map<String, dynamic>>();
    host.respond = (_, _) => reply.future;
    chat.composer.editText('/custom');
    final first = controller.send(chat);
    await controller.send(chat);
    reply.complete({'type': 'exec', 'output': 'Done'});
    await first;
    expect(
      host.commandCalls.where((c) => c.$1 == 'command.dispatch'),
      hasLength(1),
    );
  });

  test('text output settles without expecting stream events', () async {
    chat.composer.editText('/custom');
    await controller.send(chat);
    expect(chat.runtime.blocksTurnAdmission, isFalse);
    expect(chat.runtime.commandRunning, isFalse);
    expect(
      chat.reading.messages
          .where((row) => row['_command_notice'] == true)
          .map((row) => row['content']),
      ['Done'],
    );
    expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
  });

  test(
    'undo prefill edits composer without automatically submitting',
    () async {
      host.respond = (_, _) async => {
        'type': 'prefill',
        'message': 'Edit this question',
        'notice': 'Rewound',
      };
      chat.composer.editText('/undo');
      await controller.send(chat);
      expect(chat.composer.observation.text, 'Edit this question');
      expect(
        chat.reading.messages
            .where((row) => row['_command_notice'] == true)
            .map((row) => row['content']),
        ['Rewound'],
      );
      expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
    },
  );

  test('explicit dispatch refusal routes built-in to slash.exec', () async {
    host.respond = (method, _) async {
      if (method == 'command.dispatch') {
        throw JsonRpcError(
          method,
          'not a quick/plugin/bundle/skill command: model',
          code: 4018,
        );
      }
      return {'output': 'Model changed', 'warning': 'Session only'};
    };
    chat.composer.editText('/model provider/model');
    await controller.send(chat);
    expect(
      host.commandCalls.singleWhere((c) => c.$1 == 'slash.exec').$2['command'],
      '/model provider/model',
    );
    expect(
      chat.reading.messages
          .where((row) => row['_command_notice'] == true)
          .map((row) => row['content']),
      ['Session only', 'Model changed'],
    );
  });

  test('timeout never retries via slash.exec or prompt.submit', () async {
    host.respond = (_, _) async => throw TimeoutException('lost reply');
    chat.composer.editText('/custom');
    await controller.send(chat);
    expect(chat.composer.observation.text, '/custom');
    expect(chat.runtime.error, contains('uncertain'));
    expect(
      host.commandCalls.where(
        (c) => {'slash.exec', 'prompt.submit'}.contains(c.$1),
      ),
      isEmpty,
    );
  });

  test(
    'command error is preserved and is not treated as routing refusal',
    () async {
      host.respond = (method, _) async =>
          throw JsonRpcError(method, 'quick command failed', code: 4018);
      chat.composer.editText('/custom');
      await controller.send(chat);
      expect(chat.runtime.error, contains('quick command failed'));
      expect(chat.composer.observation.text, '/custom');
      expect(host.commandCalls.where((c) => c.$1 == 'slash.exec'), isEmpty);
    },
  );

  test('alias cycles terminate without a model request', () async {
    host.respond = (_, _) async => {'type': 'alias', 'target': 'cycle'};
    chat.composer.editText('/cycle');
    await controller.send(chat);
    expect(chat.runtime.error, contains('alias cycle'));
    expect(
      host.commandCalls.where((c) => c.$1 == 'command.dispatch'),
      hasLength(1),
    );
  });

  test('catalog normalizes quick commands without a leading slash', () {
    final catalog = SlashCatalog.fromJson({
      'pairs': [
        ['deploy', 'User command'],
      ],
      'canon': {'deploy': 'deploy'},
    });
    expect(catalog.commands.single.text, '/deploy');
    expect(catalog.resolve('deploy'), 'deploy');
  });

  test('catalog identifies skills supplied outside the categories array', () {
    final catalog = SlashCatalog.fromJson({
      'pairs': [
        ['/custom-skill', 'Installed skill'],
      ],
      'categories': <Map<String, dynamic>>[],
      'skills': {
        '/custom-skill': {'usage': 0, 'origin': 'local'},
      },
    });
    expect(catalog.commands.single.category, 'Skills');
  });

  test(
    'side-question acknowledgement and completion stay with their owner',
    () async {
      chat.composer.editText('/btw What changed?');
      await controller.send(chat);
      expect(
        chat.sideQuestionDeliveries.single.state,
        SideQuestionDeliveryState.pending,
      );
      expect(chat.sideQuestionDeliveries.single.taskId, 'side-task-1');
      expect(chat.sideQuestionDeliveries.single.question, 'What changed?');
      await controller.switchProfile('b');
      final other = await controller.createChat(canDispatch: () => true);
      host.event('a', 'btw.complete', {
        'task_id': 'side-task-1',
        'question': 'What changed?',
        'text': ' Side answer ',
      });
      final delivery = chat.sideQuestionDeliveries.single;
      expect(delivery.state, SideQuestionDeliveryState.completed);
      expect(delivery.result, 'Side answer');
      expect(
        chat.reading.messages
            .where((row) => row['_command_notice'] == true)
            .map((row) => row['content']),
        ['Started /btw on the Hermes host.'],
      );
      expect(
        other.reading.messages
            .where((row) => row['_command_notice'] == true)
            .map((row) => row['content']),
        isEmpty,
      );
      expect(other.sideQuestionDeliveries, isEmpty);
      expect(host.commandCalls.singleWhere((c) => c.$1 == 'prompt.btw').$2, {
        'session_id': 'a-runtime',
        'text': 'What changed?',
        'profile': 'a',
      });
      expect(host.commandCalls.where((c) => c.$1 == 'slash.exec'), isEmpty);
    },
  );

  test(
    'side-question completions correlate out of order and skip blanks',
    () async {
      host.sideQuestionTaskIds.add('side-task-2');
      chat.composer.editText('/btw First question');
      await controller.send(chat);
      chat.composer.editText('/btw Second question');
      await controller.send(chat);

      host.event('a', 'btw.complete', {
        'task_id': 'side-task-2',
        'question': 'Second question',
        'text': 'Second answer',
      });
      host.event('a', 'btw.complete', {
        'task_id': 'side-task-1',
        'question': 'First question',
        'text': 'First answer',
      });
      host.event('a', 'btw.complete', {
        'task_id': 'ignored',
        'question': 'Blank',
        'text': '   ',
      });

      expect(chat.sideQuestionDeliveries, hasLength(2));
      expect(chat.sideQuestionDeliveries[0].result, 'First answer');
      expect(chat.sideQuestionDeliveries[1].result, 'Second answer');
      expect(
        chat.sideQuestionDeliveries.map((delivery) => delivery.state),
        everyElement(SideQuestionDeliveryState.completed),
      );
    },
  );

  test('event-only side-question completion is still delivered', () async {
    host.event('a', 'btw.complete', {
      'task_id': 'desktop-task',
      'question': 'Asked elsewhere',
      'text': 'Remote answer',
    });

    final delivery = chat.sideQuestionDeliveries.single;
    expect(delivery.taskId, 'desktop-task');
    expect(delivery.question, 'Asked elsewhere');
    expect(delivery.state, SideQuestionDeliveryState.completed);
    expect(delivery.result, 'Remote answer');
  });

  test(
    'background acknowledgement and completion stay with their owner while busy',
    () async {
      emitChatEvent(controller, chat, 'message.start');
      chat.composer.editText('/bg Check the deployment');
      await controller.send(chat);

      final pending = chat.sideQuestionDeliveries.single;
      expect(pending.kind, SideQuestionDeliveryKind.backgroundTask);
      expect(pending.taskId, 'background-task-1');
      expect(pending.question, 'Check the deployment');
      expect(pending.state, SideQuestionDeliveryState.pending);
      expect(chat.runtime.execution, ChatExecution.running);
      await controller.switchProfile('b');
      final other = await controller.createChat(canDispatch: () => true);

      host.event('a', 'background.complete', {
        'task_id': 'background-task-1',
        'text': ' Deployment failed: inspect logs. ',
      });

      final completed = chat.sideQuestionDeliveries.single;
      expect(completed.state, SideQuestionDeliveryState.completed);
      expect(completed.result, 'Deployment failed: inspect logs.');
      expect(other.sideQuestionDeliveries, isEmpty);
      expect(
        host.commandCalls
            .singleWhere((call) => call.$1 == 'prompt.background')
            .$2,
        {
          'session_id': 'a-runtime',
          'text': 'Check the deployment',
          'profile': 'a',
        },
      );
    },
  );

  test(
    'background completion before acknowledgement keeps its result and prompt',
    () async {
      host.sideQuestionTaskIds[0] = 'shared-task';
      chat.composer.editText('/btw Side work');
      await controller.send(chat);
      host.backgroundRespond = (params) {
        host.event('a', 'background.complete', {
          'task_id': 'shared-task',
          'text': 'Background result',
        });
        return {'task_id': 'shared-task'};
      };

      chat.composer.editText('/background Background work');
      await controller.send(chat);

      expect(chat.sideQuestionDeliveries, hasLength(2));
      final side = chat.sideQuestionDeliveries.singleWhere(
        (delivery) => delivery.kind == SideQuestionDeliveryKind.sideQuestion,
      );
      final background = chat.sideQuestionDeliveries.singleWhere(
        (delivery) => delivery.kind == SideQuestionDeliveryKind.backgroundTask,
      );
      expect(side.state, SideQuestionDeliveryState.pending);
      expect(background.taskId, 'shared-task');
      expect(background.question, 'Background work');
      expect(background.state, SideQuestionDeliveryState.completed);
      expect(background.result, 'Background result');
    },
  );

  test('blank background completion reports a neutral completed result', () {
    host.event('a', 'background.complete', {
      'task_id': 'external-background',
      'text': '   ',
    });

    final delivery = chat.sideQuestionDeliveries.single;
    expect(delivery.kind, SideQuestionDeliveryKind.backgroundTask);
    expect(delivery.state, SideQuestionDeliveryState.completed);
    expect(delivery.result, 'No response text was returned.');
  });

  test(
    'background acknowledgement without a task ID preserves the draft',
    () async {
      host.backgroundRespond = (_) => <String, dynamic>{};
      chat.composer.editText('/bg Keep this command');

      await controller.send(chat);

      expect(chat.composer.observation.text, '/bg Keep this command');
      expect(chat.sideQuestionDeliveries, isEmpty);
      expect(
        chat.runtime.error,
        'Hermes did not confirm the background task. '
        'Check whether it started before sending this draft again.',
      );
      expect(chat.runtime.error, isNot(contains('FormatException')));
    },
  );

  test('yolo toggles the hydrated live session while busy', () async {
    emitChatEvent(controller, chat, 'message.start');
    host.event('a', 'session.info', {'yolo': true});
    chat.composer.editText('/yolo');

    await controller.send(chat);

    expect(
      host.commandCalls.where((call) => call.$1 == 'config.set').single.$2,
      {'session_id': 'a-runtime', 'key': 'yolo', 'value': '0', 'profile': 'a'},
    );
    expect(
      chat.reading.messages
          .where((row) => row['_command_notice'] == true)
          .map((row) => row['content']),
      ['YOLO disabled for this session.'],
    );
    expect(chat.yolo, isFalse);
    expect(chat.composer.observation.text, isEmpty);
    expect(chat.runtime.execution, ChatExecution.running);
    expect(
      host.commandCalls.where(
        (call) => {'command.dispatch', 'slash.exec'}.contains(call.$1),
      ),
      isEmpty,
    );
  });

  test(
    'yolo resumes unknown state and displays the acknowledged state',
    () async {
      // A fresh create response already reports YOLO. Open an existing chat
      // whose initial info omits it, then let the deliberate command resume
      // observe the server's current value through the real owner path.
      controller.dispose();
      host = CommandHost()..reportYolo = false;
      controller = ProfileWorkspaceController(
        connectionIdentity: 'slash-test-host',
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
        preferences: await SharedPreferences.getInstance(),
        appPreferences: appPreferences,
        gatewayFactory: host.gateway,
        draftStore: draftStore,
      );
      await controller.initialize();
      chat = (await controller.openSession(
        ProfileSessionKey(controller.current!.scope, 'same'),
      ))!;
      expect(chat.yolo, isNull);
      host.commandCalls.clear();
      host.reportYolo = true;
      host.yolo = '1';
      host.yoloSetResult = '1';
      chat.composer.editText('/yolo');

      final notification = await controller.send(chat);

      expect(
        host.commandCalls.where((call) => call.$1 == 'config.set').single.$2,
        containsPair('value', '0'),
      );
      expect(
        host.commandCalls
            .where((call) => call.$1 == 'session.resume')
            .single
            .$2,
        {'session_id': 'same', 'omit_messages': true, 'profile': 'a'},
      );
      expect(notification, isNull);
      expect(
        chat.reading.messages.last['content'],
        'YOLO enabled for this session.',
      );
      expect(chat.yolo, isTrue);
    },
  );

  test('terminal commands explain requirement and preserve draft', () async {
    chat.composer.editText('/clear');
    await controller.send(chat);
    expect(chat.runtime.error, contains('requires the Hermes terminal'));
    expect(chat.composer.observation.text, '/clear');
    expect(host.commandCalls.where((c) => c.$1 == 'command.dispatch'), isEmpty);
  });

  test(
    'interrupt while busy uses exact session and preserves turn status',
    () async {
      emitChatEvent(controller, chat, 'message.start');
      chat.composer.editText('/interrupt');
      await controller.send(chat);
      expect(
        host.commandCalls
            .singleWhere((c) => c.$1 == 'session.interrupt')
            .$2['session_id'],
        'a-runtime',
      );
      expect(chat.runtime.execution, ChatExecution.running);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('long command warning scrolls at 320dp/200% ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      host.warning =
          'Some commands are unavailable while this server is reconnecting. Your draft is kept. You can still send a command by name after checking its availability.';
      final input = SkillComposerController(text: '/a-');
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Column(
              children: [
                SlashCommandSuggestions(
                  inspectSkill: (_) async {},
                  loadCompletion: (query) =>
                      controller.completeCommand(chat, query),
                  saveDraft: (text) => controller.updateDraft(chat, text),
                  composer: input,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('/a-skill'), 150);
      await tester.tap(find.text('/a-skill'));
      expect(input.text, '/a-skill ');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'picker searches all skills and inserts selection without sending',
    (tester) async {
      final input = SkillComposerController(text: '/a-');
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SlashCommandSuggestions(
                  inspectSkill: (_) async {},
                  loadCompletion: (query) =>
                      controller.completeCommand(chat, query),
                  saveDraft: (text) => controller.updateDraft(chat, text),
                  composer: input,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('/a-skill'), findsOneWidget);
      await tester.tap(find.text('/a-skill'));
      expect(input.text, '/a-skill ');
      expect(chat.composer.observation.text, '/a-skill ');
      expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'completion captures Unicode range and keeps suffix without mutable items',
    () {
      final row = {'text': 'provider/model', 'meta': 'Model'};
      final completion = SlashCompletion.fromJson('/model 😀pr', {
        'items': [row],
        'replace_from': 8,
      }, warning: 'Current catalog warning');
      row['text'] = 'changed later';
      expect(completion.replaceFrom, 9);
      expect(completion.items.single.text, 'provider/model');
      expect(() => completion.items.clear(), throwsUnsupportedError);
      final edit = completion.select(
        completion.items.single,
        text: '/model 😀pr keep',
        cursor: 11,
      )!;
      expect(edit.text, '/model 😀provider/model keep');
      expect(edit.cursor, 23);
      expect(
        completion.select(
          completion.items.single,
          text: '/model other',
          cursor: 12,
        ),
        isNull,
      );
    },
  );

  testWidgets('inline skill picker replaces the token at the cursor', (
    tester,
  ) async {
    final input = SkillComposerController.fromValue(
      const TextEditingValue(
        text: 'Please 😀 use /a- for this task',
        selection: TextSelection.collapsed(offset: 17),
      ),
    );
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlashCommandSuggestions(
            inspectSkill: (_) async {},
            loadCompletion: (query) => controller.completeCommand(chat, query),
            saveDraft: (text) => controller.updateDraft(chat, text),
            composer: input,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('/a-skill'), findsOneWidget);
    expect(find.text('/model'), findsNothing);
    await tester.tap(find.text('/a-skill'));
    expect(input.text, 'Please 😀 use /a-skill for this task');
    expect(input.selection.extentOffset, 22);
    expect(chat.composer.observation.text, input.text);
    expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'inline skills expand through stock dispatch and retain the visible message',
    () async {
      const original = 'Please use /a-skill for this task';
      host.respond = (_, params) async => {
        'type': 'skill',
        'message': 'Expanded instructions for ${params['arg']}',
      };
      chat.composer.editText(original);
      await controller.send(chat);
      final dispatch = host.commandCalls
          .singleWhere((c) => c.$1 == 'command.dispatch')
          .$2;
      expect(dispatch['name'], 'a-skill');
      expect(dispatch['arg'], original);
      expect(dispatch['session_id'], 'a-runtime');
      expect(
        host.commandCalls
            .singleWhere((c) => c.$1 == 'prompt.submit')
            .$2['text'],
        'Expanded instructions for $original',
      );
      expect(chat.reading.messages.single['display_content'], original);
    },
  );

  test(
    'an inline skill failure retains queued work without submitting plain text',
    () async {
      host.respond = (_, _) async => throw StateError('Skill load failed');
      const original = 'Please use /a-skill for this task';
      chat.composer.editText(original);
      await controller.send(chat);
      expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
      expect(chat.composer.observation.queue.single.text, original);
      expect(chat.runtime.error, contains('Skill load failed'));
    },
  );

  test('inline commands and paths stay literal', () async {
    const original =
        'Explain /model and /usr/local and https://example.com/a-skill';
    chat.composer.editText(original);
    await controller.send(chat);
    expect(host.commandCalls.where((c) => c.$1 == 'command.dispatch'), isEmpty);
    expect(
      host.commandCalls.singleWhere((c) => c.$1 == 'prompt.submit').$2['text'],
      original,
    );
    for (final text in [
      'hello https://example.com/a-',
      'hello /usr/local',
      'hello word/a-',
      'hello /a- done',
    ]) {
      expect(SlashCompletion.isQuery(text), isFalse, reason: text);
    }
    expect(SlashCompletion.isQuery('hello\n/a-'), isTrue);
  });

  for (final original in [
    'Use /a-skill and /a-other then /a-skill again',
    '/a-skill use /a-other then /a-skill again',
  ]) {
    test('distinct skills load once: $original', () async {
      host.extraSkillNames.add('/a-other');
      host.respond = (_, params) async => {
        'type': 'skill',
        'message': 'Expanded ${params['name']}',
      };
      chat.composer.editText(original);
      await controller.send(chat);
      expect(
        host.commandCalls
            .where((c) => c.$1 == 'command.dispatch')
            .map((c) => c.$2['name']),
        ['a-skill', 'a-other'],
      );
      expect(
        host.commandCalls
            .singleWhere((c) => c.$1 == 'prompt.submit')
            .$2['text'],
        'Expanded a-skill\n\nExpanded a-other',
      );
      expect(chat.reading.messages.single['display_content'], original);
    });
  }

  test(
    'saved inline skill messages recover the original multiline instruction',
    () {
      const original = 'Please use /a-skill\nfor this task';
      const expanded =
          '[IMPORTANT: The user has invoked the "a-skill" skill.\n'
          'The full skill content is loaded below.]\nPrivate skill body\n'
          'The user has provided the following instruction alongside the skill invocation: $original\n\n'
          '[Runtime note: private]';
      expect(
        answerMessageDisplayText({'role': 'user', 'content': expanded}),
        original,
      );
    },
  );

  testWidgets(
    'skill emphasis preserves plain text, editing and IME decoration',
    (tester) async {
      final input = SkillComposerController(
        text: 'Use /a-skill then /model and /a-skill/path',
      );
      addTearDown(input.dispose);
      input.observeCommands(const [SlashCommand('/a-skill', '', 'Skills')]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: input)),
        ),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      final context = tester.element(find.byType(EditableText));
      TextSpan span() => input.buildTextSpan(
        context: context,
        style: editable.style,
        withComposing: true,
      );
      expect(span().toPlainText(), input.text);
      final skill = span().children!.whereType<TextSpan>().singleWhere(
        (s) => s.text == '/a-skill',
      );
      expect(skill.style!.fontWeight, FontWeight.w700);
      expect(skill.style!.color, Theme.of(context).colorScheme.primary);
      input.value = input.value.copyWith(
        composing: const TextRange(start: 6, end: 10),
      );
      expect(
        span().children!
            .whereType<TextSpan>()
            .where((s) => s.style?.decoration == TextDecoration.underline)
            .map((s) => s.text)
            .join(),
        '-ski',
      );
      input.text = 'Use /a-skil then /model';
      expect(
        span().children!.whereType<TextSpan>().where(
          (s) => s.style?.fontWeight == FontWeight.w700,
        ),
        isEmpty,
      );
      input.text = 'Use /a-skill';
      input.setScope('another profile');
      expect(
        span().children!.whereType<TextSpan>().where(
          (s) => s.style?.fontWeight == FontWeight.w700,
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('mobile inline skill composer ${brightness.name} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              theme: wingTheme(brightness),
              debugShowCheckedModeBanner: false,
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
        final composer = find.byKey(const Key('profile-message-composer'));
        await tester.enterText(composer, 'Please use /a-');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(find.text('/a-skill'), findsOneWidget);
        Future<void> capture(String state) async {
          if (!Platform.environment.containsKey('CAPTURE_SKILL_COMPOSER')) {
            return;
          }
          await tester.runAsync(() async {
            final render =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/skill-composer/${brightness.name}-$scale-$state.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('picker');
        final inspect = find.byTooltip('Inspect /a-skill');
        expect(tester.getSize(inspect), const Size(48, 48));
        await tester.tap(inspect);
        await tester.pumpAndSettle();
        expect(find.byType(SkillDocumentViewer), findsOneWidget);
        expect(
          tester
              .widget<SkillDocumentViewer>(find.byType(SkillDocumentViewer))
              .document
              .rawContent,
          contains('Inspect the original sources.'),
        );
        expect(host.skillReads.single, {'profile': 'a', 'name': 'a-skill'});
        expect(chat.composer.observation.text, 'Please use /a-');
        expect(
          host.commandCalls.where((c) => c.$1 == 'prompt.submit'),
          isEmpty,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(composer).controller!.text,
          'Please use /a-',
        );
        expect(inspect.hitTestable(), findsOneWidget);
        await tester.tap(find.text('/a-skill'));
        await tester.pumpAndSettle();
        final input = tester.widget<TextField>(composer).controller!;
        expect(input.text, 'Please use /a-skill ');
        expect(
          find.byType(SlashCommandSuggestions).hitTestable(),
          findsNothing,
        );
        final editable = tester.widget<EditableText>(
          find.descendant(of: composer, matching: find.byType(EditableText)),
        );
        final span = input.buildTextSpan(
          context: tester.element(composer),
          style: editable.style,
          withComposing: true,
        );
        expect(
          span.children!
              .whereType<TextSpan>()
              .singleWhere((s) => s.text == '/a-skill')
              .style!
              .fontWeight,
          FontWeight.w700,
        );
        expect(tester.takeException(), isNull);
        await capture('selected');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('skill inspection failure retains draft and permits retry', (
    tester,
  ) async {
    host.readSkill = () async => throw StateError('Offline');
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    final composer = find.byKey(const Key('profile-message-composer'));
    await tester.enterText(composer, '/a-');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Inspect /a-skill'));
    await tester.pumpAndSettle();
    expect(find.byType(SkillDocumentViewer), findsNothing);
    expect(
      find.text(
        'Could not read this skill. Check the connection and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(composer).controller!.text, '/a-');
    host.readSkill = null;
    await tester.tap(find.byTooltip('Inspect /a-skill'));
    await tester.pumpAndSettle();
    expect(find.byType(SkillDocumentViewer), findsOneWidget);
    expect(host.skillReads, hasLength(2));
    expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'held skill inspection ignores repeat taps and a changed profile',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      host.readSkill = () => pending.future;
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.enterText(
        find.byKey(const Key('profile-message-composer')),
        '/',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Inspect /model'), findsNothing);
      final inspect = find.byTooltip('Inspect /a-skill');
      await tester.tap(inspect);
      await tester.pump();
      await tester.tap(inspect);
      await tester.pump();
      expect(host.skillReads, hasLength(1));
      await controller.switchProfile('b');
      await tester.pump();
      pending.complete({'name': 'a-skill', 'content': 'Late instructions'});
      await tester.pumpAndSettle();
      expect(find.byType(SkillDocumentViewer), findsNothing);
      expect(host.skillReads.single, {'profile': 'a', 'name': 'a-skill'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('completion keeps the owning session after a profile switch', () async {
    await controller.switchProfile('b');
    final other = await controller.createChat(canDispatch: () => true);

    expect(other.runtime.runtimeId, isNot(chat.runtime.runtimeId));
    await controller.completeCommand(chat, '/approvals ');
    await controller.completeCommand(other, '/model ');

    expect(
      host.commandCalls
          .where((call) => call.$1 == 'complete.slash')
          .map((call) => call.$2),
      [
        {'session_id': chat.runtime.runtimeId, 'text': '/approvals '},
        {'session_id': other.runtime.runtimeId, 'text': '/model '},
      ],
    );
  });

  testWidgets('selecting /approvals does not show a command loading error', (
    tester,
  ) async {
    host.warning =
        'slash command /handoff unavailable — name taken by built-in; use /skill handoff; '
        'slash command /plan unavailable — name taken by built-in; use /skill plan';
    final input = SkillComposerController(text: '/app');
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlashCommandSuggestions(
            inspectSkill: (_) async {},
            loadCompletion: (query) => controller.completeCommand(chat, query),
            saveDraft: (text) => controller.updateDraft(chat, text),
            composer: input,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/approvals'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(input.text, '/approvals ');
    expect(chat.composer.observation.text, '/approvals ');
    expect(find.text('Could not load commands. Tap to retry.'), findsNothing);
    expect(find.text('manual'), findsOneWidget);
    expect(host.commandCalls.singleWhere((c) => c.$1 == 'complete.slash').$2, {
      'session_id': 'a-runtime',
      'text': '/approvals ',
    });
    expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'argument completion replaces only the server range and keeps suffix',
    (tester) async {
      host.respond = (_, _) async => {
        'items': [
          {'text': 'provider/model', 'meta': 'Model'},
        ],
        'replace_from': 7,
      };
      final input = SkillComposerController.fromValue(
        const TextEditingValue(
          text: '/model pr keep',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlashCommandSuggestions(
              inspectSkill: (_) async {},
              loadCompletion: (query) =>
                  controller.completeCommand(chat, query),
              saveDraft: (text) => controller.updateDraft(chat, text),
              composer: input,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('provider/model'));
      expect(input.text, '/model provider/model keep');
      expect(input.selection.extentOffset, 21);
      await tester.pumpWidget(const SizedBox.shrink());
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final saved =
          await ComposerDraftStore(
            preferences,
            connectionIdentity: controller.connectionIdentity,
          ).read(
            profileName: chat.key.workspace.profileName,
            sessionId: chat.key.sessionId,
          );
      expect(saved?.text, '/model provider/model keep');
      final restored = ProfileWorkspaceController(
        access: controller.access,
        connectionIdentity: controller.connectionIdentity,
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: host.gateway,
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      await restored.openSession(chat.key);
      expect(
        restored.current!.chat!.composer.observation.text,
        '/model provider/model keep',
      );
    },
  );

  testWidgets('late completion cannot replace a newer search', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    host.respond = (_, _) => delayed.future;
    final input = SkillComposerController(text: '/model pr');
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlashCommandSuggestions(
            inspectSkill: (_) async {},
            loadCompletion: (query) => controller.completeCommand(chat, query),
            saveDraft: (text) => controller.updateDraft(chat, text),
            composer: input,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    input.text = '/a-';
    await tester.pump(const Duration(milliseconds: 200));
    delayed.complete({
      'items': [
        {'text': 'stale model', 'meta': ''},
      ],
      'replace_from': 7,
    });
    await tester.pumpAndSettle();
    expect(find.text('/a-skill'), findsOneWidget);
    expect(find.text('stale model'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'mobile composer sends skill and displays invocation, not expanded body',
    (tester) async {
      host.respond = (_, _) async => {
        'type': 'skill',
        'message': 'Internal expanded skill body',
        'display': '/a-skill task',
      };
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.enterText(
        find.byKey(const Key('profile-message-composer')),
        '/a-skill task',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Send'));
      // The fixture and widget callbacks use different async zones.
      for (var i = 0; i < 100 && chat.runtime.commandRunning; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pump();
      expect(chat.runtime.commandRunning, isFalse);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              (widget.data ?? widget.textSpan?.toPlainText()) ==
                  '/a-skill task',
        ),
        findsOneWidget,
      );
      expect(find.text('Internal expanded skill body'), findsNothing);
      expect(chat.runtime.execution, ChatExecution.running);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
