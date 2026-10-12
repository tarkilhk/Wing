import 'hermes_profile.dart';

/// A shared room on one authenticated connection, independent of bot sessions.
final class GroupNotificationTarget {
  const GroupNotificationTarget(this.scope, this.roomId);
  final WorkspaceScope scope;
  final String roomId;
  String get key => '${scope.connectionIdentity}/$roomId';
  Map<String, String> toJson() => {
    'connection': scope.connectionId,
    'connection_identity': scope.connectionIdentity,
    'room': roomId,
  };
  factory GroupNotificationTarget.fromJson(Map<String, dynamic> value) {
    String field(String name) {
      final text = value[name];
      if (text is! String || text.isEmpty) {
        throw const FormatException('Invalid group notification target');
      }
      return text;
    }

    if (value.containsKey('session') || value.containsKey('profile')) {
      throw const FormatException('Mixed notification target');
    }
    return GroupNotificationTarget(
      WorkspaceScope(
        connectionId: field('connection'),
        connectionIdentity: field('connection_identity'),
        profileName: 'default',
      ),
      field('room'),
    );
  }
}

final class GroupAnswerNotification {
  const GroupAnswerNotification({
    required this.target,
    required this.title,
    required this.instance,
    required this.sequence,
    required this.text,
  });
  final GroupNotificationTarget target;
  final String title, instance, text;
  final int sequence;
}
