/// Extracts stock Hermes Doctor's final report from its bounded action log.
/// The summary is prose; the detailed checks remain available separately.
String? doctorDiagnosticSummary(List<dynamic> lines) {
  final clean = lines
      .join('\n')
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .split('\n')
      .map((line) => line.trim())
      .toList();
  // Action logs append runs. Never surface an earlier run's summary when the
  // latest run failed before printing its own report.
  final start = clean.lastIndexWhere(
    (line) => line.startsWith('=== doctor started '),
  );
  final divider = clean.lastIndexWhere(
    (line) => RegExp(r'^─{60}$').hasMatch(line),
  );
  if (divider <= start) return null;
  final summary = clean.skip(divider + 1).join('\n').trim();
  return summary.isEmpty ? null : summary;
}
