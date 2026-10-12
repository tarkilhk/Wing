import 'package:flutter/material.dart';
import '../../models/recent_conversation.dart';
import '../../services/recent_conversation_session.dart';
import 'conversation_route_scope.dart';
import 'recent_conversation_switcher.dart';

/// Group route composition; gestures, captures and springs stay shared with chat.
class GroupConversationSwitcher extends StatefulWidget {
  const GroupConversationSwitcher({
    super.key,
    required this.createSession,
    required this.groupKey,
    required this.onLeave,
    required this.previewBuilder,
    required this.child,
  });
  final RecentConversationSession Function() createSession;
  final RecentConversationKey groupKey;
  final VoidCallback onLeave;
  final Widget Function(RecentConversationCard) previewBuilder;
  final Widget child;
  @override
  State<GroupConversationSwitcher> createState() =>
      _GroupConversationSwitcherState();
}

class _GroupConversationSwitcherState extends State<GroupConversationSwitcher>
    with WidgetsBindingObserver {
  late final _session = widget.createSession();
  final _switcher = GlobalKey<RecentConversationSwitcherState>();
  bool _foreground = true, _obscured = false, _editing = false;
  bool _recording = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setState(() => _foreground = state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.isCurrentOf(context) != false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _switcher.currentState?.dismissStack() != true) {
          _session.dispose();
          widget.onLeave();
        }
      },
      child: RecentConversationSwitcher(
        key: _switcher,
        session: _session,
        chatKey: widget.groupKey,
        previewBuilder: widget.previewBuilder,
        gesturesEnabled: _foreground && current && !_recording,
        nudgesEnabled: _foreground && current && !_editing && !_recording,
        onPresentationChanged: (obscured, stack) {
          if (_obscured == obscured) return;
          setState(() => _obscured = obscured);
        },
        child: ConversationPresentationScope(
          visible: !_obscured && _foreground && current,
          onInputActivityChanged: (activity) {
            if (mounted &&
                (activity.editing != _editing ||
                    activity.recording != _recording)) {
              setState(() {
                _editing = activity.editing;
                _recording = activity.recording;
              });
            }
          },
          child: widget.child,
        ),
      ),
    );
  }
}
