import 'package:flutter/material.dart';

import '../models/transcript_presentation.dart';
import '../models/transcript_timeline.dart';
import '../screens/profile_transcript.dart';
import '../models/profile_supervision.dart';
import 'activity/activity_detail_actions.dart';
import 'conversation_activity.dart';
import 'profile_message.dart';
import 'studio_error.dart';
import 'studio_loading.dart';

/// Uses the same projection, viewport, tool and reasoning renderers as chat.
class SubagentTimeline extends StatelessWidget {
  const SubagentTimeline({
    super.key,
    required this.session,
    required this.agentsBuilder,
  });
  final SubagentTimelineReader session;
  final Widget Function(SubagentInspectionSession) agentsBuilder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final projection = ChatTranscriptProjection(
        savedRows: session.messages,
        streamingMessage: session.streamingMessage,
        runtime: session.runtime,
        presentationId: session.messagePresentationId,
        liveAnswering: session.liveAnswering,
      );
      final activity = ConversationActivity(
        runtime: session.runtime,
        entries: projection.activity,
        todos: session.todos,
        inspection: session,
        agentsBuilder: () => agentsBuilder(session),
        live: session.liveAnswering,
        taskCount: session.todos.length,
        agentCount: session.state.subagents.length,
      );
      return StudioPageLoading(
        active: session.historyLoading && !session.historyPaging,
        label: 'Loading subagent activity',
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: ActivityDetailAction(
                  label: 'Refresh subagent activity',
                  icon: Icons.refresh,
                  onPressed: session.historyLoading ? null : session.refresh,
                ),
              ),
              Expanded(
                child: ProfileTranscript(
                  presentation: TranscriptPresentation.capture(
                    identity: ('subagent', session.state.key),
                    reader: session,
                    timeline: projection.timeline,
                    needsInput: false,
                    turnAdmissionBlocked: session.liveAnswering,
                  ),
                  onRefreshHistory: session.refresh,
                  onLoadOlder: session.loadOlder,
                  activity: activity,
                  emptyContent: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No subagent activity is available yet.'),
                  ),
                  tail: const [],
                  messageBuilder: (entry) =>
                      ProfileMessage(message: entry.message),
                ),
              ),
              if (session.qualification case final text?)
                _boundedFeedback(
                  Padding(padding: const EdgeInsets.all(8), child: Text(text)),
                  constraints.maxHeight * 0.2,
                ),
              if (session.liveError case final error?)
                Row(
                  children: [
                    Expanded(
                      child: _boundedFeedback(
                        StudioError(error),
                        constraints.maxHeight * 0.35,
                      ),
                    ),
                    ActivityDetailAction(
                      label: 'Retry subagent activity',
                      icon: Icons.refresh,
                      onPressed: session.refresh,
                    ),
                  ],
                ),
              activity.dock(),
            ],
          ),
        ),
      );
    },
  );
  Widget _boundedFeedback(Widget child, double height) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: height),
    child: SingleChildScrollView(primary: false, child: child),
  );
}
