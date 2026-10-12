import 'package:flutter/widgets.dart';
import '../../services/workspace_recents_session.dart';

/// A normal chat window borrowed by a group retains that native Back target.
class RecentConversationRouteScope extends InheritedWidget {
  const RecentConversationRouteScope({
    super.key,
    required this.recents,
    required this.onLeave,
    required super.child,
  });
  final WorkspaceRecentsSession recents;
  final VoidCallback onLeave;
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
