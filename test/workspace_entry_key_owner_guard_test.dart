import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/architecture/model.dart';
import '../tools/architecture/rules/workspace_entry_key_owner.dart' as rule;

void main() {
  test('remembered entry key belongs to shared app preferences', () async {
    final snapshot = Snapshot.load(
      Directory.current.path,
      'tools/architecture/roles.json',
    );
    expect(await rule.check(snapshot), isEmpty);
  });
  test(
    'key ownership fixtures and CLI exits pass',
    () async {
      final result = await Process.run('dart', [
        'run',
        'tools/architecture/tests/workspace_entry_key_owner_test.dart',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
