import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'visibility storage key derivation stays in its preference owner',
    () async {
      final result = await Process.run('dart', [
        'run',
        'tools/architecture/tests/visibility_key_owner_test.dart',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'actual production visibility key guard passes',
    () async {
      final result = await Process.run('dart', [
        'run',
        'tools/architecture/rules/visibility_key_owner.dart',
        '--json',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('"findings":[]'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
