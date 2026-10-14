import '../../models/gateway_todo.dart';
import '../../widgets/profile_activity_status.dart';
import '../../widgets/profile_activity_tabs.dart';
import '../../widgets/profile_execution_activity.dart';
import '../../widgets/profile_live_execution.dart';
import '../../widgets/profile_live_work_dock.dart';
import '../../widgets/profile_subagent_panel.dart';
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

class _BotGroupHistoryScreenState extends State<BotGroupHistoryScreen>
    with WidgetsBindingObserver {
  final _dock = GlobalKey<ProfileLiveWorkDockState>();
  late final _session = widget.createSession();
  String? _reportedError;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _errorNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    _session.setVisible(true);
    final first = widget.initialMemberId == null
        ? _session.group.members.firstOrNull
        : _session.group.members
              .where((member) => member.id == widget.initialMemberId)
              .firstOrNull;
    if (first != null) unawaited(_session.select(first));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.setVisible(state == AppLifecycleState.resumed);

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
    WidgetsBinding.instance.removeObserver(this);
    _errorNotice?.close();
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = _session.reader;
    final runtime = _session.runtime;
    final projection = ChatTranscriptProjection(
      savedRows: reader.messages,
      streamingMessage: _session.streamingMessage,
      runtime: runtime,
      presentationId: reader.messagePresentationId,
      liveAnswering: _session.liveAnswering,
    );
    final timeline = projection.timeline;
    final agents = ProfileSubagentPanel(session: _session, embedded: true);
    final tasks = ProfileTodoPanel(todos: _session.todos, embedded: true);
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _dock.currentState?.isOpen != true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _dock.currentState?.dismiss();
          setState(() {});
        }
      },
      child: Scaffold(
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
                  child:
                      timeline.sections.isEmpty &&
                          projection.activity.isEmpty &&
                          reader.historyError == null
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
                            identity: _session.key,
                            needsInput: runtime.needsInput,
                            turnAdmissionBlocked: _session.liveAnswering,
                            openingContent: null,
                            notificationReading: null,
                            onAnswerVisible: null,
                            onRefreshHistory: _session.refresh,
                            onLoadOlder: _session.loadOlder,
                            timeline: timeline,
                            liveExecution:
                                !_session.liveAnswering ||
                                    projection.activity.isEmpty
                                ? null
                                : ProfileLiveExecution(
                                    entries: projection.activity,
                                  ),
                            liveToolCount: _session.liveAnswering
                                ? 0
                                : runtime.toolActivities.length,
                            currentActivity:
                                _session.liveAnswering ||
                                    projection.activity.isEmpty
                                ? const []
                                : [
                                    ProfileExecutionActivity(
                                      entries: projection.activity,
                                    ),
                                  ],
                            activityTabs: _session.liveAnswering
                                ? const []
                                : [
                                    if (_session.todos.isNotEmpty)
                                      ProfileActivityTab(
                                        id: 'tasks',
                                        label:
                                            'Tasks ${_session.todos.where((todo) => todo.status == GatewayTodoStatus.completed).length}/${_session.todos.length}',
                                        child: tasks,
                                      ),
                                    if (_session.subagents.isNotEmpty)
                                      ProfileActivityTab(
                                        id: 'agents',
                                        label:
                                            'Agents ${_session.subagents.where((agent) => !agent.isTerminal).length}/${_session.subagents.length}',
                                        onSelected: () => unawaited(
                                          _session.refreshSubagents(),
                                        ),
                                        child: agents,
                                      ),
                                  ],
                            tail: const [],
                            messageBuilder: (entry) => ProfileMessage(
                              message: entry.message,
                              loadImages: false,
                              attachmentImagesAvailable: false,
                            ),
                          ),
                        ),
                ),
                if (_session.liveError case final error?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: StudioError(error),
                  ),
                ProfileActivityStatus(
                  runtime: runtime,
                  subagents: _session.subagents,
                  unconfirmedSubagentIds: _session.state.unconfirmedSubagentIds,
                  saving: false,
                ),
                if (_session.liveAnswering &&
                    (_session.todos.isNotEmpty ||
                        _session.subagents.isNotEmpty))
                  ProfileLiveWorkDock(
                    key: _dock,
                    onOpenChanged: () {
                      if (mounted) setState(() {});
                    },
                    taskCount: _session.todos.length,
                    completedTasks: _session.todos
                        .where(
                          (todo) => todo.status == GatewayTodoStatus.completed,
                        )
                        .length,
                    subagentCount: _session.subagents.length,
                    tasks: tasks,
                    subagents: agents,
                    onAgentsSelected: _session.refreshSubagents,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
