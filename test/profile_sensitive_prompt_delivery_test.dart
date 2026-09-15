import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_workspace_controller_test.dart' show Host;

class SensitivePromptHost extends Host {
  Completer<void>? responseDelay;
  Object? responseError;
  String? resumedRuntime;
  Object? openRequests = const [];
  bool includeOpenRequests = true;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    final wrapped = ProfileGateway(
      scope: scope,
      discover: discover,
      connect: base.connect,
      close: base.close,
      get: base.read,
      rpc: (method, params) async {
        final response = base.call(method, params);
        if (method == 'request.answer') {
          await responseDelay?.future;
          final error = responseError;
          if (error != null) throw error;
        }
        final result = await response;
        if (method == 'session.resume' && resumedRuntime != null) {
          return {
            ...result,
            'session_id': resumedRuntime,
            if (includeOpenRequests) 'open_requests': openRequests,
          };
        }
        if (method == 'session.resume') {
          return {
            ...result,
            if (includeOpenRequests) 'open_requests': openRequests,
          };
        }
        return result;
      },
    );
    gateways[scope.profileName] = wrapped;
    return wrapped;
  }
}

void main() {
  late SensitivePromptHost host;
  late ProfileWorkspaceController controller;
  late SharedPreferences preferences;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    host = SensitivePromptHost();
    controller = ProfileWorkspaceController(
      connectionIdentity: 'sensitive-prompt-test',
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      preferences: preferences,
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  test(
    'routes sudo and secret responses through their exact profile owner',
    () async {
      chat.draft = 'composer marker';
      const cases = [
        (
          event: 'sudo',
          id: 'sudo-1',
          method: 'request.answer',
          field: 'password',
        ),
        (
          event: 'secret',
          id: 'secret-1',
          method: 'request.answer',
          field: 'value',
        ),
      ];

      for (final value in cases) {
        host.event('a', value.event, {
          'request_id': value.id,
          'env_var': 'FIXTURE_TOKEN',
          'prompt': 'Enter the fixture token',
        });
        final request = chat.sensitivePrompt!;

        await controller.respondSensitivePrompt(
          chat,
          'synthetic-secret',
          expectedRequest: request,
        );

        expect(host.calls.last.$2, value.method);
        expect(host.calls.last.$3, {
          'id': value.id,
          'result': {'value': 'synthetic-secret'},
          'profile': 'a',
        });
        expect(chat.sensitivePrompt, isNull);
      }

      expect(chat.draft, 'composer marker');
      expect(chat.messages.toString(), isNot(contains('synthetic-secret')));
      expect(chat.error, isNull);
      expect(
        [
          for (final key in preferences.getKeys()) preferences.get(key),
        ].toString(),
        isNot(contains('synthetic-secret')),
      );
    },
  );

  test('cancel sends the official empty value', () async {
    host.event('a', 'secret', {
      'request_id': 'secret-cancel',
      'env_var': 'FIXTURE_TOKEN',
    });
    final request = chat.sensitivePrompt!;

    await controller.respondSensitivePrompt(chat, '', expectedRequest: request);

    expect(host.calls.last.$3, {
      'id': 'secret-cancel',
      'result': {'value': ''},
      'profile': 'a',
    });
  });

  test(
    'routes the three vault response contracts and normalizes codes',
    () async {
      final login = jsonEncode({
        'identifier': 'person@example.test',
        'password': 'synthetic-password',
      });
      final cases = [
        (
          event: 'vault.unlock_prompt',
          data: <String, dynamic>{
            'request_id': 'unlock-1',
            'backend': 'onepassword',
            'display_name': '1Password',
          },
          method: 'request.answer',
          field: 'password',
          input: 'synthetic-password',
          output: 'synthetic-password',
        ),
        (
          event: 'vault.code',
          data: <String, dynamic>{
            'request_id': 'code-1',
            'site': 'Example',
            'hint': 'Authenticator code',
          },
          method: 'request.answer',
          field: 'code',
          input: '123 456-78',
          output: '12345678',
        ),
        (
          event: 'vault.save_login',
          data: <String, dynamic>{
            'request_id': 'save-1',
            'origin': 'https://example.test',
            'site': 'Example',
          },
          method: 'request.answer',
          field: 'login',
          input: login,
          output: login,
        ),
      ];

      for (final value in cases) {
        host.event('a', value.event, value.data);
        final request = chat.sensitivePrompt!;

        await controller.respondSensitivePrompt(
          chat,
          value.input,
          expectedRequest: request,
        );

        expect(host.calls.last.$2, value.method);
        expect(host.calls.last.$3, {
          'id': value.data['request_id'],
          'result': {'value': value.output},
          'profile': 'a',
        });
      }

      expect(chat.messages.toString(), isNot(contains('synthetic-password')));
      expect(
        [
          for (final key in preferences.getKeys()) preferences.get(key),
        ].toString(),
        isNot(contains('synthetic-password')),
      );
    },
  );

  test('vault cancel values are explicit empty strings', () async {
    const cases = [
      (
        event: 'vault.unlock_prompt',
        method: 'request.answer',
        field: 'password',
      ),
      (event: 'vault.code', method: 'request.answer', field: 'code'),
      (event: 'vault.save_login', method: 'request.answer', field: 'login'),
    ];

    for (final value in cases) {
      host.event('a', value.event, {'request_id': value.event});
      final request = chat.sensitivePrompt!;
      await controller.respondSensitivePrompt(
        chat,
        '',
        expectedRequest: request,
      );

      expect(host.calls.last.$2, value.method);
      expect(host.calls.last.$3['result'], {'value': ''});
    }
  });

  test('vault expiry clears only its matching request ID and kind', () {
    host.event('a', 'vault.code', {
      'request_id': 'current-code',
      'site': 'Example',
    });

    host.event('a', 'request.cancel', {
      'id': 'older-code',
      'method': 'vault.code',
      'reason': 'timeout',
    });
    expect(chat.sensitivePrompt?.requestId, 'current-code');

    host.event('a', 'request.cancel', {
      'id': 'current-code',
      'method': 'vault.unlock_prompt',
      'reason': 'timeout',
    });
    expect(chat.sensitivePrompt?.requestId, 'current-code');

    host.event('a', 'request.cancel', {
      'id': 'current-code',
      'method': 'vault.code',
      'reason': 'timeout',
    });
    expect(chat.sensitivePrompt, isNull);
    expect(chat.sensitivePromptResponding, isFalse);
  });

  test('an older response cannot clear a newer pending request', () async {
    host.responseDelay = Completer<void>();
    host.event('a', 'sudo', {'request_id': 'old'});
    final old = chat.sensitivePrompt!;
    final response = controller.respondSensitivePrompt(
      chat,
      'synthetic-password',
      expectedRequest: old,
    );
    await Future<void>.delayed(Duration.zero);

    host.event('a', 'secret', {'request_id': 'new', 'env_var': 'NEW_TOKEN'});
    host.responseDelay!.complete();
    await response;

    expect(chat.sensitivePrompt?.requestId, 'new');
    expect(chat.sensitivePromptResponding, isFalse);
  });

  test('disconnect retains metadata but disables response state', () {
    host.event('a', 'sudo', {'request_id': 'waiting'});

    host.gateways['a']!.onConnectionChanged!(false);

    expect(chat.sensitivePrompt?.requestId, 'waiting');
    expect(chat.sensitivePromptResponding, isFalse);
    expect(chat.status, ProfileTurnStatus.reconnecting);
  });

  test(
    'resume restores a secure form from open_requests for its runtime',
    () async {
      host.openRequests = [
        {
          'id': 'foreign',
          'method': 'secret',
          'params': {'session_id': 'other-runtime', 'env_var': 'WRONG_TOKEN'},
        },
        {
          'id': 'recovered-secret',
          'method': 'secret',
          'params': {
            'session_id': chat.runtimeId,
            'env_var': 'FIXTURE_TOKEN',
            'prompt': 'Enter the fixture token',
          },
        },
      ];
      await controller.reconnect(chat.key.workspace);
      expect(chat.sensitivePrompt?.requestId, 'recovered-secret');
      expect(chat.sensitivePrompt?.title, 'FIXTURE_TOKEN');
      expect(chat.status, ProfileTurnStatus.attention);
      host.openRequests = [];
      await controller.reconnect(chat.key.workspace);
      expect(chat.sensitivePrompt, isNull);
    },
  );

  test(
    'a changed runtime cannot restore another runtime secure request',
    () async {
      host.event('a', 'sudo', {'request_id': 'old'});
      host.openRequests = [
        {
          'id': 'old',
          'method': 'sudo',
          'params': {'session_id': chat.runtimeId},
        },
      ];
      host.resumedRuntime = 'new-runtime';
      await controller.reconnect(chat.key.workspace);
      expect(chat.sensitivePrompt, isNull);
    },
  );

  test('partial session info retains a live secure request', () {
    host.event('a', 'secret', {'request_id': 'live'});
    host.event('a', 'session.info', {'model': 'fixture-model'});
    expect(chat.sensitivePrompt?.requestId, 'live');
  });

  test('a snapshot during secure submission cannot strand the form', () async {
    host.event('a', 'secret', {'request_id': 'answering'});
    host.responseDelay = Completer<void>();
    final response = controller.respondSensitivePrompt(
      chat,
      'synthetic-secret',
      expectedRequest: chat.sensitivePrompt!,
    );
    host.event('a', 'session.info', {
      'open_requests': [
        {
          'id': 'answering',
          'method': 'secret',
          'params': {'session_id': chat.runtimeId},
        },
      ],
    });
    host.responseDelay!.complete();
    await response;
    expect(chat.sensitivePrompt, isNull);
    expect(chat.sensitivePromptResponding, isFalse);
  });

  test(
    'session info updates open requests without resetting an in-flight answer',
    () {
      Map<String, dynamic> snapshot(String site) => {
        'open_requests': [
          {
            'id': 'code',
            'method': 'vault.code',
            'params': {'session_id': chat.runtimeId, 'site': site},
          },
        ],
      };
      host.event('a', 'session.info', snapshot('Example'));
      expect(chat.sensitivePrompt?.requestId, 'code');
      chat.sensitivePromptResponding = true;
      host.event('a', 'session.info', snapshot('Updated Example'));
      expect(chat.sensitivePromptResponding, isTrue);
      host.event('a', 'session.info', {'open_requests': [], 'running': false});
      expect(chat.sensitivePrompt, isNull);
      expect(chat.sensitivePromptResponding, isFalse);
      expect(chat.status, ProfileTurnStatus.completed);
    },
  );

  test(
    'secure response data in snapshots is rejected without persisting it',
    () async {
      host.openRequests = [
        {
          'id': 'bad',
          'method': 'secret',
          'params': {
            'session_id': chat.runtimeId,
            'value': 'synthetic-secret-must-not-persist',
          },
        },
      ];
      await controller.reconnect(chat.key.workspace);
      expect(chat.sensitivePrompt, isNull);
      expect(
        [
          for (final key in preferences.getKeys()) preferences.get(key),
        ].toString(),
        isNot(contains('synthetic-secret-must-not-persist')),
      );
    },
  );

  test(
    'an expired server request clears the secure form without retrying',
    () async {
      host.clarifyResult = {'status': 'expired'};
      host.event('a', 'secret', {
        'request_id': 'expired',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.sensitivePrompt!;

      await controller.respondSensitivePrompt(
        chat,
        'synthetic-secret',
        expectedRequest: request,
      );

      expect(chat.sensitivePrompt, isNull);
      expect(chat.sensitivePromptResponding, isFalse);
    },
  );

  test(
    'a transport failure retains metadata without storing its error',
    () async {
      host.responseError = StateError('server echoed synthetic-secret');
      host.event('a', 'secret', {
        'request_id': 'retry',
        'env_var': 'FIXTURE_TOKEN',
      });
      final request = chat.sensitivePrompt!;

      await expectLater(
        controller.respondSensitivePrompt(
          chat,
          'synthetic-secret',
          expectedRequest: request,
        ),
        throwsStateError,
      );

      expect(chat.sensitivePrompt, same(request));
      expect(chat.sensitivePromptResponding, isFalse);
      expect(chat.error, isNull);
      expect(chat.messages.toString(), isNot(contains('synthetic-secret')));
    },
  );
}
