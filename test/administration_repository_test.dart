import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'support/administration_fixture.dart';

void main() {
  test(
    'two servers and profiles retain separate reads and sparse writes',
    () async {
      final a = AdministrationFixture('A');
      final b = AdministrationFixture('B');
      final personalA = a.server.profile('personal');
      final workA = a.server.profile('work');
      final personalB = b.server.profile('personal');
      await personalA.saveSettings({'memory.memory_char_limit': 2500});
      await workA.saveSettings({'memory.memory_enabled': true});
      await personalB.saveSettings({'memory.memory_char_limit': 4000});
      expect(setting(a.configs['personal']!, 'memory.memory_char_limit'), 2500);
      expect(setting(a.configs['work']!, 'memory.memory_char_limit'), 3000);
      expect(setting(b.configs['personal']!, 'memory.memory_char_limit'), 4000);
      expect(setting(b.configs['work']!, 'memory.memory_enabled'), false);
      expect(a.configs['personal']!['unrelated'], {'keep': true});
      final write = a.requests.firstWhere((r) => r.$1 == 'PUT');
      expect(write.$3, {'profile': 'personal'});
      expect(write.$4, {
        'profile': 'personal',
        'config': {
          'memory': {'memory_char_limit': 2500},
        },
      });
    },
  );

  test(
    'request callers cannot override captured profile in query or body',
    () async {
      final f = AdministrationFixture();
      final p = f.server.profile('work');
      await p.read('config', {'profile': 'default'});
      f.override = (method, path, query, body) async {
        if (path == 'profiles') {
          return {
            'profiles': [
              {'name': 'work'},
            ],
          };
        }
        if (path == 'profiles/active') {
          return {'current': 'work', 'active': 'work'};
        }
        return {'ok': true};
      };
      await p.write('DELETE', 'learning/node', {
        'profile': 'default',
        'id': 'local-skill',
      });
      final read = f.requests.first;
      final write = f.requests.last;
      expect(read.$3['profile'], 'work');
      expect(write.$3['profile'], 'work');
      expect(write.$4?['profile'], 'work');
    },
  );

  test(
    'a vanished profile prevents the mutation without changing another profile',
    () async {
      final f = AdministrationFixture();
      final p = f.server.profile('work');
      f.configs.remove('work');
      await expectLater(
        p.saveSettings({'memory.memory_enabled': true}),
        throwsA(isA<AdministrationFailure>()),
      );
      expect(f.requests.where((r) => r.$1 != 'GET'), isEmpty);
    },
  );

  test(
    'rejected writes and mismatched readback cannot become success',
    () async {
      final f = AdministrationFixture()..reject = true;
      final p = f.server.profile('personal');
      await expectLater(
        p.saveSettings({'memory.memory_char_limit': 9999}),
        throwsA(isA<AdministrationFailure>()),
      );
      f.reject = false;
      f.ignoreSave = true;
      await expectLater(
        p.saveSettings({'memory.memory_char_limit': 9999}),
        throwsA(isA<AdministrationFailure>()),
      );
      expect(setting(f.configs['personal']!, 'memory.memory_char_limit'), 2000);
    },
  );

  test('same-name background actions must match the returned PID', () async {
    final f = AdministrationFixture();
    f.override = (_, _, _, _) async => {
      'pid': 222,
      'running': false,
      'exit_code': 0,
    };
    const action = AdministrationAction('skills-update', 111);
    await expectLater(
      action.status(f.server),
      throwsA(isA<AdministrationFailure>()),
    );
    f.override = (_, _, _, _) async => {
      'pid': 111,
      'running': false,
      'exit_code': 1,
    };
    expect((await action.status(f.server))['exit_code'], 1);
  });

  test('uncertain start is not an invented tracked operation', () {
    expect(
      () => AdministrationAction.fromJson({'ok': true}),
      throwsA(isA<AdministrationFailure>()),
    );
    expect(
      () => AdministrationFixture().server.profile('current'),
      throwsArgumentError,
    );
    expect(
      () => AdministrationFixture().server.profile('../work'),
      throwsArgumentError,
    );
  });

  test(
    'server lifecycle writes never acquire selected-profile query/body',
    () async {
      final f = AdministrationFixture();
      f.override = (_, _, _, _) async => {'ok': true};
      await f.server.write('PATCH', 'profiles/work', {'new_name': 'research'});
      expect(f.requests.single.$3, isEmpty);
      expect(f.requests.single.$4, {'new_name': 'research'});
    },
  );
}
