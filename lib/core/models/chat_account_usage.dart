/// Stock account report for one session's effective inference route.
///
/// Formatted provider output remains text. Optional `nous_usage` is the same
/// Nous read's dollar projection; it does not replace or add to this report.
class ChatAccountUsage {
  ChatAccountUsage._(this.lines, this.nousLines, this.nousRoute);

  final List<String> lines;
  final List<String> nousLines;
  final bool nousRoute;

  factory ChatAccountUsage.fromJson(Map<String, dynamic> value) {
    List<String> lines(String key) {
      final entries = value[key];
      if (entries is! List || entries.any((line) => line is! String)) {
        throw FormatException('Invalid account report $key');
      }
      return List<String>.unmodifiable(entries.cast<String>());
    }

    final route = value['nous_route'];
    if (route is! bool) {
      throw const FormatException('Missing account report route');
    }
    return ChatAccountUsage._(lines('lines'), lines('nous_lines'), route);
  }
}
