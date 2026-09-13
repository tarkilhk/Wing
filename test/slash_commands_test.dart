import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/slash_command.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/models/side_question_delivery.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/slash_command_suggestions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

class CommandHost extends Host {
  final commandCalls = <(String, Map<String, dynamic>)>[];
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? respond;
  String yolo = '0';
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
      ['/model', 'Choose model'],
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
    'commands': {
      '/clear': {'desktop': 'terminal'},
    },
    'warning': '',
  };

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    final gateway = ProfileGateway(
      scope: scope,
      discover: discover,
      get: (endpoint, query) async {
        final result = await base.read(endpoint, query);
        if (!endpoint.endsWith('/messages')) return result;
        // Command tests start with the same empty history over REST and RPC.
        return {
          ...result,
          'messages': <Map<String, dynamic>>[],
          'pagination': {...result['pagination'] as Map, 'returned': 0},
        };
      },
      rpc: (method, params) async {
        commandCalls.add((method, params));
        if (method == 'secret.respond') {
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
        if (method == 'command.dispatch' ||
            method == 'slash.exec' ||
            method == 'complete.slash') {
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
            'info': {...result['info'] as Map, 'yolo': yolo == '1'},
          };
        }
        return result;
      },
    );
    gateways[scope.profileName] = gateway;
    return gateway;
  }
}

void main() {
  late CommandHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = CommandHost();
    controller = ProfileWorkspaceController(
      connectionIdentity: 'slash-test-host',
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });
  tearDown(() => controller.dispose());

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
    expect(catalog.search('/').length, 304);
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
      chat.draft = '/short first\nsecond';
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
      expect(chat.messages.single['display_content'], '/a-skill first\nsecond');
      expect(chat.draft, isEmpty);
      expect(chat.status, ProfileTurnStatus.running);
    },
  );

  test(
    'late skill reply submits to original owner after a profile switch',
    () async {
      final reply = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => reply.future;
      chat.draft = '/a-skill task';
      final send = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      await controller.switchProfile('b');
      final other = await controller.createChat();
      other.draft = 'Keep this draft';
      reply.complete({
        'type': 'send',
        'message': 'Expanded bundle',
        'display': '/a-skill task',
        'notice': 'Loading bundle',
      });
      await send;
      expect(controller.current!.chat, same(other));
      expect(other.draft, 'Keep this draft');
      expect(other.messages, isEmpty);
      expect(chat.commandOutput, ['Loading bundle']);
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
      chat.draft = '/a-skill needs setup';

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret.request', {
        'request_id': 'skill-secret',
        'env_var': 'FIXTURE_TOKEN',
        'prompt': 'Optional fixture token',
      });
      final request = chat.sensitivePrompt!;
      expect(chat.status, ProfileTurnStatus.attention);

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
      expect(chat.messages.single['display_content'], '/a-skill needs setup');
      expect(chat.draft, isEmpty);
      expect(chat.status, ProfileTurnStatus.running);
    },
  );

  test(
    'late secret response acknowledgement does not block the expanded skill prompt',
    () async {
      final dispatch = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => dispatch.future;
      host.sensitiveResponseDelay = Completer<void>();
      chat.draft = '/a-skill delayed cancel';

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret.request', {
        'request_id': 'delayed-secret',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.sensitivePrompt!;
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
      expect(chat.status, ProfileTurnStatus.running);
      host.sensitiveResponseDelay!.complete();
      await cancelling;
      await sending;
      expect(chat.status, ProfileTurnStatus.running);
      expect(chat.sensitivePrompt, isNull);
    },
  );

  test(
    'secret request during prompt acknowledgement remains a live turn',
    () async {
      host.respond = (_, _) async => {
        'type': 'skill',
        'message': 'Expanded prompt',
      };
      host.promptSubmitStarted = Completer<void>();
      host.promptSubmitDelay = Completer<void>();
      chat.draft = '/a-skill live prompt secret';

      final sending = controller.send(chat);
      await host.promptSubmitStarted!.future;
      host.event('a', 'secret.request', {
        'request_id': 'live-turn-secret',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.sensitivePrompt!;
      expect(chat.status, ProfileTurnStatus.attention);
      await controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: request,
      );
      expect(chat.status, ProfileTurnStatus.running);

      host.promptSubmitDelay!.complete();
      await sending;
      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(1),
      );
      expect(chat.status, ProfileTurnStatus.running);
    },
  );

  test(
    'failed preflight secret response can be retried before skill submit',
    () async {
      final dispatch = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => dispatch.future;
      host.sensitiveResponseError = TimeoutException('retry response');
      chat.draft = '/a-skill retry secret';

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret.request', {
        'request_id': 'retry-secret',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.sensitivePrompt!;
      await expectLater(
        controller.respondSensitivePrompt(chat, '', expectedRequest: request),
        throwsA(isA<TimeoutException>()),
      );
      expect(chat.status, ProfileTurnStatus.attention);
      expect(chat.sensitivePrompt, same(request));

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
      );
      expect(chat.status, ProfileTurnStatus.running);
    },
  );

  test(
    'replacement preflight request keeps the original return state',
    () async {
      final dispatch = Completer<Map<String, dynamic>>();
      host.respond = (_, _) => dispatch.future;
      chat
        ..draft = '/a-skill replacement secret'
        ..status = ProfileTurnStatus.completed;

      final sending = controller.send(chat);
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'secret.request', {
        'request_id': 'first-secret',
        'env_var': 'FIRST_TOKEN',
      });
      host.event('a', 'secret.request', {
        'request_id': 'replacement-secret',
        'env_var': 'SECOND_TOKEN',
      });
      final replacement = chat.sensitivePrompt!;
      await controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: replacement,
      );
      expect(chat.status, ProfileTurnStatus.completed);

      dispatch.complete({
        'type': 'skill',
        'message': 'Expanded after replacement secret',
      });
      await sending;
      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(1),
      );
      expect(chat.status, ProfileTurnStatus.running);
    },
  );

  test(
    'sensitive preflight expiry releases every stock request kind',
    () async {
      const cases = [
        ('sudo.request', 'sudo.expire'),
        ('secret.request', 'secret.expire'),
        ('vault.unlock.request', 'vault.unlock.expire'),
        ('vault.save_login.request', 'vault.save_login.expire'),
        ('vault.code.request', 'vault.code.expire'),
      ];

      for (var index = 0; index < cases.length; index++) {
        final dispatch = Completer<Map<String, dynamic>>();
        host.respond = (_, _) => dispatch.future;
        chat
          ..draft = '/a-skill expiring request $index'
          ..status = ProfileTurnStatus.completed;
        final sending = controller.send(chat);
        await Future<void>.delayed(Duration.zero);
        final requestId = 'expiring-$index';
        host.event('a', cases[index].$1, {'request_id': requestId});
        expect(chat.status, ProfileTurnStatus.attention);

        host.event('a', cases[index].$2, {'request_id': requestId});
        expect(chat.sensitivePrompt, isNull);
        expect(chat.status, ProfileTurnStatus.completed);
        dispatch.complete({
          'type': 'skill',
          'message': 'Expanded after expiry $index',
        });
        await sending;
        expect(chat.status, ProfileTurnStatus.running);
      }

      expect(
        host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
        hasLength(cases.length),
      );
    },
  );

  test('sensitive expiry during an active turn stays running', () async {
    chat.status = ProfileTurnStatus.running;
    host.event('a', 'secret.request', {'request_id': 'active-secret-expiry'});
    expect(chat.status, ProfileTurnStatus.attention);

    host.event('a', 'secret.expire', {'request_id': 'active-secret-expiry'});

    expect(chat.sensitivePrompt, isNull);
    expect(chat.status, ProfileTurnStatus.running);
  });

  test('duplicate taps do not execute a command twice', () async {
    final reply = Completer<Map<String, dynamic>>();
    host.respond = (_, _) => reply.future;
    chat.draft = '/custom';
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
    chat.draft = '/custom';
    await controller.send(chat);
    expect(chat.busy, isFalse);
    expect(chat.commandRunning, isFalse);
    expect(chat.commandOutput, ['Done']);
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
      chat.draft = '/undo';
      await controller.send(chat);
      expect(chat.draft, 'Edit this question');
      expect(chat.commandOutput, ['Rewound']);
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
    chat.draft = '/model provider/model';
    await controller.send(chat);
    expect(
      host.commandCalls.singleWhere((c) => c.$1 == 'slash.exec').$2['command'],
      '/model provider/model',
    );
    expect(chat.commandOutput, ['Session only', 'Model changed']);
  });

  test('timeout never retries via slash.exec or prompt.submit', () async {
    host.respond = (_, _) async => throw TimeoutException('lost reply');
    chat.draft = '/custom';
    await controller.send(chat);
    expect(chat.draft, '/custom');
    expect(chat.error, contains('uncertain'));
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
      chat.draft = '/custom';
      await controller.send(chat);
      expect(chat.error, contains('quick command failed'));
      expect(chat.draft, '/custom');
      expect(host.commandCalls.where((c) => c.$1 == 'slash.exec'), isEmpty);
    },
  );

  test('alias cycles terminate without a model request', () async {
    host.respond = (_, _) async => {'type': 'alias', 'target': 'cycle'};
    chat.draft = '/cycle';
    await controller.send(chat);
    expect(chat.error, contains('alias cycle'));
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
      chat.draft = '/btw What changed?';
      await controller.send(chat);
      expect(
        chat.sideQuestionDeliveries.single.state,
        SideQuestionDeliveryState.pending,
      );
      expect(chat.sideQuestionDeliveries.single.taskId, 'side-task-1');
      expect(chat.sideQuestionDeliveries.single.question, 'What changed?');
      await controller.switchProfile('b');
      final other = await controller.createChat();
      host.event('a', 'btw.complete', {
        'task_id': 'side-task-1',
        'question': 'What changed?',
        'text': ' Side answer ',
      });
      final delivery = chat.sideQuestionDeliveries.single;
      expect(delivery.state, SideQuestionDeliveryState.completed);
      expect(delivery.result, 'Side answer');
      expect(chat.commandOutput, ['Started /btw on the Hermes host.']);
      expect(other.commandOutput, isEmpty);
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
      chat.draft = '/btw First question';
      await controller.send(chat);
      chat.draft = '/btw Second question';
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
      chat.status = ProfileTurnStatus.running;
      chat.draft = '/bg Check the deployment';
      await controller.send(chat);

      final pending = chat.sideQuestionDeliveries.single;
      expect(pending.kind, SideQuestionDeliveryKind.backgroundTask);
      expect(pending.taskId, 'background-task-1');
      expect(pending.question, 'Check the deployment');
      expect(pending.state, SideQuestionDeliveryState.pending);
      expect(chat.status, ProfileTurnStatus.running);
      await controller.switchProfile('b');
      final other = await controller.createChat();

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
      chat.draft = '/btw Side work';
      await controller.send(chat);
      host.backgroundRespond = (params) {
        host.event('a', 'background.complete', {
          'task_id': 'shared-task',
          'text': 'Background result',
        });
        return {'task_id': 'shared-task'};
      };

      chat.draft = '/background Background work';
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
      chat.draft = '/bg Keep this command';

      await controller.send(chat);

      expect(chat.draft, '/bg Keep this command');
      expect(chat.sideQuestionDeliveries, isEmpty);
      expect(
        chat.error,
        'Hermes did not confirm the background task. '
        'Check whether it started before sending this draft again.',
      );
      expect(chat.error, isNot(contains('FormatException')));
    },
  );

  test('yolo toggles the hydrated live session while busy', () async {
    chat.status = ProfileTurnStatus.running;
    host.event('a', 'session.info', {'yolo': true});
    chat.draft = '/yolo';

    await controller.send(chat);

    expect(
      host.commandCalls.where((call) => call.$1 == 'config.set').single.$2,
      {'session_id': 'a-runtime', 'key': 'yolo', 'value': '0', 'profile': 'a'},
    );
    expect(chat.commandOutput, ['YOLO disabled for this session.']);
    expect(chat.yolo, isFalse);
    expect(chat.draft, isEmpty);
    expect(chat.status, ProfileTurnStatus.running);
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
      chat.yolo = null;
      host.yolo = '1';
      host.yoloSetResult = '1';
      chat.draft = '/yolo';

      await controller.send(chat);

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
      expect(chat.commandOutput, ['YOLO enabled for this session.']);
      expect(chat.yolo, isTrue);
    },
  );

  test('terminal commands explain requirement and preserve draft', () async {
    chat.draft = '/clear';
    await controller.send(chat);
    expect(chat.error, contains('requires the Hermes terminal'));
    expect(chat.draft, '/clear');
    expect(host.commandCalls.where((c) => c.$1 == 'command.dispatch'), isEmpty);
  });

  test(
    'interrupt while busy uses exact session and preserves turn status',
    () async {
      chat.status = ProfileTurnStatus.running;
      chat.draft = '/interrupt';
      await controller.send(chat);
      expect(
        host.commandCalls
            .singleWhere((c) => c.$1 == 'session.interrupt')
            .$2['session_id'],
        'a-runtime',
      );
      expect(chat.status, ProfileTurnStatus.running);
    },
  );

  testWidgets(
    'picker searches all skills and inserts selection without sending',
    (tester) async {
      final input = TextEditingController(text: '/a-');
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SlashCommandSuggestions(
                  controller: controller,
                  chat: chat,
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
      expect(chat.draft, '/a-skill ');
      expect(host.commandCalls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'argument completion replaces only the server range and keeps suffix',
    (tester) async {
      host.respond = (_, _) async => {
        'items': [
          {'text': 'provider/model', 'meta': 'Model'},
        ],
        'replace_from': 7,
      };
      final input = TextEditingController.fromValue(
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
              controller: controller,
              chat: chat,
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
    },
  );

  testWidgets('late completion cannot replace a newer search', (tester) async {
    final delayed = Completer<Map<String, dynamic>>();
    host.respond = (_, _) => delayed.future;
    final input = TextEditingController(text: '/model pr');
    addTearDown(input.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlashCommandSuggestions(
            controller: controller,
            chat: chat,
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
      for (var i = 0; i < 100 && chat.commandRunning; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pump();
      expect(chat.commandRunning, isFalse);
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
      expect(chat.status, ProfileTurnStatus.running);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
