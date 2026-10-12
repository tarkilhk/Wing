import 'package:flutter/widgets.dart';
import '../../models/recent_conversation.dart';
import '../../services/workspace_recents_session.dart';

/// Borrowed chat windows return through their workspace's canonical menu owner.
class RecentConversationRouteScope extends InheritedWidget {
  const RecentConversationRouteScope({
    super.key,
    required this.recents,
    required this.onLeave,
    required super.child,
  });
  final WorkspaceRecentsSession recents;
  final ValueChanged<RecentConversationKey> onLeave;
  static RecentConversationRouteScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RecentConversationRouteScope>();
  @override
  bool updateShouldNotify(RecentConversationRouteScope oldWidget) =>
      recents != oldWidget.recents || onLeave != oldWidget.onLeave;
}

/// Visibility of the mounted discussion underneath shared Recents cards.
class ConversationPresentationScope extends InheritedWidget {
  const ConversationPresentationScope({
    super.key,
    required this.visible,
    required this.onInputActivityChanged,
    required super.child,
  });
  final bool visible;
  final ValueChanged<({bool editing, bool recording})> onInputActivityChanged;
  static ConversationPresentationScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ConversationPresentationScope>();
  @override
  bool updateShouldNotify(ConversationPresentationScope oldWidget) =>
      visible != oldWidget.visible;
}
