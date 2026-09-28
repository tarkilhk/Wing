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
