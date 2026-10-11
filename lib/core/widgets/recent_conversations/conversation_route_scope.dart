import 'package:flutter/widgets.dart';
import '../../models/recent_conversation.dart';

/// A normal chat window borrowed by a group retains that native Back target.
class RecentConversationRouteScope extends InheritedWidget {
  const RecentConversationRouteScope({
    super.key,
    required this.entries,
    required this.onLeave,
    required super.child,
  });
  final List<RecentConversationEntry> entries;
  final VoidCallback onLeave;
  static RecentConversationRouteScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RecentConversationRouteScope>();
  @override
  bool updateShouldNotify(RecentConversationRouteScope oldWidget) =>
      entries != oldWidget.entries || onLeave != oldWidget.onLeave;
}

/// Visibility of the mounted discussion underneath shared Recents cards.
class ConversationPresentationScope extends InheritedWidget {
  const ConversationPresentationScope({
    super.key,
    required this.visible,
    required this.onComposerFocusChanged,
    required super.child,
  });
  final bool visible;
  final ValueChanged<bool> onComposerFocusChanged;
  static ConversationPresentationScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ConversationPresentationScope>();
  @override
  bool updateShouldNotify(ConversationPresentationScope oldWidget) =>
      visible != oldWidget.visible;
}
