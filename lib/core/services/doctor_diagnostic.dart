/// A complete final report from stock Hermes Doctor's bounded action log.
class DoctorDiagnostic {
  const DoctorDiagnostic(this.findings);

  final List<DoctorFinding> findings;
  bool get hasIssues => findings.isNotEmpty;
  String get title => hasIssues
      ? '${findings.length} ${findings.length == 1 ? 'issue' : 'issues'} found'
      : 'No issues found';

  static DoctorDiagnostic? fromLines(List<dynamic> lines) {
    final clean = lines
        .join('\n')
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .split('\n')
        .map((line) => line.trim())
        .toList();
    // Logs append runs. A new run can fail before producing its own report.
    final start = clean.lastIndexWhere(
      (line) => line.startsWith('=== doctor started '),
    );
    final divider = clean.lastIndexWhere(
      (line) => RegExp(r'^─{60}$').hasMatch(line),
    );
    if (divider <= start) return null;
    final report = clean
        .skip(divider + 1)
        .where((line) => line.isNotEmpty)
        .toList();
    if (report.isEmpty) return null;
    if (report.length == 1 && report.single == 'All checks passed! 🎉') {
      return const DoctorDiagnostic([]);
    }
    final heading = RegExp(
      r'^Found (\d+) issue\(s\) to address:$',
    ).firstMatch(report.first);
    if (heading == null) return null;
    final findings = <String>[];
    for (final line in report.skip(1)) {
      // The CLI-only repair instruction belongs in the full output, not in a
      // mobile findings list that cannot perform that operation.
      if (line ==
          "Tip: run 'hermes doctor --fix' to auto-fix what's possible.") {
        continue;
      }
      final item = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(line);
      if (item != null) {
        if (int.parse(item[1]!) != findings.length + 1) return null;
        findings.add(item[2]!);
      } else if (findings.isNotEmpty) {
        findings[findings.length - 1] += ' $line';
      } else {
        return null;
      }
    }
    // A truncated report must not turn missing findings into a clean diagnosis.
    if (findings.length != int.parse(heading[1]!) || findings.isEmpty) {
      return null;
    }
    return DoctorDiagnostic(findings.map(DoctorFinding.fromText).toList());
  }
}

class DoctorFinding {
  const DoctorFinding(
    this.title,
    this.detail, {
    this.hasRecommendation = false,
  });

  final String title;
  final String? detail;
  final bool hasRecommendation;

  String chatPrompt(String diagnosticOutput) =>
      '''Help me investigate this Hermes Doctor finding and propose a solution.

Finding:
$title
${detail == null ? '' : '\n${hasRecommendation ? 'Doctor’s recommendation' : 'Doctor details'}:\n$detail\n'}
Explain what this means, its likely cause, and whether it needs attention. Use the diagnostic output below as context, focusing on this finding.

Propose a fix if possible, including any risk of losing chat history or other data and how to verify the result. If you need more information, ask me rather than guessing.

Do not make changes or run repair commands yet. Explain your proposed solution first.

Diagnostic output:
$diagnosticOutput''';

  factory DoctorFinding.fromText(String text) {
    final separator = text.indexOf(' — ');
    if (separator > 0) {
      return DoctorFinding(
        text.substring(0, separator),
        text.substring(separator + 3),
        hasRecommendation: true,
      );
    }
    final vulnerabilities = RegExp(
      r'^(.+) has (\d+ npm vulnerabilities)$',
    ).firstMatch(text);
    if (vulnerabilities != null) {
      return DoctorFinding(vulnerabilities[1]!, vulnerabilities[2]!);
    }
    return DoctorFinding(text, null);
  }
}
