import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/hermes_question.dart';

final class _QuestionPosition {
  const _QuestionPosition(this.question, this.afterMessage, this.groupSequence);
  final HermesQuestion question;
  final Object? afterMessage;
  final int? groupSequence;
}

/// One device-owned history per authenticated conversation. First observation
/// fixes position; later outcomes cannot move the entry or grant live authority.
final class HermesQuestionHistory {
  factory HermesQuestionHistory(SharedPreferences preferences, String owner) =>
      (_owners[preferences] ??= {}).putIfAbsent(
        owner,
        () => HermesQuestionHistory._(preferences, owner),
      );

  HermesQuestionHistory._(this._preferences, String owner)
    : _key = 'hermes_question_history/$owner' {
    final saved = _preferences.getString(_key);
    if (saved == null) return;
    for (final value in jsonDecode(saved) as List) {
      final row = value as Map;
      final question = HermesQuestion.fromJson(row['question'] as Map);
      _entries[question.id] = _QuestionPosition(
        question,
        row['after_message'],
        row['group_sequence'] as int?,
      );
    }
  }

  static final _owners = Expando<Map<String, HermesQuestionHistory>>();
  final SharedPreferences _preferences;
  final String _key;
  final _entries = <String, _QuestionPosition>{};
  Future<void> _writes = Future.value();
  String? error;
  List<Map<String, dynamic>>? _projectedSource, _projected;
  int _revision = 0, _projectedRevision = -1;

  Iterable<HermesQuestion> get questions =>
      _entries.values.map((entry) => entry.question);
  HermesQuestion? question(String id) => _entries[id]?.question;

  void observe(
    HermesQuestion question, {
    Object? afterMessage,
    int? groupSequence,
  }) {
    final old = _entries[question.id];
    if (old != null) {
      // A passive/stale read never erases an acknowledged answer or invents a
      // second occurrence of the same server-owned request.
      if (question.status.certainty < old.question.status.certainty) return;
      if (question.status == old.question.status &&
          (question.status != HermesQuestionStatus.pending ||
              (question.command == old.question.command &&
                  question.description == old.question.description &&
                  question.sender == old.question.sender))) {
        return;
      }
      _entries[question.id] = _QuestionPosition(
        HermesQuestion(
          id: old.question.id,
          requestId: question.requestId,
          kind: old.question.kind,
          status: question.status,
          timestamp: old.question.timestamp,
          description: question.description,
          command: question.command,
          sender: question.sender,
        ),
        old.afterMessage,
        old.groupSequence,
      );
    } else {
      _entries[question.id] = _QuestionPosition(
        question,
        afterMessage,
        groupSequence,
      );
    }
    _revision++;
    _save();
  }

  void settle(String id, HermesQuestionStatus status) {
    final old = question(id);
    if (old != null) observe(old.withStatus(status));
  }

  void reconcile(Set<String> active, {HermesQuestionKind? kind}) {
    for (final entry in questions.toList()) {
      if ((kind == null || entry.kind == kind) &&
          entry.status == HermesQuestionStatus.pending &&
          !active.contains(entry.id)) {
        settle(entry.id, HermesQuestionStatus.closed);
      }
    }
  }

  void _save() {
    final rows = [
      for (final entry in _entries.values)
        {
          'question': entry.question.toJson(),
          'after_message': entry.afterMessage,
          'group_sequence': entry.groupSequence,
        },
    ];
    _writes = _writes
        .then((_) async {
          if (!await _preferences.setString(_key, jsonEncode(rows))) {
            throw StateError('Hermes question history could not be saved.');
          }
          error = null;
        })
        .catchError((Object _) {
          error = 'Hermes question history could not be saved on this device.';
        });
  }

  Future<void> flush() async {
    await _writes;
    if (error case final message?) throw StateError(message);
  }

  /// Interleave by the original row/room sequence. Timestamp ordering covers a
  /// saved page whose original neighboring row has not been loaded yet.
  List<Map<String, dynamic>> project(List<Map<String, dynamic>> messages) {
    if (_entries.isEmpty) return messages;
    if (identical(_projectedSource, messages) &&
        _projectedRevision == _revision) {
      return _projected!;
    }
    final insertions = <int, List<HermesQuestion>>{};
    final indices = {
      for (var i = 0; i < messages.length; i++)
        if (messages[i]['id'] != null) messages[i]['id']: i,
    };
    for (final entry in _entries.values) {
      if (entry.question.status == HermesQuestionStatus.pending) continue;
      var index = indices[entry.afterMessage];
      if (entry.groupSequence case final sequence?) {
        index = -1;
        for (var i = 0; i < messages.length; i++) {
          if ((messages[i]['sequence'] as int) > sequence) break;
          index = i;
        }
      } else if (index == null) {
        index = -1;
        for (var i = 0; i < messages.length; i++) {
          final timestamp = messages[i]['timestamp'];
          if (timestamp is num) {
            if (timestamp * 1000 >
                entry.question.timestamp.millisecondsSinceEpoch) {
              break;
            }
            index = i;
          }
        }
      }
      (insertions[index! + 1] ??= []).add(entry.question);
    }
    _projectedSource = messages;
    _projectedRevision = _revision;
    return _projected = List.unmodifiable([
      for (var i = 0; i <= messages.length; i++) ...[
        for (final question in insertions[i] ?? const <HermesQuestion>[])
          question.row,
        if (i < messages.length) messages[i],
      ],
    ]);
  }
}
