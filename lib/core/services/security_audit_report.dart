enum SecuritySeverity {
  critical('Critical'),
  high('High'),
  moderate('Moderate'),
  medium('Medium'),
  low('Low'),
  unknown('Unknown');

  const SecuritySeverity(this.label);
  final String label;
}

class SecurityFinding {
  const SecurityFinding({
    required this.severity,
    required this.component,
    required this.package,
    required this.version,
    required this.advisory,
    this.description,
    this.fixedIn,
  });

  final SecuritySeverity severity;
  final String component, package, version, advisory;
  final String? description, fixedIn;
}

/// A complete report from the current stock Hermes security-audit action log.
/// Counts describe reported findings, not deduplicated advisories or packages.
class SecurityAuditReport {
  const SecurityAuditReport({
    required this.componentCount,
    required this.findings,
    required this.notices,
  });

  final int componentCount;
  final List<SecurityFinding> findings;
  final String notices;
  bool get hasVulnerabilities => findings.isNotEmpty;
  bool get hasHighSeverity => findings.any(
    (finding) => const [
      SecuritySeverity.critical,
      SecuritySeverity.high,
    ].contains(finding.severity),
  );
  String get title => hasVulnerabilities
      ? '${findings.length} ${findings.length == 1 ? 'vulnerability' : 'vulnerabilities'} found'
      : 'No known vulnerabilities found';
  String get summary =>
      '$title across $componentCount ${componentCount == 1 ? 'component' : 'components'}';

  List<SecurityFinding> atSeverity(SecuritySeverity severity) =>
      findings.where((finding) => finding.severity == severity).toList();

  static SecurityAuditReport? fromStatus(Map<String, dynamic> status) {
    if (status['running'] != false ||
        !const [0, 1].contains(status['exit_code'])) {
      return null;
    }
    final report = fromLines(status['lines'] as List? ?? []);
    if (status['exit_code'] == 1 && report?.hasVulnerabilities != true) {
      return null;
    }
    return report;
  }

  static SecurityAuditReport? fromLines(List<dynamic> lines) {
    final clean = lines
        .join('\n')
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .split('\n');
    final start = clean.lastIndexWhere(
      (line) => line.trim().startsWith('=== security-audit started '),
    );
    final current = clean.skip(start + 1).toList();
    final findingsHeading = RegExp(
      r'^Found (\d+) known vulnerability finding\(s\) across (\d+) component\(s\):$',
    );
    final cleanHeading = RegExp(
      r'^No known vulnerabilities found across (\d+) component\(s\)\.$',
    );
    final heading = current.lastIndexWhere(
      (line) =>
          findingsHeading.hasMatch(line.trim()) ||
          cleanHeading.hasMatch(line.trim()),
    );
    if (heading < 0) return null;
    final found = findingsHeading.firstMatch(current[heading].trim());
    final cleanReport = cleanHeading.firstMatch(current[heading].trim());
    final count = found == null ? 0 : int.tryParse(found[1]!);
    final components = int.tryParse(found?[2] ?? cleanReport![1]!);
    if (count == null || components == null) return null;
    if (components == 0 || (found != null && count == 0)) return null;
    final findings = <SecurityFinding>[];
    String? component;
    final row = RegExp(
      r'^  (CRITICAL|HIGH|MODERATE|MEDIUM|LOW|UNKNOWN)\s+(\S+)==(\S+)\s+(\S+)\s*$',
    );
    final section = RegExp(r'^\[([^\]]+)\]$');
    for (var i = heading + 1; i < current.length; i++) {
      final line = current[i];
      if (line.trim().isEmpty) continue;
      final group = section.firstMatch(line.trimRight());
      if (group != null) {
        component = group[1];
        continue;
      }
      final match = row.firstMatch(line);
      if (match == null || component == null) return null;
      String? description;
      String? fixedIn;
      if (i + 1 < current.length &&
          current[i + 1].startsWith('           ') &&
          !current[i + 1].trim().startsWith('fixed in:')) {
        description = current[++i].trim();
      }
      if (i + 1 < current.length &&
          current[i + 1].startsWith('           fixed in: ')) {
        fixedIn = current[++i].trim().substring('fixed in: '.length);
      }
      findings.add(
        SecurityFinding(
          severity: SecuritySeverity.values.singleWhere(
            (severity) => severity.name.toUpperCase() == match[1],
          ),
          component: component,
          package: match[2]!,
          version: match[3]!,
          advisory: match[4]!,
          description: description,
          fixedIn: fixedIn,
        ),
      );
    }
    // A clipped tail or unfamiliar report must not invent severity totals.
    if (findings.length != count) return null;
    return SecurityAuditReport(
      componentCount: components,
      findings: List.unmodifiable(findings),
      notices: current.take(heading).join('\n').trim(),
    );
  }
}
