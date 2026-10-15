part of 'chat_runtime.dart';

/// Request lifecycle observations stay with the execution owner. The observer
/// receives display metadata only; persistence and placement belong to reading.
extension _RuntimeQuestions on ChatRuntime {
  void _publishQuestion(HermesQuestion question) {
    final old = _questionHistory[question.id];
    if (old != null) {
      if (question.status.certainty < old.status.certainty) return;
      question = HermesQuestion(
        id: old.id,
        requestId: question.requestId,
        kind: old.kind,
        status: question.status,
        timestamp: old.timestamp,
        description: question.description,
        command: question.command,
        sender: old.sender,
      );
    }
    _questionHistory[question.id] = question;
    onQuestion?.call(question);
  }

  void _rememberApproval(Map<String, dynamic> raw) {
    final id = raw['request_id'];
    if (id is! String || id.isEmpty) return;
    final request = GatewayApprovalRequest.fromEventData(raw);
    _publishQuestion(
      HermesQuestion(
        id: 'approval/$id',
        requestId: raw['server_request_id'] is String
            ? raw['server_request_id'] as String
            : id,
        kind: HermesQuestionKind.approval,
        status: HermesQuestionStatus.pending,
        timestamp: DateTime.now(),
        description: request.description,
        command: request.command,
      ),
    );
  }

  void _rememberQuestions(Iterable<GatewayClarifyRequest> questions) {
    for (final question in questions) {
      _publishQuestion(
        HermesQuestion(
          id: 'clarify/${question.requestId}/${question.questionId ?? ''}',
          requestId: question.requestId,
          kind: HermesQuestionKind.clarification,
          status: HermesQuestionStatus.pending,
          timestamp: DateTime.now(),
          description: [question.question, ...question.choices].join('\n'),
        ),
      );
    }
  }

  void _rememberSecure(GatewaySensitivePromptRequest request) {
    _publishQuestion(
      HermesQuestion(
        id: 'secure/${request.kind.name}/${request.requestId}',
        requestId: request.requestId,
        kind: HermesQuestionKind.secureInput,
        status: HermesQuestionStatus.pending,
        timestamp: DateTime.now(),
        description: '${request.title}\n${request.description}',
      ),
    );
  }

  void _settleQuestion(String id, HermesQuestionStatus status) {
    final old = _questionHistory[id];
    if (old != null) _publishQuestion(old.withStatus(status));
  }

  void _settleQuestionRequest(String requestId, HermesQuestionStatus status) {
    for (final question in _questionHistory.values.toList()) {
      if (question.requestId == requestId) _settleQuestion(question.id, status);
    }
  }

  void _reconcileQuestionHistory(HermesQuestionKind kind, Set<String> active) {
    for (final question in _questionHistory.values.toList()) {
      if (question.kind == kind &&
          question.status == HermesQuestionStatus.pending &&
          !active.contains(question.id)) {
        _settleQuestion(question.id, HermesQuestionStatus.closed);
      }
    }
    onQuestionReconciliation?.call(kind, active);
  }
}
