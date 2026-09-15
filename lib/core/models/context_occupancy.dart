/// Server-reported context-window occupancy for one session.
class ContextOccupancy {
  final int used;
  final int max;
  final double percent;
  final bool estimated;

  const ContextOccupancy({
    required this.used,
    required this.max,
    required this.percent,
    this.estimated = false,
  });

  /// Parses only authoritative server values. Missing or unusable limits make
  /// the fuse unknown rather than encouraging a phone-owned estimate.
  static ContextOccupancy? fromJson(Map<String, dynamic>? value) {
    if (value == null) return null;
    final used = _finiteNum(value['context_used']);
    final max = _finiteNum(value['context_max']);
    final percent = _finiteNum(value['context_percent']);
    if (used == null ||
        max == null ||
        percent == null ||
        max <= 0 ||
        used < 0) {
      return null;
    }
    return ContextOccupancy(
      used: used.round(),
      max: max.round(),
      percent: percent.clamp(0, 100).toDouble(),
      estimated: value['context_estimated'] == true,
    );
  }

  static double? _finiteNum(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return value.toDouble();
  }
}
