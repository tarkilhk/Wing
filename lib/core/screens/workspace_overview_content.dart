import 'package:flutter/material.dart';
import '../models/bots.dart';
import '../services/bots_session.dart';
import '../services/profile_workspace_controller.dart';
import '../services/workspace_recents_session.dart';
import '../widgets/recent_identity_card.dart';
import '../widgets/studio_error.dart';
export 'administration/administration_content.dart';

class WorkspaceActivityContent extends StatefulWidget {
  const WorkspaceActivityContent({
    super.key,
    required this.controller,
    required this.bots,
    required this.onOpen,
    required this.onOpenGroup,
    required this.visible,
  });
  final ProfileWorkspaceController controller;
  final BotsSession bots;
  final bool visible;
  final void Function(ProfileRecentChat, List<WorkspaceRecentItem>) onOpen;
  final Future<void> Function(BotGroup) onOpenGroup;
  @override
  State<WorkspaceActivityContent> createState() =>
      _WorkspaceActivityContentState();
}

class _WorkspaceActivityContentState extends State<WorkspaceActivityContent> {
  late WorkspaceRecentsSession _session;
  bool _opening = false;
  void _attach() {
    _session = WorkspaceRecentsSession(widget.controller, widget.bots);
    _session.addListener(_changed);
    _syncVisibility();
  }

  void _syncVisibility() {
    final session = _session;
    // Hiding cancels polling immediately and cannot publish a refresh.
    if (!widget.visible) {
      session.setVisible(false);
      return;
    }
    // Both attachment and widget updates can run during route composition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_session, session)) {
        session.setVisible(widget.visible);
      }
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(WorkspaceActivityContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.bots != widget.bots) {
      _session.dispose();
      _attach();
    } else {
      _syncVisibility();
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _openGroup(BotGroup group) async {
    if (_opening) return;
    setState(() => _opening = true);
    _session.setVisible(false);
    try {
      await widget.onOpenGroup(group);
    } finally {
      if (mounted) {
        _session.setVisible(widget.visible);
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final items = _session.items();
    final now = DateTime.now();
    final colors = controller.appPreferences.profileColorsFor(
      controller.connectionIdentity,
    );
    return ValueListenableBuilder(
      valueListenable: colors,
      builder: (context, choices, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.recentsLoading || widget.bots.state.loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                semanticsLabel: 'Loading recent chats',
              ),
            ),
          for (final error in {
            ...controller.recentsProfileErrors.values,
            ...widget.bots.state.errors,
          })
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StudioError(error),
            ),
          if (items.isEmpty &&
              controller.recentsLoaded &&
              !widget.bots.state.loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const Icon(Icons.history, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    controller.recentsProfileErrors.isEmpty &&
                            widget.bots.state.errors.isEmpty
                        ? 'No recent chats'
                        : 'No recent chats found in available profiles',
                  ),
                ],
              ),
            ),
          for (final item in items)
            RecentIdentityCard(
              item: item,
              bots: widget.bots.state.bots,
              now: now,
              profileChoice: choices
                  .profiles[item.chat?.key.workspace.profileName]
                  ?.displayChoice,
              isDefault:
                  controller.discovery
                      ?.named(item.chat?.key.workspace.profileName ?? '')
                      ?.isDefault ==
                  true,
              onTap: controller.switching || _opening
                  ? null
                  : () {
                      if (item.group case final group?) {
                        _openGroup(group);
                      } else {
                        widget.onOpen(item.chat!, items);
                      }
                    },
            ),
        ],
      ),
    );
  }
}
