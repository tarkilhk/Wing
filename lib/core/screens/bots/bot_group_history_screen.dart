import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/bot_group_history_session.dart';
import '../../utils/expansion_scroll_controller.dart';
import '../../widgets/profile_message.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';

class BotGroupHistoryScreen extends StatefulWidget {
  const BotGroupHistoryScreen({super.key, required this.createSession});
  final BotGroupHistorySession Function() createSession;

  @override
  State<BotGroupHistoryScreen> createState() => _BotGroupHistoryScreenState();
}

class _BotGroupHistoryScreenState extends State<BotGroupHistoryScreen> {
  late final _session = widget.createSession();
  final _scroll = ScrollController();
  final _heights = <Object?, double>{};

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    final first = _session.group.members.firstOrNull;
    if (first != null) unawaited(_session.select(first));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _session.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _session.messages.reversed.toList();
    final errorRows = _session.error == null ? 0 : 1;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: WingAppBar(
        context: context,
        title: const Text('Working history', maxLines: 2),
        actions: [
          IconButton(
            tooltip: 'Refresh working history',
            onPressed: _session.loading ? null : _session.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _session.group.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  for (final member in _session.group.members)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(member.name),
                        selected: _session.member?.id == member.id,
                        onSelected: (_) {
                          if (_session.member?.id == member.id) return;
                          _heights.clear();
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                          unawaited(_session.select(member));
                        },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Read only · This bot’s internal conversation',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            if (_session.loading) const LinearProgressIndicator(),
            Expanded(
              child: messages.isEmpty && errorRows == 0
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _session.loading
                              ? 'Loading working history…'
                              : 'No working history is available for ${_session.member?.name ?? 'this bot'}.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: ValueKey(('worker-history', _session.member?.id)),
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          messages.length +
                          errorRows +
                          (_session.hasOlder ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (errorRows == 1 && index == 0) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: StudioError(_session.error!),
                          );
                        }
                        index -= errorRows;
                        if (index == messages.length) {
                          return Center(
                            child: IconButton(
                              tooltip: 'Load older working history',
                              onPressed: _session.loading
                                  ? null
                                  : _session.loadOlder,
                              icon: const Icon(Icons.history),
                            ),
                          );
                        }
                        final message = messages[index];
                        return TranscriptScrollAnchor(
                          key: ValueKey(message.id),
                          initialHeight: _heights[message.id] ?? 0,
                          onHeightChanged: (_, height) {
                            _heights[message.id] = height;
                          },
                          child: ProfileMessage(
                            message: message,
                            loadImages: false,
                            attachmentImagesAvailable: false,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
