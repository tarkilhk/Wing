import '../../models/bots.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/bot_group_history_session.dart';
import '../profile_transcript.dart';
import '../../models/transcript_timeline.dart';
import '../../widgets/profile_message.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';

class BotGroupHistoryScreen extends StatefulWidget {
  const BotGroupHistoryScreen({
    super.key,
    required this.createSession,
    required this.appearanceForMember,
    this.initialMemberId,
  });
  final BotRecord? Function(String profile) appearanceForMember;
  final String? initialMemberId;
  final BotGroupHistorySession Function() createSession;

  @override
  State<BotGroupHistoryScreen> createState() => _BotGroupHistoryScreenState();
}

class _BotGroupHistoryScreenState extends State<BotGroupHistoryScreen> {
  late final _session = widget.createSession();
  String? _reportedError;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _errorNotice;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    final first = widget.initialMemberId == null
        ? _session.group.members.firstOrNull
        : _session.group.members
              .where((member) => member.id == widget.initialMemberId)
              .firstOrNull;
    if (first != null) unawaited(_session.select(first));
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final error = _session.reader.historyError;
    if (error == null) {
      _errorNotice?.close();
      _errorNotice = null;
    }
    if (error != null &&
        error != _reportedError &&
        _session.reader.messages.isNotEmpty) {
      final notice = ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: StudioError(error)));
      _errorNotice = notice;
      unawaited(
        notice.closed.then((_) {
          if (identical(_errorNotice, notice)) _errorNotice = null;
        }),
      );
    }
    _reportedError = error;
  }

  @override
  void dispose() {
    _errorNotice?.close();
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = _session.reader;
    final timeline = TranscriptTimeline.project(
      reader.messages,
      presentationId: reader.messagePresentationId,
    );
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: WingAppBar(
        context: context,
        title: const Text('Working history', maxLines: 2),
        actions: [
          StudioButtonPress(
            child: IconButton(
              tooltip: 'Refresh working history',
              onPressed: reader.historyLoading ? null : _session.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: StudioPageLoading(
          active: reader.historyLoading && !reader.historyPaging,
          label: _session.historyAvailable
              ? 'Refreshing working history'
              : 'Loading working history',
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
                        child: StudioButtonPress(
                          child: ChoiceChip(
                            showCheckmark: false,
                            label: Text(member.name),
                            selected: _session.member?.id == member.id,
                            onSelected: (_) {
                              if (_session.member?.id == member.id) return;
                              unawaited(_session.select(member));
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Read only · This bot’s internal conversation',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: timeline.sections.isEmpty && reader.historyError == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              reader.historyLoading &&
                                  !_session.historyAvailable
                              ? const SizedBox.shrink()
                              : Text(
                                  'No working history is available for ${_session.member?.name ?? 'this bot'}.',
                                  textAlign: TextAlign.center,
                                ),
                        ),
                      )
                    : BotConversationScope(
                        bot: _session.member == null
                            ? null
                            : widget.appearanceForMember(
                                _session.member!.profile,
                              ),
                        name: _session.member?.name,
                        child: ProfileTranscript(
                          key: ValueKey((
                            'worker-history',
                            _session.member?.id,
                          )),
                          reader: reader,
                          identity: null,
                          needsInput: false,
                          turnAdmissionBlocked: false,
                          openingContent: null,
                          notificationReading: null,
                          onAnswerVisible: null,
                          onRefreshHistory: _session.refresh,
                          onLoadOlder: _session.loadOlder,
                          timeline: timeline,
                          tail: const [],
                          messageBuilder: (entry) => ProfileMessage(
                            message: entry.message,
                            loadImages: false,
                            attachmentImagesAvailable: false,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
