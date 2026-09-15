import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/session_control.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/models/queued_prompt_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

Map<String, dynamic> _control(String revision, {String status = 'active'}) => {
  'goal': {
    'title': 'Ship mobile client',
    'status': status,
    'turns_used': 2,
    'max_turns': 8,
    'contract': {
      'outcome': 'Release',
      'verification': 'Tests pass',
      'constraints': 'Scoped',
      'boundaries': 'Android',
      'stop_when': 'Verified',
    },
    'subgoals': <String>[],
    'gates': <Object>[],
  },
  'revision': revision,
  'updated_at': 100,
};

Map<String, dynamic> _actionResponse(
  String revision, {
  String type = 'exec',
  String? message,
  String? output = 'Goal updated on the server.',
}) => {
  'control': _control(revision),
  'dispatch': {
    'type': type,
    'output': output,
    'notice': null,
    'message': message,
    'display': type == 'send' ? 'Continue goal' : null,
  },
};

class _ControlHost extends Host {
  Map<String, dynamic> readResponse = {'control': _control('read-1')};
  Map<String, dynamic> actionResponse = _actionResponse('action-1');
  Completer<Map<String, dynamic>>? pendingRead;
  Completer<Map<String, dynamic>>? pendingAction;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return gateways[scope.profileName] = ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      close: base.close,
      get: base.read,
      rpc: (method, params) {
        if (method == 'session.control.read' || method == 'session.control') {
          calls.add((scope.profileName, method, params));
          return method == 'session.control.read'
              ? pendingRead?.future ?? Future.value(readResponse)
              : pendingAction?.future ?? Future.value(actionResponse);
        }
        return base.call(method, params);
      },
    );
  }
}

void main() {
  late _ControlHost host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = _ControlHost();
    controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'session-control-test',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat();
  });

  tearDown(() => controller.dispose());

  test(
    'ready event hydrates once and a newer event wins a late read',
    () async {
      host.event('a', 'session.info');
      await Future<void>.delayed(Duration.zero);
      host.event('a', 'session.info');
      await Future<void>.delayed(Duration.zero);
      expect(
        host.calls.where((call) => call.$2 == 'session.control.read'),
        hasLength(1),
      );

      host.pendingRead = Completer<Map<String, dynamic>>();
      final refresh = controller.refreshSessionControl(chat);
      host.event('a', 'session.control.update', {
        'control': _control('event-new'),
      });
      host.pendingRead!.complete({'control': _control('read-old')});
      await refresh;
      expect(chat.sessionControl!.revision, 'event-new');
    },
  );

  test(
    'action rejects a stale continuation and accepts the same event revision',
    () async {
      host.pendingAction = Completer<Map<String, dynamic>>();
      final action = controller.controlSession(
        chat,
        SessionControlAction.goalPause,
      );
      host.event('a', 'session.control.update', {
        'control': _control('event-new', status: 'paused'),
      });
      host.pendingAction!.complete(
        _actionResponse(
          'response-old',
          type: 'send',
          message: 'Continue stale goal',
          output: null,
        ),
      );
      expect(await action, isFalse);
      expect(chat.sessionControl!.revision, 'event-new');
      expect(chat.sessionControlError, contains('state changed'));
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);

      host.pendingAction = Completer<Map<String, dynamic>>();
      final same = controller.controlSession(
        chat,
        SessionControlAction.goalResume,
      );
      host.event('a', 'session.control.update', {
        'control': _control('shared'),
      });
      host.pendingAction!.complete(_actionResponse('shared'));
      expect(await same, isTrue);
      expect(chat.sessionControl!.revision, 'shared');
      expect(chat.sessionControlNotice, 'Goal updated on the server.');
      expect(host.calls.last.$3, {
        'session_id': 'a-runtime',
        'action': 'goal.resume',
        'args': <String, dynamic>{},
        'profile': 'a',
      });
    },
  );

  test(
    'continuation preserves composer state and reports partial failure',
    () async {
      await controller.updateDraft(chat, 'Unrelated draft');
      final attachment = AttachmentDraft(
        id: 'file',
        cachedPath: 'unused',
        name: 'notes.txt',
        byteLength: 1,
        mediaType: 'text/plain',
        kind: AttachmentDraftKind.genericFile,
      );
      chat.attachments.add(attachment);
      chat.queuedPrompts.add(QueuedPromptDraft(text: 'Later prompt'));
      host.actionResponse = _actionResponse(
        'continued',
        type: 'send',
        message: 'Continue the goal',
        output: null,
      );

      expect(
        await controller.controlSession(chat, SessionControlAction.goalResume),
        isTrue,
      );
      expect(chat.draft, 'Unrelated draft');
      expect(chat.attachments, [attachment]);
      expect(chat.queuedPrompts.single.text, 'Later prompt');
      expect(host.calls.where((call) => call.$2 == 'file.attach'), isEmpty);

      chat.status = ProfileTurnStatus.running;
      host.actionResponse = _actionResponse(
        'changed-without-send',
        type: 'send',
        message: 'Continue again',
        output: null,
      );
      expect(
        await controller.controlSession(chat, SessionControlAction.goalResume),
        isFalse,
      );
      expect(chat.sessionControl!.revision, 'changed-without-send');
      expect(
        chat.sessionControlError,
        contains('continuation was not accepted'),
      );
      expect(chat.draft, 'Unrelated draft');
    },
  );

  test('subgoal actions send their exact manager arguments', () async {
    expect(
      await controller.controlSession(
        chat,
        SessionControlAction.subgoalAdd,
        args: {'text': 'Verify hydration'},
      ),
      isTrue,
    );
    expect(host.calls.last.$3, {
      'session_id': 'a-runtime',
      'action': 'subgoal.add',
      'args': {'text': 'Verify hydration'},
      'profile': 'a',
    });

    host.actionResponse = _actionResponse('removed');
    expect(
      await controller.controlSession(
        chat,
        SessionControlAction.subgoalRemove,
        args: {'index': 1},
      ),
      isTrue,
    );
    expect(host.calls.last.$3, {
      'session_id': 'a-runtime',
      'action': 'subgoal.remove',
      'args': {'index': 1},
      'profile': 'a',
    });

    host.actionResponse = _actionResponse('cleared');
    expect(
      await controller.controlSession(chat, SessionControlAction.subgoalClear),
      isTrue,
    );
    expect(host.calls.last.$3, {
      'session_id': 'a-runtime',
      'action': 'subgoal.clear',
      'args': <String, dynamic>{},
      'profile': 'a',
    });
  });

  test(
    'duplicate and stale actions fail closed without changing ownership',
    () async {
      host.pendingAction = Completer<Map<String, dynamic>>();
      final first = controller.controlSession(
        chat,
        SessionControlAction.goalClear,
      );
      expect(
        await controller.controlSession(chat, SessionControlAction.goalClear),
        isFalse,
      );
      await controller.switchProfile('b');
      host.pendingAction!.complete(_actionResponse('scoped'));
      expect(await first, isTrue);
      expect(
        host.calls.where((call) => call.$2 == 'session.control').last.$1,
        'a',
      );

      host.pendingAction = Completer<Map<String, dynamic>>();
      final stale = controller.controlSession(
        chat,
        SessionControlAction.goalUnwait,
      );
      chat.runtimeId = 'replacement-runtime';
      host.pendingAction!.complete(_actionResponse('stale'));
      expect(await stale, isFalse);
    },
  );

  test(
    'malformed dispatch does not claim the server action succeeded',
    () async {
      host.actionResponse = {
        'control': _control('changed'),
        'dispatch': {'type': 'exec'},
      };

      expect(
        await controller.controlSession(chat, SessionControlAction.goalPause),
        isFalse,
      );
      expect(chat.sessionControl, isNull);
      expect(chat.sessionControlError, contains('Refresh'));
    },
  );
}
