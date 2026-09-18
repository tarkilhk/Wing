import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/security_audit_report.dart';

void main() {
  final sample = File('test/fixtures/security_audit.txt').readAsLinesSync();
  const clean = 'No known vulnerabilities found across 177 component(s).';

  test('parses the supplied report without deduplicating advisories', () {
    final report = SecurityAuditReport.fromLines(sample)!;
    expect(report.title, '21 vulnerabilities found');
    expect(report.summary, '21 vulnerabilities found across 177 components');
    expect(report.atSeverity(SecuritySeverity.high), hasLength(4));
    expect(report.atSeverity(SecuritySeverity.moderate), hasLength(6));
    expect(report.atSeverity(SecuritySeverity.low), hasLength(2));
    expect(report.atSeverity(SecuritySeverity.unknown), hasLength(9));
    expect(report.atSeverity(SecuritySeverity.critical), isEmpty);
    expect(report.notices, contains('did not restart running gateways'));
    final first = report.findings.first;
    expect(first.package, 'httpcore2');
    expect(first.version, '2.7.0');
    expect(first.component, 'venv');
    expect(first.advisory, 'GHSA-7mj9-2mp8-4m2p');
    expect(first.description, contains('without TLS'));
    expect(first.fixedIn, '2.10.0');
  });

  test(
    'supports all stock severities, repeated sources and optional details',
    () {
      final report = SecurityAuditReport.fromLines([
        'Found 6 known vulnerability finding(s) across 3 component(s):',
        for (final severity in SecuritySeverity.values) ...[
          '[${severity.index.isEven ? 'venv' : 'mcp:example'}]',
          '  ${severity.name.toUpperCase().padRight(8)}  package==1.2.3  GHSA-${severity.name}',
        ],
      ])!;
      expect(report.findings.map((f) => f.severity), SecuritySeverity.values);
      expect(
        report.findings.every(
          (f) => f.description == null && f.fixedIn == null,
        ),
        isTrue,
      );
      expect(report.findings[1].component, 'mcp:example');
    },
  );

  test('strips terminal colors and supports chunked log entries', () {
    final report = SecurityAuditReport.fromLines([
      '\x1b[33m${sample.join('\n')}\x1b[0m',
    ])!;
    expect(report.findings, hasLength(21));
  });

  test('reads only the newest run, including clean outcomes', () {
    final report = SecurityAuditReport.fromLines([
      ...sample,
      '=== security-audit started 2026-09-18 19:00:00 ===',
      clean,
    ])!;
    expect(report.title, 'No known vulnerabilities found');
    expect(
      report.summary,
      'No known vulnerabilities found across 177 components',
    );
    expect(report.findings, isEmpty);
    expect(report.notices, isEmpty);
    expect(
      SecurityAuditReport.fromLines([
        ...sample,
        '=== security-audit started 2026-09-18 19:00:00 ===',
        'audit failed: OSV batch query failed: offline',
      ]),
      isNull,
    );
  });

  test(
    'never treats truncated, empty or unfamiliar reports as a clean scan',
    () {
      for (final lines in [
        <String>[],
        sample.skip(6).toList(),
        sample.take(15).toList(),
        [clean, 'unrecognized trailer'],
        [
          'No components discovered (everything skipped, or empty environment).',
        ],
        ['No known vulnerabilities found across 0 component(s).'],
        [
          'Found 1 known vulnerability finding(s) across 177 component(s):',
          '[venv]',
          '  NEW  pkg==1  ID',
        ],
        [
          'Found 1 known vulnerability finding(s) across 177 component(s):',
          '  HIGH  pkg==1  ID',
        ],
      ]) {
        expect(
          SecurityAuditReport.fromLines(lines),
          isNull,
          reason: lines.join('\n'),
        );
      }
    },
  );

  test(
    'uses singular nouns and preserves a finding with only fix metadata',
    () {
      final report = SecurityAuditReport.fromLines([
        'Found 1 known vulnerability finding(s) across 1 component(s):',
        '[plugin:example]',
        '  HIGH      @scope/package==1.0.0  GHSA-example',
        '           fixed in: 2.0.0',
      ])!;
      expect(report.summary, '1 vulnerability found across 1 component');
      expect(report.findings.single.description, isNull);
      expect(report.findings.single.fixedIn, '2.0.0');
    },
  );

  test('running, unknown and failed actions cannot inherit a final report', () {
    for (final (running, exitCode) in [
      (true, null),
      (false, null),
      (false, 2),
    ]) {
      expect(
        SecurityAuditReport.fromStatus({
          'running': running,
          'exit_code': exitCode,
          'lines': sample,
        }),
        isNull,
      );
    }
    for (final exitCode in [0, 1]) {
      expect(
        SecurityAuditReport.fromStatus({
          'running': false,
          'exit_code': exitCode,
          'lines': sample,
        })!.findings,
        hasLength(21),
      );
    }
    expect(
      SecurityAuditReport.fromStatus({
        'running': false,
        'exit_code': 1,
        'lines': [clean],
      }),
      isNull,
    );
  });
}
