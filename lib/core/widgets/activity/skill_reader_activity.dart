part of 'skill_document_viewer.dart';

String _skillDate(BuildContext context, DateTime date, {bool exact = false}) {
  final local = date.toLocal(), locale = MaterialLocalizations.of(context);
  return exact
      ? '${locale.formatMediumDate(local)}, ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local))}'
      : locale.formatShortMonthDay(local);
}

class _SkillActivitySummary extends StatelessWidget {
  const _SkillActivitySummary({required this.observation});
  final SkillReaderObservation observation;
  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    Widget metric(int? count, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(count.toString(), style: colors.typography.title),
        Text(
          label,
          style: colors.typography.label.copyWith(color: colors.muted),
        ),
      ],
    );
    return _SkillSurface(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _SkillActivityDialog(observation: observation),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      size: 16,
                      color: colors.muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('Activity', style: colors.typography.label),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: colors.muted),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (observation.uses != null)
                      Expanded(
                        child: metric(observation.uses, 'recorded uses'),
                      ),
                    if (observation.patches != null)
                      Expanded(
                        child: metric(observation.patches, 'patches / edits'),
                      ),
                  ],
                ),
                if (observation.lastPatched case final date?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 12, color: colors.muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Last change ${_skillDate(context, date)}',
                              textAlign: TextAlign.right,
                              style: colors.typography.label.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillActivityDialog extends StatefulWidget {
  const _SkillActivityDialog({required this.observation});
  final SkillReaderObservation observation;
  @override
  State<_SkillActivityDialog> createState() => _SkillActivityDialogState();
}

class _SkillActivityDialogState extends State<_SkillActivityDialog> {
  bool _requests = false;
  @override
  Widget build(BuildContext context) {
    final observation = widget.observation, colors = WingTokens.of(context);
    final profiles = observation.activity
        .where(
          (p) => p.uses != null || p.patches != null || p.readRequests != null,
        )
        .toList();
    final palette = <Color>[
      colors.accent,
      const Color(0xff8bb8e8),
      const Color(0xffc5a3e5),
      const Color(0xffe7b66e),
      const Color(0xffe294a3),
      const Color(0xff83c79a),
      const Color(0xffb1b9c8),
    ];
    Color colour(SkillProfileActivity profile) =>
        palette[profiles.indexOf(profile) % palette.length];
    Widget chart(String label, int? Function(SkillProfileActivity) value) =>
        _SkillDonut(
          label: label,
          values: [
            for (final p in profiles)
              if (value(p) case final count?)
                (name: p.profile, count: count, color: colour(p)),
          ],
        );
    return Dialog(
      backgroundColor: colors.raised,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: WingRadius.card,
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Activity', style: colors.typography.section),
                  ),
                  ActivityDetailAction(
                    label: 'Close activity',
                    icon: Icons.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const _SkillRule(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, box) {
                        final charts = [
                          if (observation.uses != null)
                            chart('Uses', (p) => p.uses),
                          if (observation.patches != null)
                            chart('Patches / edits', (p) => p.patches),
                        ];
                        return box.maxWidth >=
                                MediaQuery.textScalerOf(context).scale(304)
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final c in charts) Expanded(child: c),
                                ],
                              )
                            : Column(children: charts);
                      },
                    ),
                    const SizedBox(height: 12),
                    for (final profile in profiles) ...[
                      const _SkillRule(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colour(profile),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                profile.profile,
                                style: colors.typography.label.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Text(
                      'Recorded skill loads/references and patches or full edits. No date window supplied. ${observation.activity.where((p) => p.uses != null || p.patches != null).length} profile records; missing records are unknown.',
                      style: colors.typography.label.copyWith(
                        color: colors.muted,
                      ),
                    ),
                    if (observation.readRequests case final requests?) ...[
                      const SizedBox(height: 12),
                      const _SkillRule(),
                      InkWell(
                        onTap: () => setState(() => _requests = !_requests),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Read requests · ${observation.readPeriodDays} days',
                                  style: colors.typography.label,
                                ),
                              ),
                              Text(
                                requests.toString(),
                                style: colors.typography.label,
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _requests
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_requests) ...[
                        if (requests > 0)
                          ClipRRect(
                            borderRadius: WingRadius.control,
                            child: SizedBox(
                              height: MediaQuery.textScalerOf(
                                context,
                              ).scale(32),
                              child: Row(
                                children: [
                                  for (final profile in profiles)
                                    if (profile.readRequests case final count?
                                        when count > 0)
                                      Expanded(
                                        flex: count,
                                        child: Semantics(
                                          label:
                                              '${profile.profile}: $count read requests',
                                          child: Container(
                                            color: colour(profile),
                                            alignment: Alignment.center,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 2,
                                                    ),
                                                child: Text(
                                                  count.toString(),
                                                  style: colors.typography.label
                                                      .copyWith(
                                                        color: _chartInk(
                                                          colour(profile),
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Logged skill-read requests in sessions started within ${observation.readPeriodDays} days, including unsuccessful requests. Missing profile records are unknown.',
                          style: colors.typography.label.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ],
                    if (profiles.any((p) => p.lastPatched != null)) ...[
                      const SizedBox(height: 12),
                      const _SkillRule(),
                      const SizedBox(height: 8),
                      Text(
                        'Last updated',
                        style: colors.typography.label.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final profile in profiles)
                        if (profile.lastPatched case final date?)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  profile.profile,
                                  style: colors.typography.label.copyWith(
                                    color: colors.muted,
                                  ),
                                ),
                                Text(
                                  _skillDate(context, date, exact: true),
                                  style: colors.typography.label.copyWith(
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _chartInk(Color colour) =>
    colour.computeLuminance() > .35 ? const Color(0xff101b24) : Colors.white;
typedef _SkillChartValue = ({String name, int count, Color color});

class _SkillDonut extends StatelessWidget {
  const _SkillDonut({required this.label, required this.values});
  final String label;
  final List<_SkillChartValue> values;
  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context),
        total = values.fold<int>(0, (sum, p) => sum + p.count),
        scale = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(box.maxWidth, scale.scale(160));
        return Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: colors.typography.label.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label:
                    '$label: $total. ${values.map((p) => '${p.name} ${p.count}').join(', ')}',
                child: ExcludeSemantics(
                  child: total == 0
                      ? SizedBox(
                          height: size,
                          child: Center(
                            child: Text('0', style: colors.typography.title),
                          ),
                        )
                      : SizedBox(
                          width: size,
                          height: size,
                          child: CustomPaint(
                            painter: _SkillDonutPainter(
                              values: values,
                              label: label == 'Uses' ? 'uses' : 'changes',
                              ink: colors.onSurface,
                              scale: scale,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkillDonutPainter extends CustomPainter {
  const _SkillDonutPainter({
    required this.values,
    required this.label,
    required this.ink,
    required this.scale,
  });
  final List<_SkillChartValue> values;
  final String label;
  final Color ink;
  final TextScaler scale;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, p) => sum + p.count),
        center = size.center(Offset.zero),
        stroke = size.width * .18,
        radius = (size.width - stroke) / 2;
    var angle = -math.pi / 2;
    void text(String text, Offset at, double font, Color colour) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: colour,
            fontSize: scale.scale(font),
            fontWeight: FontWeight.w500,
            fontFamily: WingTypography.sans,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
    }

    for (final value in values) {
      if (value.count == 0) continue;
      final sweep = value.count / total * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        sweep,
        false,
        Paint()
          ..color = value.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      final middle = angle + sweep / 2;
      text(
        value.count.toString(),
        center + Offset(math.cos(middle) * radius, math.sin(middle) * radius),
        12,
        _chartInk(value.color),
      );
      angle += sweep;
    }
    text(total.toString(), center - Offset(0, scale.scale(6)), 24, ink);
    text(label, center + Offset(0, scale.scale(16)), 11, ink);
  }

  @override
  bool shouldRepaint(_SkillDonutPainter old) =>
      old.values != values || old.ink != ink || old.scale != scale;
}
