import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/backend_update.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/backend_update_controller.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';

const _available = <String, dynamic>{
  'current_version': '1.2.3',
  'install_method': 'pipx',
  'behind': 2,
  'update_available': true,
  'can_apply': true,
};

class _UpdateHost {
  Map<String, dynamic> checkResponse = _available;
  Map<String, dynamic> statusResponse = {
    'name': 'hermes-update',
    'running': true,
    'pid': 41,
    'exit_code': null,
    'lines': <String>[],
  };
  Map<String, dynamic> postResponse = {
    'ok': true,
    'name': 'hermes-update',
    'pid': 41,
    'action_id': 'action-1',
  };
  Map<String, dynamic> receiptResponse = {
    'receipt': {
      'outcome': 'success',
      'pid': 41,
      'finished_at': '2026-09-12T12:00:00Z',
    },
    'summary': {'outcome': 'success'},
  };
  Completer<Map<String, dynamic>>? pendingPost;
  Completer<Map<String, dynamic>>? pendingStatus;
  bool postFails = false;
  final reads = <(String, Map<String, String>)>[];
  final posts = <(String, Map<String, dynamic>)>[];

  late final gateway = ProfileGateway(
    scope: WorkspaceScope(connectionId: 'host', profileName: 'work'),
    get: (endpoint, query) async {
      reads.add((endpoint, query));
      return switch (endpoint) {
        'hermes/update/check' => checkResponse,
        'hermes/update/receipt' => receiptResponse,
        _ => pendingStatus?.future ?? statusResponse,
      };
    },
    post: (endpoint, body) async {
      posts.add((endpoint, body));
      if (postFails) throw TimeoutException('lost acknowledgement');
      return pendingPost?.future ?? postResponse;
    },
    rpc: (_, _) async => <String, dynamic>{},
    discover: () async => const ProfileDiscovery(
      profiles: [],
      currentName: null,
      activeName: null,
    ),
  );
}

Future<BackendUpdateController> _started(_UpdateHost host) async {
  final controller = BackendUpdateController(host.gateway);
  expect(await controller.startUpdate(), isTrue);
  return controller;
}

void main() {
  test('start rechecks eligibility and targets the captured profile', () async {
    final host = _UpdateHost();
    final controller = BackendUpdateController(host.gateway);
    addTearDown(controller.dispose);

    await controller.checkForUpdate();
    expect(controller.check!.canStart, isTrue);
    expect(await controller.startUpdate(), isTrue);
    expect(controller.phase, BackendUpdatePhase.running);
    expect(
      host.reads.where((call) => call.$1 == 'hermes/update/check'),
      hasLength(2),
    );
    for (final call in host.reads) {
      expect(call.$2, {'force': 'true', 'profile': 'work'});
    }
    expect(host.posts, hasLength(1));
    expect(host.posts.single.$1, 'hermes/update?profile=work');
    expect(host.posts.single.$2, isEmpty);
  });

  test('fresh eligibility can refuse a previously advertised update', () async {
    final host = _UpdateHost();
    final controller = BackendUpdateController(host.gateway);
    addTearDown(controller.dispose);
    await controller.checkForUpdate();
    host.checkResponse = {..._available, 'update_available': false};

    expect(await controller.startUpdate(), isFalse);
    expect(controller.phase, BackendUpdatePhase.refused);
    expect(host.posts, isEmpty);
  });

  test('already running acknowledgement is tracked', () async {
    final host = _UpdateHost()
      ..postResponse = {
        'ok': true,
        'name': 'hermes-update',
        'pid': 41,
        'action_id': 'existing-action',
        'already_running': true,
      };
    final controller = BackendUpdateController(host.gateway);
    addTearDown(controller.dispose);

    expect(await controller.startUpdate(), isTrue);
    expect(controller.phase, BackendUpdatePhase.running);
    expect(controller.requestOutstanding, isTrue);
    expect(controller.message, contains('already running'));
    await controller.checkForUpdate();
    expect(host.reads, hasLength(1));
    expect(controller.phase, BackendUpdatePhase.running);
  });

  test('explicit refusal is not presented as success', () async {
    final host = _UpdateHost()
      ..postResponse = {'ok': false, 'message': 'private backend detail'};
    final controller = BackendUpdateController(host.gateway);
    addTearDown(controller.dispose);

    expect(await controller.startUpdate(), isFalse);
    expect(controller.phase, BackendUpdatePhase.refused);
    expect(controller.requestOutstanding, isFalse);
    expect(controller.message, isNot(contains('private backend detail')));
  });

  test('correlated action status proves terminal outcomes', () async {
    final host = _UpdateHost();
    final controller = await _started(host);
    addTearDown(controller.dispose);

    host.statusResponse = {
      'name': 'hermes-update',
      'running': false,
      'pid': 41,
      'exit_code': 0,
      'lines': <String>[],
      'action_id': 'action-1',
    };
    host.receiptResponse = {
      ...host.receiptResponse,
      'receipt': {
        ...host.receiptResponse['receipt'] as Map,
        'outcome': 'partial',
      },
    };
    await controller.refreshStatus();
    expect(controller.phase, BackendUpdatePhase.partial);
    expect(host.reads.last.$1, 'hermes/update/receipt');
    expect(host.reads.last.$2, {'profile': 'work'});

    host.receiptResponse = {
      ...host.receiptResponse,
      'receipt': {
        ...host.receiptResponse['receipt'] as Map,
        'outcome': 'refused',
      },
    };
    await controller.refreshStatus();
    expect(controller.phase, BackendUpdatePhase.refused);

    host.statusResponse = {...host.statusResponse, 'exit_code': 1};
    host.receiptResponse = {
      ...host.receiptResponse,
      'receipt': {
        ...host.receiptResponse['receipt'] as Map,
        'outcome': 'failed',
      },
    };
    await controller.refreshStatus();
    expect(controller.phase, BackendUpdatePhase.failed);

    host.statusResponse = {...host.statusResponse, 'exit_code': 0};
    host.receiptResponse = {
      ...host.receiptResponse,
      'receipt': {
        ...host.receiptResponse['receipt'] as Map,
        'outcome': 'success',
      },
    };
    await controller.refreshStatus();
    expect(controller.phase, BackendUpdatePhase.succeeded);
  });

  test(
    'same process exit stays conservative and old receipt cannot confirm',
    () async {
      final host = _UpdateHost();
      final controller = await _started(host);
      addTearDown(controller.dispose);

      host.statusResponse = {
        'name': 'hermes-update',
        'running': true,
        'pid': 41,
        'exit_code': null,
        'lines': <String>[],
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.running);

      host.statusResponse = {
        'name': 'hermes-update',
        'running': true,
        'pid': 41,
        'exit_code': null,
        'lines': <String>[],
        'action_id': 'old-action',
        'receipt': {'outcome': 'success'},
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.unknown);

      host.statusResponse = {
        'name': 'hermes-update',
        'running': false,
        'pid': null,
        'exit_code': null,
        'lines': <String>[],
        'action_id': 'action-1',
      };
      host.receiptResponse = {
        'receipt': {
          'outcome': 'success',
          'pid': 99,
          'finished_at': '2026-09-12T11:00:00Z',
        },
        'summary': {'outcome': 'success'},
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.unknown);
      expect(controller.requestOutstanding, isFalse);

      host.statusResponse = {
        'name': 'hermes-update',
        'running': false,
        'pid': 41,
        'exit_code': 0,
        'lines': <String>[],
        'receipt': {'outcome': 'failed'},
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.unknown);
      expect(controller.message, contains('command exited successfully'));
      expect(controller.requestOutstanding, isFalse);

      host.statusResponse = {
        'name': 'hermes-update',
        'running': false,
        'pid': 41,
        'exit_code': 0,
        'lines': <String>[],
        'action_id': 'old-action',
        'receipt': {'outcome': 'success'},
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.unknown);
      expect(controller.message, contains('different update'));
    },
  );

  test(
    'a status read started before a new request cannot overwrite it',
    () async {
      final host = _UpdateHost();
      final controller = await _started(host);
      addTearDown(controller.dispose);

      host.statusResponse = {
        'running': false,
        'pid': 41,
        'exit_code': 0,
        'lines': <String>[],
        'action_id': 'action-1',
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.succeeded);

      final oldStatus = host.pendingStatus = Completer<Map<String, dynamic>>();
      final pendingRefresh = controller.refreshStatus();
      await Future<void>.delayed(Duration.zero);
      expect(controller.statusLoading, isTrue);

      host
        ..postResponse = {
          'ok': true,
          'name': 'hermes-update',
          'pid': 42,
          'action_id': 'action-2',
        }
        ..pendingStatus = null;
      expect(await controller.startUpdate(), isTrue);
      expect(controller.phase, BackendUpdatePhase.running);
      expect(controller.statusLoading, isFalse);

      oldStatus.complete({
        'running': false,
        'pid': 41,
        'exit_code': 1,
        'lines': <String>[],
        'action_id': 'action-1',
      });
      await pendingRefresh;
      expect(controller.phase, BackendUpdatePhase.running);
      expect(controller.message, contains('started'));
      expect(controller.requestOutstanding, isTrue);
    },
  );

  test(
    'malformed acknowledgement stays unknown and blocks another post',
    () async {
      final host = _UpdateHost()
        ..postResponse = {
          'name': 'hermes-update',
          'pid': 41,
          'action_id': 'action-1',
        };
      final controller = BackendUpdateController(host.gateway);
      addTearDown(controller.dispose);

      expect(await controller.startUpdate(), isFalse);
      expect(controller.phase, BackendUpdatePhase.unknown);
      expect(controller.requestOutstanding, isTrue);
      expect(await controller.startUpdate(), isFalse);
      expect(host.posts, hasLength(1));

      final wrongHost = _UpdateHost()
        ..postResponse = {
          'ok': true,
          'name': 'update',
          'pid': 41,
          'action_id': 'action-1',
        };
      final wrongController = BackendUpdateController(wrongHost.gateway);
      addTearDown(wrongController.dispose);
      expect(await wrongController.startUpdate(), isFalse);
      expect(wrongController.phase, BackendUpdatePhase.unknown);
      expect(wrongController.requestOutstanding, isTrue);

      final missingIdentityHost = _UpdateHost()
        ..postResponse = {'ok': true, 'name': 'hermes-update', 'pid': 41};
      final missingIdentityController = BackendUpdateController(
        missingIdentityHost.gateway,
      );
      addTearDown(missingIdentityController.dispose);
      expect(await missingIdentityController.startUpdate(), isFalse);
      expect(missingIdentityController.phase, BackendUpdatePhase.unknown);
      expect(missingIdentityController.requestOutstanding, isTrue);
    },
  );

  test(
    'lost acknowledgement is unknown and is not retried automatically',
    () async {
      final host = _UpdateHost()..postFails = true;
      final controller = BackendUpdateController(host.gateway);
      addTearDown(controller.dispose);

      expect(await controller.startUpdate(), isFalse);
      expect(controller.phase, BackendUpdatePhase.unknown);
      expect(controller.message, contains('could not be confirmed'));
      expect(host.posts, hasLength(1));

      host.statusResponse = {
        'running': false,
        'pid': null,
        'exit_code': null,
        'lines': <String>[],
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.unknown);
      expect(controller.requestOutstanding, isTrue);
      expect(controller.message, contains('still unconfirmed'));
    },
  );

  test('fresh controller reports the last completed server update', () async {
    final host = _UpdateHost()
      ..statusResponse = {
        'running': false,
        'pid': 41,
        'exit_code': 0,
        'lines': <String>[],
        'action_id': 'old-action',
      }
      ..receiptResponse = {
        'receipt': {
          'outcome': 'partial',
          'pid': 41,
          'finished_at': '2026-09-12T12:00:00Z',
        },
        'summary': {'outcome': 'partial'},
      };
    final controller = BackendUpdateController(host.gateway);
    addTearDown(controller.dispose);

    await controller.refreshStatus();
    expect(controller.phase, BackendUpdatePhase.partial);
    expect(
      controller.message,
      'Last recorded update completed only partially.',
    );
    expect(host.reads.last.$1, 'hermes/update/receipt');
  });

  test(
    'observed host update blocks starts until it becomes terminal',
    () async {
      final host = _UpdateHost();
      final controller = BackendUpdateController(host.gateway);
      addTearDown(controller.dispose);

      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.running);
      expect(controller.requestOutstanding, isFalse);
      expect(controller.canStart, isFalse);
      expect(await controller.startUpdate(), isFalse);
      await controller.checkForUpdate();
      expect(host.posts, isEmpty);
      expect(host.reads, hasLength(1));

      host.statusResponse = {
        'running': false,
        'pid': 41,
        'exit_code': 0,
        'lines': <String>[],
        'action_id': 'old-action',
      };
      await controller.refreshStatus();
      expect(controller.phase, BackendUpdatePhase.succeeded);
      expect(controller.message, startsWith('Last recorded update'));

      await controller.checkForUpdate();
      expect(controller.canStart, isTrue);
    },
  );

  test('same-process completion uses a matching full receipt', () async {
    final host = _UpdateHost();
    final controller = await _started(host);
    addTearDown(controller.dispose);
    host
      ..statusResponse = {
        'running': false,
        'pid': 41,
        'exit_code': 1,
        'lines': <String>[],
      }
      ..receiptResponse = {
        'receipt': {
          'outcome': 'partial',
          'pid': 41,
          'finished_at': '2026-09-12T12:00:00Z',
        },
      };

    await controller.refreshStatus();
    expect(controller.phase, BackendUpdatePhase.partial);
    expect(controller.requestOutstanding, isFalse);
  });

  test('duplicate start and disposed completion are ignored', () async {
    final host = _UpdateHost();
    final pending = host.pendingPost = Completer<Map<String, dynamic>>();
    final controller = BackendUpdateController(host.gateway);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final first = controller.startUpdate();
    await Future<void>.delayed(Duration.zero);
    expect(await controller.startUpdate(), isFalse);
    expect(host.posts, hasLength(1));
    controller.dispose();
    final before = notifications;
    pending.complete(host.postResponse);
    expect(await first, isFalse);
    expect(notifications, before);
  });
}
