import 'answer_versions.dart';
import 'review_notice.dart';

bool isLocalTranscriptMessage(Map<String, dynamic> message) =>
    isLocalReviewMessage(message) || message['_command_notice'] == true;

/// Client-only feedback stays between its neighboring transcript rows when
/// authoritative history replaces live rows. It never counts toward pagination.
List<Map<String, dynamic>> retainLocalTranscriptMessages(
  List<Map<String, dynamic>> previous,
  List<Map<String, dynamic>> refreshed,
) {
  final result = refreshed
      .where((row) => !isLocalTranscriptMessage(row))
      .toList();
  int locate(Map<String, dynamic> row) => result.indexWhere((candidate) {
    if (isLocalReviewMessage(row)) {
      return reviewMessageText(candidate) == reviewMessageText(row);
    }
    if (row['id'] != null) return candidate['id'] == row['id'];
    return candidate['role'] == row['role'] &&
        answerMessageText(candidate) == answerMessageText(row);
  });

  for (var i = 0; i < previous.length; i++) {
    final local = previous[i];
    if (!isLocalTranscriptMessage(local)) continue;
    if (isLocalReviewMessage(local) &&
        result.any(
          (row) => reviewMessageText(row) == reviewMessageText(local),
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
    result.insert(insertion ?? 0, local);
  }
  return result;
}
