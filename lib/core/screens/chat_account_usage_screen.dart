import 'package:flutter/material.dart';

import '../services/chat_account_usage_session.dart';
import '../theme/wing_theme.dart';
import '../widgets/studio_error.dart';
import '../widgets/studio_loading.dart';
import '../widgets/wing_app_bar.dart';

/// A captured chat's read-only provider report, separate from usage analytics.
class ChatAccountUsageScreen extends StatefulWidget {
  const ChatAccountUsageScreen({
    super.key,
    required this.session,
    required this.chatTitle,
  });

  final ChatAccountUsageSession session;
  final String chatTitle;

  @override
  State<ChatAccountUsageScreen> createState() => _ChatAccountUsageScreenState();
}

class _ChatAccountUsageScreenState extends State<ChatAccountUsageScreen> {
  @override
  void initState() {
    super.initState();
    widget.session.refresh();
  }

  @override
  void dispose() {
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final report = session.report;
      final tokens = WingTokens.of(context);
      Widget reportLines(List<String> lines) => Text(
        lines.join('\n'),
        style: tokens.typography.body.copyWith(color: tokens.onSurface),
      );
      return StudioLoadingFrame(
        child: Scaffold(
          appBar: WingAppBar(
            context: context,
            title: const Text('Account usage'),
            actions: [
              if (session.error == null)
                StudioButtonPress(
                  child: IconButton(
                    tooltip: 'Refresh account usage',
                    onPressed: session.loading || session.retired
                        ? null
                        : session.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
          body: SafeArea(
            top: false,
            child: StudioPageLoading(
              active: session.loading,
              label: 'Loading account usage',
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WingSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.chatTitle,
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: WingSpacing.lg),
                    if (session.retired)
                      const StudioError(
                        'This account report is no longer current.',
                        detail: 'Go back and reopen Account usage.',
                      )
                    else ...[
                      if (session.error case final error?) ...[
                        StudioRetryNotice(
                          message: error,
                          onRetry: session.loading ? null : session.refresh,
                        ),
                        const SizedBox(height: WingSpacing.lg),
                      ],
                      if (report != null) ...[
                        if (report.lines.isNotEmpty ||
                            !report.nousRoute ||
                            report.nousLines.isEmpty) ...[
                          Text('This chat', style: tokens.typography.section),
                          const SizedBox(height: WingSpacing.sm),
                        ],
                        if (report.lines.isNotEmpty)
                          reportLines(report.lines)
                        else if (!report.nousRoute || report.nousLines.isEmpty)
                          Text(
                            'No account limits were reported for this chat.',
                            style: tokens.typography.body.copyWith(
                              color: tokens.muted,
                            ),
                          ),
                        if (report.nousLines.isNotEmpty) ...[
                          if (report.lines.isNotEmpty || !report.nousRoute)
                            const SizedBox(height: WingSpacing.lg),
                          Text(
                            report.nousRoute
                                ? 'Nous account'
                                : 'Separate Nous account',
                            style: tokens.typography.section,
                          ),
                          const SizedBox(height: WingSpacing.sm),
                          reportLines(report.nousLines),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
