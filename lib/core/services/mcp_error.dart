/// MCP OAuth errors can include URLs and credential assignments from exceptions.
/// Keep the reason useful without displaying those values in the connector UI.
String mcpErrorMessage(Object? error, {required String summary}) {
  if (error is! String || error.trim().isEmpty) return summary;
  var detail = error.trim();
  detail = detail.replaceAllMapped(
    RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
    (match) {
      final uri = Uri.tryParse(match[0]!);
      if (uri == null || uri.host.isEmpty) return '[URL redacted]';
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    },
  );
  detail = detail.replaceAllMapped(
    RegExp(
      r'\b(authorization|cookie|set-cookie)\s*[:=][^\r\n]*',
      caseSensitive: false,
    ),
    (match) => '${match[1]}: [REDACTED]',
  );
  detail = detail.replaceAll(
    RegExp(r'\b(Bearer|Basic)\s+[^\s,;]+', caseSensitive: false),
    '[REDACTED]',
  );
  detail = detail.replaceAllMapped(
    RegExp(
      r'''\b(authorization|cookie|set-cookie|[\w-]*(?:token|secret|password|api[_-]?key)|code|state)\b["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)''',
      caseSensitive: false,
    ),
    (match) => '${match[1]}=[REDACTED]',
  );
  return '$summary\n$detail';
}
