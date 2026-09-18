import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/usage_analytics.dart';
import '../../theme/wing_theme.dart';

String compactUsage(num? value) {
  if (value == null) return 'Unavailable';
  for (final (size, suffix) in [
    (1e12, 'T'),
    (1e9, 'B'),
    (1e6, 'M'),
    (1e3, 'K'),
  ]) {
    if (value >= size) {
      return '${(value / size).toStringAsFixed(value / size >= 100 ? 0 : 1)}$suffix';
    }
  }
  return value.toStringAsFixed(0);
}

List<Color> usageColors(BuildContext context) {
  final tokens = WingTokens.of(context);
  final dark = tokens.brightness == Brightness.dark;
  return [
    tokens.accent,
    dark ? const Color(0xFF8BA9C2) : const Color(0xFF69819A),
    dark ? const Color(0xFFE9B96E) : const Color(0xFFA46C20),
    dark ? const Color(0xFF91ADF1) : const Color(0xFF526FAF),
    dark ? const Color(0xFFC997B8) : const Color(0xFF986783),
    dark ? const Color(0xFFAFC489) : const Color(0xFF71823E),
  ];
}

class UsageSegment {
  final String id;
  final String label;
  final double? value;
  final Color color;
  final bool partial;
  final VoidCallback? onTap;
  const UsageSegment({
    required this.id,
    required this.label,
    required this.value,
    required this.color,
    this.partial = false,
    this.onTap,
  });
}

Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 300);

class UsageComposition extends StatelessWidget {
  final List<UsageSegment> segments;
  const UsageComposition({super.key, required this.segments});
  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, s) => sum + (s.value ?? 0));
    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 16,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: WingTokens.of(context).border),
              ),
              for (var i = 0; i < segments.length; i++)
                AnimatedPositioned(
                  key: ValueKey(segments[i].id),
                  duration: _motion(context),
                  curve: Curves.easeInOutCubic,
                  left: total == 0
                      ? 0
                      : constraints.maxWidth *
                            segments
                                .take(i)
                                .fold<double>(
                                  0,
                                  (sum, s) => sum + (s.value ?? 0),
                                ) /
                            total,
                  width: total == 0
                      ? 0
                      : constraints.maxWidth * (segments[i].value ?? 0) / total,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(color: segments[i].color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class UsageCalendar extends StatefulWidget {
  final UsageDaily daily;
  final String? selected;
  final ValueChanged<UsageDay> onSelected;
  const UsageCalendar({
    super.key,
    required this.daily,
    required this.selected,
    required this.onSelected,
  });
  @override
  State<UsageCalendar> createState() => _UsageCalendarState();
}

class _UsageCalendarState extends State<UsageCalendar> {
  late int _page;
  int get _pages => (widget.daily.days.length / 91).ceil();
  @override
  void initState() {
    super.initState();
    _page = _pages - 1;
  }

  @override
  void didUpdateWidget(UsageCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.daily.days.first.date != widget.daily.days.first.date ||
        oldWidget.daily.days.length != widget.daily.days.length) {
      _page = _pages - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.daily.days;
    // Work backwards so the latest page is full, including for 365D.
    final end = all.length - (_pages - 1 - _page) * 91;
    final start = math.max(0, end - 91);
    final days = all.sublist(start, end);
    final maximum = all.fold<int>(
      0,
      (m, d) => math.max(m, d.tokens.total ?? 0),
    );
    final tokens = WingTokens.of(context);
    final locale = MaterialLocalizations.of(context);
    // Fixed-size cells keep the activity map compact at every phone width.
    // Longer ranges run top-to-bottom through Sunday-aligned week columns.
    const square = 12.0;
    const gap = 3.0;
    const pitch = square + gap;
    final weekly = all.length > 8;
    final offset = weekly ? days.first.date.weekday % 7 : 0;
    final columns = weekly ? ((days.length + offset) / 7).ceil() : days.length;
    Widget cell(UsageDay day) {
      final count = day.tokens.total;
      final selected = day.id == widget.selected;
      final color = count == null
          ? tokens.raised
          : count == 0
          ? tokens.border.withValues(alpha: .45)
          : Color.lerp(
              tokens.raised,
              tokens.accent,
              .25 + .75 * math.sqrt(count / math.max(maximum, 1)),
            )!;
      final label =
          '${locale.formatFullDate(day.date)}: ${count == null ? 'tokens unavailable' : '${locale.formatDecimal(count)} tokens'}';
      return Semantics(
        label: label,
        button: true,
        selected: selected,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('usage-day-${day.id}'),
              borderRadius: BorderRadius.circular(4),
              onTap: () => widget.onSelected(day),
              child: Align(
                alignment: Alignment.topLeft,
                child: AnimatedContainer(
                  duration: _motion(context),
                  width: square,
                  height: square,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                    border: selected
                        ? Border.all(color: tokens.onSurface, width: 1.5)
                        : null,
                  ),
                  child: count == null
                      ? Icon(Icons.question_mark, size: 9, color: tokens.muted)
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${locale.formatShortDate(days.first.date)} – ${locale.formatShortDate(days.last.date)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_pages > 1) ...[
              IconButton(
                tooltip: 'Earlier dates',
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Later dates',
                onPressed: _page < _pages - 1
                    ? () => setState(() => _page++)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            key: const ValueKey('usage-activity-grid'),
            width: columns * pitch - gap,
            height: (weekly ? 7 : 1) * pitch - gap,
            child: Column(
              children: [
                for (var row = 0; row < (weekly ? 7 : 1); row++)
                  SizedBox(
                    height: row == (weekly ? 6 : 0) ? square : pitch,
                    child: Row(
                      children: [
                        for (var col = 0; col < columns; col++)
                          SizedBox(
                            width: col == columns - 1 ? square : pitch,
                            child:
                                (weekly ? col * 7 + row - offset : col) >= 0 &&
                                    (weekly ? col * 7 + row - offset : col) <
                                        days.length
                                ? cell(
                                    days[weekly ? col * 7 + row - offset : col],
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              'Tokens · UTC session-start dates',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Less', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 6),
                for (var i = 0; i < 5; i++)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        tokens.border.withValues(alpha: .45),
                        tokens.accent,
                        i / 4,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: 3),
                Text('More', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class UsageAreaChart extends StatelessWidget {
  final UsageDaily daily;
  final String? selected;
  const UsageAreaChart({
    super.key,
    required this.daily,
    required this.selected,
  });
  @override
  Widget build(BuildContext context) {
    final days = daily.days;
    final maximum = days.fold<int>(
      0,
      (m, d) => math.max(m, d.tokens.total ?? 0),
    );
    final locale = MaterialLocalizations.of(context);
    final colors = usageColors(context).take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${compactUsage(maximum)} tokens / day',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Semantics(
          label:
              'Stacked daily token chart. Uncached input, cached input and output. Select a date in the usage grid for exact values.',
          image: true,
          child: SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _AreaPainter(
                days,
                selected,
                colors,
                WingTokens.of(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(
              locale.formatShortMonthDay(days.first.date),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              locale.formatShortMonthDay(days.last.date),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (var i = 0; i < 3; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[i],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      usageTokenLabels[i],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _AreaPainter extends CustomPainter {
  final List<UsageDay> days;
  final String? selected;
  final List<Color> colors;
  final WingTokens tokens;
  _AreaPainter(this.days, this.selected, this.colors, this.tokens);
  @override
  void paint(Canvas canvas, Size size) {
    final maximum = math.max(
      1,
      days.fold<int>(0, (m, d) => math.max(m, d.tokens.total ?? 0)),
    );
    final grid = Paint()
      ..color = tokens.border.withValues(alpha: .6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    double x(int i) => size.width * i / math.max(1, days.length - 1);
    double y(int i, int count) =>
        size.height *
        (1 -
            days[i].tokens.values
                    .take(count)
                    .fold<int>(0, (sum, n) => sum + n!) /
                maximum);
    for (var type = 0; type < 3; type++) {
      final path = Path()..moveTo(x(0), y(0, type));
      for (var i = 0; i < days.length; i++) {
        path.lineTo(x(i), y(i, type + 1));
      }
      for (var i = days.length - 1; i >= 0; i--) {
        path.lineTo(x(i), y(i, type));
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = colors[type].withValues(alpha: .82),
      );
    }
    final index = days.indexWhere((day) => day.id == selected);
    if (index >= 0) {
      canvas.drawLine(
        Offset(x(index), 0),
        Offset(x(index), size.height),
        Paint()
          ..color = tokens.onSurface
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_AreaPainter oldDelegate) => true;
}
