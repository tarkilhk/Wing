import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/attachment_draft.dart';
import '../models/queued_prompt_draft.dart';

class ComposerDraftSnapshot {
  final String text;
  final List<AttachmentDraft> attachments;
  final bool submissionUncertain;
  final List<QueuedPromptDraft> queuedPrompts;
  final bool queuePaused;

  const ComposerDraftSnapshot({
    required this.text,
    required this.attachments,
    required this.submissionUncertain,
    this.queuedPrompts = const [],
    this.queuePaused = false,
  });
}

typedef ComposerDraftSummary = ({
  String sessionId,
  String text,
  int attachmentCount,
  int queuedCount,
  bool submissionUncertain,
});

/// Stores only work that has not been accepted by Hermes yet.
class ComposerDraftStore {
  final SharedPreferences _preferences;
  final String connectionIdentity;

  ComposerDraftStore(this._preferences, {required this.connectionIdentity}) {
    if (connectionIdentity.isEmpty) {
      throw ArgumentError('A verified connection identity is required');
    }
  }

  String get _key => 'composer_drafts_v1_$connectionIdentity';

  List<ComposerDraftSummary> summaries({required String profileName}) {
    return [
      for (final record in _readRecords())
        if (record['profile'] == profileName &&
            record['session'] is String &&
            (record['session'] as String).isNotEmpty &&
            record['text'] is String &&
            record['attachments'] is List)
          (
            sessionId: record['session'] as String,
            text: record['text'] as String,
            attachmentCount: (record['attachments'] as List).length,
            queuedCount: record['queue'] is List
                ? (record['queue'] as List).length
                : 0,
            submissionUncertain: record['submission_uncertain'] == true,
          ),
    ];
  }

  Future<ComposerDraftSnapshot?> read({
    required String profileName,
    required String sessionId,
  }) async {
    final records = _readRecords();
    final record = records.where((value) {
      return value['profile'] == profileName && value['session'] == sessionId;
    }).firstOrNull;
    if (record == null) return null;
    return _decodeRecord(record);
  }

  Future<void> write({
    required String profileName,
    required String sessionId,
    required String text,
    required Iterable<AttachmentDraft> attachments,
    bool submissionUncertain = false,
    Iterable<QueuedPromptDraft> queuedPrompts = const [],
    bool queuePaused = false,
  }) async {
    final records = _readRecords()
      ..removeWhere(
        (value) =>
            value['profile'] == profileName && value['session'] == sessionId,
      );
    final files = attachments.toList(growable: false);
    final queue = queuedPrompts.toList(growable: false);
    if (text.isNotEmpty || files.isNotEmpty || queue.isNotEmpty) {
      records.add(
        _encodeRecord(
          profileName: profileName,
          sessionId: sessionId,
          text: text,
          attachments: files,
          submissionUncertain: submissionUncertain,
          queuedPrompts: queue,
          queuePaused: queuePaused,
        ),
      );
    }
    final saved = records.isEmpty
        ? await _preferences.remove(_key)
        : await _preferences.setString(_key, jsonEncode(records));
    if (!saved) throw StateError('Could not save unsent messages.');
  }

  Future<ComposerDraftSnapshot?> move({
    required String profileName,
    required String fromSessionId,
    required String toSessionId,
    bool forNewSession = false,
  }) async {
    if (fromSessionId == toSessionId) {
      throw ArgumentError('Draft destination must be new.');
    }
    final records = _readRecords();
    if (records.any(
      (value) =>
          value['profile'] == profileName && value['session'] == toSessionId,
    )) {
      throw StateError('The replacement chat already has a draft.');
    }
    final index = records.indexWhere(
      (value) =>
          value['profile'] == profileName && value['session'] == fromSessionId,
    );
    if (index < 0) return null;
    if (!forNewSession) {
      records[index] = {...records[index], 'session': toSessionId};
      if (!await _preferences.setString(_key, jsonEncode(records))) {
        throw StateError('Could not move unsent messages.');
      }
      return null;
    }
    final sourceRecord = jsonEncode(records[index]);
    final snapshot = await _decodeRecord(records[index], forNewSession: true);
    if (snapshot == null) {
      throw StateError('The saved draft could not be read.');
    }
    final currentRecords = _readRecords();
    if (currentRecords.any(
      (value) =>
          value['profile'] == profileName && value['session'] == toSessionId,
    )) {
      throw StateError('The replacement chat already has a draft.');
    }
    final currentIndex = currentRecords.indexWhere(
      (value) =>
          value['profile'] == profileName &&
          value['session'] == fromSessionId &&
          jsonEncode(value) == sourceRecord,
    );
    if (currentIndex < 0) {
      throw StateError('The saved draft changed while it was being moved.');
    }
    currentRecords[currentIndex] = _encodeRecord(
      profileName: profileName,
      sessionId: toSessionId,
      text: snapshot.text,
      attachments: snapshot.attachments,
      submissionUncertain: snapshot.submissionUncertain,
      queuedPrompts: snapshot.queuedPrompts,
      queuePaused: true,
    );
    if (!await _preferences.setString(_key, jsonEncode(currentRecords))) {
      throw StateError('Could not move unsent messages.');
    }
    return snapshot;
  }

  Future<ComposerDraftSnapshot?> _decodeRecord(
    Map<String, dynamic> record, {
    bool forNewSession = false,
  }) async {
    final text = record['text'];
    final rawAttachments = record['attachments'];
    if (text is! String || rawAttachments is! List) return null;
    return ComposerDraftSnapshot(
      text: text,
      attachments: await _decodeAttachments(
        rawAttachments,
        forNewSession: forNewSession,
      ),
      submissionUncertain: record['submission_uncertain'] == true,
      queuedPrompts: await _decodeQueue(
        record['queue'],
        forNewSession: forNewSession,
      ),
      queuePaused: forNewSession || record['queue_paused'] == true,
    );
  }

  Map<String, dynamic> _encodeRecord({
    required String profileName,
    required String sessionId,
    required String text,
    required Iterable<AttachmentDraft> attachments,
    required bool submissionUncertain,
    required Iterable<QueuedPromptDraft> queuedPrompts,
    required bool queuePaused,
  }) => {
    'profile': profileName,
    'session': sessionId,
    'text': text,
    'submission_uncertain': submissionUncertain,
    'queue': queuedPrompts.map(_encodeQueuedPrompt).toList(),
    'queue_paused': queuePaused,
    'attachments': attachments.map(_encodeAttachment).toList(),
  };

  List<Map<String, dynamic>> _readRecords() {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final value in decoded)
          if (value is Map) Map<String, dynamic>.from(value),
      ];
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _encodeAttachment(AttachmentDraft draft) => {
    'id': draft.id,
    'path': draft.cachedPath,
    'name': draft.name,
    'bytes': draft.byteLength,
    'media_type': draft.mediaType,
    'kind': draft.kind.name,
    'source_image_format': draft.sourceImageFormat?.name,
    'sanitized': draft.sanitized,
    'status': draft.status.name,
    'ref_text': draft.refText,
    'image_path': draft.imagePath,
    'attached_session_id': draft.attachedSessionId,
    'error': draft.error,
    'atlas_intake_accepted': draft.atlasIntakeAccepted,
  };

  Map<String, dynamic> _encodeQueuedPrompt(QueuedPromptDraft prompt) => {
    'text': prompt.text,
    'attachments': prompt.attachments.map(_encodeAttachment).toList(),
    if (prompt.submissionUncertain) 'submission_uncertain': true,
  };

  Future<List<QueuedPromptDraft>> _decodeQueue(
    Object? value, {
    bool forNewSession = false,
  }) async {
    if (value is! List) return [];
    final queued = <QueuedPromptDraft>[];
    for (final entry in value) {
      if (entry is String) {
        queued.add(QueuedPromptDraft(text: entry));
        continue;
      }
      try {
        final record = Map<String, dynamic>.from(entry as Map);
        final text = record['text'];
        final rawAttachments = record['attachments'];
        final submissionUncertain = record['submission_uncertain'];
        if (text is! String ||
            rawAttachments is! List ||
            (submissionUncertain != null && submissionUncertain is! bool)) {
          throw const FormatException('Invalid queued prompt');
        }
        final attachments = await _decodeAttachments(
          rawAttachments,
          forNewSession: forNewSession,
        );
        if (text.trim().isNotEmpty || attachments.isNotEmpty) {
          queued.add(
            QueuedPromptDraft(
              text: text,
              attachments: attachments,
              submissionUncertain: submissionUncertain == true,
            ),
          );
        }
      } catch (_) {
        // One damaged queue entry must not discard the other unsent work.
      }
    }
    return queued;
  }

  Future<List<AttachmentDraft>> _decodeAttachments(
    List<dynamic> values, {
    bool forNewSession = false,
  }) async {
    final attachments = <AttachmentDraft>[];
    for (final value in values) {
      try {
        final draft = _decodeAttachment(
          Map<String, dynamic>.from(value as Map),
        );
        final hasReusableReference =
            !forNewSession && draft.hasGatewayAttachment;
        final cachedFileExists = hasReusableReference
            ? true
            : await File(draft.cachedPath).exists();
        if (forNewSession) {
          draft
            ..refText = null
            ..imagePath = null
            ..attachedSessionId = null
            ..atlasIntakeAccepted = null;
          if (!cachedFileExists) {
            draft
              ..status = AttachmentDraftStatus.failed
              ..error =
                  'This staged file is no longer available. Remove it and attach it again.';
          } else if (draft.status == AttachmentDraftStatus.attached ||
              draft.status == AttachmentDraftStatus.uploading) {
            draft
              ..status = AttachmentDraftStatus.ready
              ..error = null;
          }
        } else if (!cachedFileExists) {
          draft
            ..status = AttachmentDraftStatus.failed
            ..error =
                'This staged file is no longer available. Remove it and attach it again.';
        } else if (draft.status == AttachmentDraftStatus.uploading) {
          draft.status = AttachmentDraftStatus.ready;
        }
        attachments.add(draft);
      } catch (_) {
        // One damaged attachment record must not discard the user's text.
      }
    }
    return attachments;
  }

  AttachmentDraft _decodeAttachment(Map<String, dynamic> value) {
    T enumValue<T extends Enum>(List<T> values, Object? name) =>
        values.singleWhere((candidate) => candidate.name == name);

    final id = value['id'];
    final path = value['path'];
    final name = value['name'];
    final bytes = value['bytes'];
    final mediaType = value['media_type'];
    if (id is! String ||
        id.isEmpty ||
        path is! String ||
        path.isEmpty ||
        name is! String ||
        name.isEmpty ||
        bytes is! int ||
        bytes <= 0 ||
        mediaType is! String ||
        mediaType.isEmpty) {
      throw const FormatException('Invalid attachment draft');
    }
    final sourceFormat = value['source_image_format'];
    return AttachmentDraft(
      id: id,
      cachedPath: path,
      name: name,
      byteLength: bytes,
      mediaType: mediaType,
      kind: enumValue(AttachmentDraftKind.values, value['kind']),
      sourceImageFormat: sourceFormat == null
          ? null
          : enumValue(AttachmentImageFormat.values, sourceFormat),
      sanitized: value['sanitized'] == true,
      status: enumValue(AttachmentDraftStatus.values, value['status']),
      refText: value['ref_text'] as String?,
      imagePath: value['image_path'] as String?,
      attachedSessionId: value['attached_session_id'] as String?,
      error: value['error'] as String?,
      atlasIntakeAccepted: value['atlas_intake_accepted'] as bool?,
    );
  }
}
