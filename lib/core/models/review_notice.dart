import 'answer_versions.dart';

/// Desktop marks review system messages explicitly instead of inspecting prose.
String? reviewMessageText(Map<String, dynamic> message) {
  if (message['role'] != 'system') return null;
  final text = answerMessageText(message);
  return text.startsWith('review:') ? text.substring(7).trim() : null;
}

String normalizeReviewText(String text) =>
    text.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').trim();

bool isLocalReviewMessage(Map<String, dynamic> message) =>
    message['_review_notice'] is String;

/// Live review events have no history snapshot API. Keep them between their
/// neighboring transcript rows when authoritative history replaces live rows.
/// They never contribute to server pagination offsets or survive a runtime reset.
List<Map<String, dynamic>> retainReviewMessages(
  List<Map<String, dynamic>> previous,
  List<Map<String, dynamic>> refreshed,
) {
  final result = refreshed.where((row) => !isLocalReviewMessage(row)).toList();
  int locate(Map<String, dynamic> row) => result.indexWhere((candidate) {
    if (isLocalReviewMessage(row)) {
      return reviewMessageText(candidate) == reviewMessageText(row);
    }
    if (row['id'] != null) return candidate['id'] == row['id'];
    return candidate['role'] == row['role'] &&
        answerMessageText(candidate) == answerMessageText(row);
  });

  for (var i = 0; i < previous.length; i++) {
    final review = previous[i];
    if (!isLocalReviewMessage(review)) continue;
    if (result.any(
      (row) => reviewMessageText(row) == reviewMessageText(review),
    )) {
      continue;
    }
    int? insertion;
    for (var before = i - 1; before >= 0; before--) {
      final index = locate(previous[before]);
      if (index < 0) continue;
      insertion = index + 1;
      break;
    }
    if (insertion == null) {
      for (var after = i + 1; after < previous.length; after++) {
        final index = locate(previous[after]);
        if (index < 0) continue;
        insertion = index;
        break;
      }
    }
    result.insert(insertion ?? 0, review);
  }
  return result;
}
