/// Identity of the answer or pending input represented by a chat notification.
/// Text is never used as identity; two identical answers are still distinct.
class NotificationFocus {
  final String kind;
  final String id;
  final int? messageId;

  const NotificationFocus(this.kind, this.id, {this.messageId});
  String get identity => '$kind:$id';
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    if (messageId != null) 'message_id': messageId,
  };
  factory NotificationFocus.fromJson(Map<String, dynamic> data) {
    final kind = data['kind'];
    final id = data['id'];
    if (kind is! String ||
        id is! String ||
        id.isEmpty ||
        !{
          'answer',
          'side',
          'background',
          'approval',
          'question',
          'secure',
          'status',
        }.contains(kind)) {
      throw const FormatException('Invalid notification target');
    }
    return NotificationFocus(kind, id, messageId: data['message_id'] as int?);
  }
  @override
  bool operator ==(Object other) =>
      other is NotificationFocus &&
      kind == other.kind &&
      id == other.id &&
      messageId == other.messageId;
  @override
  int get hashCode => Object.hash(kind, id, messageId);
}
