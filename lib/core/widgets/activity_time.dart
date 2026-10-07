import 'dart:async';

import 'package:flutter/material.dart';

import '../presentation/tool_call_presentation.dart';
import '../theme/wing_theme.dart';
import '../utils/tool_activity_clock.dart';

/// Only this small label ticks. Execution facts and the transcript never tick.
class ActivityTime extends StatefulWidget {
  const ActivityTime({
    super.key,
    this.durationSeconds,
    this.startedAt,
    this.backendStartedAt,
    this.subject = 'Tool',
    this.clock = toolActivityNow,
    this.wallClock = DateTime.now,
  });
  final double? durationSeconds;
  final Duration? startedAt;

  /// Backend Unix timestamp in seconds, never a locally invented start.
  final double? backendStartedAt;
  final String subject;
  final Duration Function() clock;
  final DateTime Function() wallClock;

  @override
  State<ActivityTime> createState() => _ActivityTimeState();
}

class _ActivityTimeState extends State<ActivityTime>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(ActivityTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _schedule();
    if (mounted) setState(() {});
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (widget.durationSeconds != null ||
        (widget.startedAt == null && widget.backendStartedAt == null) ||
        !TickerMode.valuesOf(context).enabled ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finalTime = widget.durationSeconds;
    final start = widget.startedAt;
    final backendStart = widget.backendStartedAt;
    if (finalTime == null && start == null && backendStart == null) {
      return const SizedBox.shrink();
    }
    final elapsed =
        finalTime ??
        (backendStart != null
                ? widget.wallClock().microsecondsSinceEpoch / 1000000 -
                      backendStart
                : (widget.clock() - start!).inMilliseconds / 1000)
            .clamp(0.0, double.infinity);
    final text =
        '${finalTime == null ? '≈ ' : ''}${formatToolDuration(elapsed)}';
    return Tooltip(
      message: finalTime == null
          ? backendStart != null
                ? 'Approximate elapsed time from backend start; phone and server clocks may differ'
                : 'Approximate time since backend tool start was received'
          : 'Backend duration',
      child: Semantics(
        label: finalTime == null
            ? '${widget.subject} running; approximate elapsed time'
            : 'Backend duration $text',
        child: ExcludeSemantics(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: WingTokens.of(context).muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
