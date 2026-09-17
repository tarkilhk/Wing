import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/doctor_diagnostic.dart';

void main() {
  final divider = '─' * 60;
  test(
    'extracts the final report, removing terminal colors and indentation',
    () {
      expect(
        doctorDiagnosticSummary([
          '  ✓ Profiles checked',
          '\x1b[33m$divider\x1b[0m',
          '\x1b[33m\x1b[1m  Found 3 issue(s) to address:\x1b[0m',
          '',
          '  1. state.db is large — enable sessions.auto_prune in config.yaml',
          '  2. Browser tools (agent-browser) has 2 npm vulnerabilities',
          '  3. web workspace has 6 npm vulnerabilities',
          '',
          "  Tip: run 'hermes doctor --fix' to auto-fix what's possible.",
          '',
        ]),
        'Found 3 issue(s) to address:\n\n'
        '1. state.db is large — enable sessions.auto_prune in config.yaml\n'
        '2. Browser tools (agent-browser) has 2 npm vulnerabilities\n'
        '3. web workspace has 6 npm vulnerabilities\n\n'
        "Tip: run 'hermes doctor --fix' to auto-fix what's possible.",
      );
    },
  );
  test('uses only the latest report from an appended action log', () {
    expect(
      doctorDiagnosticSummary([
        divider,
        'Found 3 issue(s) to address:',
        '=== doctor started 2026-09-18 01:15:00 ===',
        divider,
        '  All checks passed! 🎉',
      ]),
      'All checks passed! 🎉',
    );
  });
  test('does not mistake an old report or partial output for a diagnosis', () {
    for (final lines in [
      <String>[],
      ['  ✓ Profiles checked'],
      [divider, ''],
      [divider, 'All checks passed!', '=== doctor started today ===', 'Error'],
      ['┌${'─' * 60}┐', 'Doctor', '└${'─' * 60}┘'],
    ]) {
      expect(doctorDiagnosticSummary(lines), isNull);
    }
  });
}
