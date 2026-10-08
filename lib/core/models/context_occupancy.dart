/// One server-estimated component of the session's context window.
class ContextCategory {
  const ContextCategory({
    required this.id,
    required this.label,
    required this.tokens,
  });

  final String id;
  final String label;
  final int tokens;

  static ContextCategory? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final label = value['label'];
    final tokens = value['tokens'];
    if (id is! String ||
        id.trim().isEmpty ||
        label is! String ||
        label.trim().isEmpty ||
        tokens is! num ||
        !tokens.isFinite ||
        tokens < 0) {
      return null;
    }
    return ContextCategory(id: id, label: label, tokens: tokens.round());
  }
}

/// Server-reported occupancy and estimated composition for one session.
class ContextOccupancy {
  final int used;
  final int max;
  final double percent;
  final bool estimated;
  final List<ContextCategory> categories;

  ContextOccupancy({
    required this.used,
    required this.max,
    required this.percent,
    this.estimated = false,
    Iterable<ContextCategory> categories = const [],
  }) : categories = List.unmodifiable(categories);

  /// Live usage invalidates an idle composition without replacing measured
  /// occupancy with a sum of the category estimates.
  ContextOccupancy withoutCategories() => ContextOccupancy(
    used: used,
    max: max,
    percent: percent,
    estimated: estimated,
  );

  /// Parses only authoritative server values. Missing or unusable limits make
  /// occupancy unknown rather than encouraging a phone-owned estimate.
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
      categories: value['categories'] is List
          ? (value['categories'] as List)
                .map(ContextCategory.fromJson)
                .whereType<ContextCategory>()
          : const [],
    );
  }

  static double? _finiteNum(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return value.toDouble();
  }
}
