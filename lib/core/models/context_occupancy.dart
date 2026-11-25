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

enum PromptCacheConfidence { proven, declared, assumed, unknown }

/// A server report about a cached prompt prefix, independent of occupancy.
/// Dates describe the reported event; this value does not infer current warmth.
class PromptCacheWindow {
  PromptCacheWindow._({
    required this.guaranteedUntil,
    required this.estimatedUntil,
    required this.refreshedAt,
    required this.tier,
    required this.confidence,
    required this.reason,
    required Map<String, DateTime> coverage,
    required this.warmingOff,
    required this.tierPending,
    required this.learned,
  }) : coverage = Map.unmodifiable(coverage);

  final DateTime? guaranteedUntil, estimatedUntil, refreshedAt;
  final String? tier, reason, learned;
  final PromptCacheConfidence confidence;
  final Map<String, DateTime> coverage;
  final bool? warmingOff, tierPending;

  static PromptCacheWindow? fromJson(Object? value) {
    if (value is! Map) return null;
    final coverage = <String, DateTime>{};
    if (value['coverage'] case final Map supplied) {
      for (final entry in supplied.entries) {
        final tier = _text(entry.key);
        final deadline = _date(entry.value);
        if (tier != null && deadline != null) coverage[tier] = deadline;
      }
    }
    return PromptCacheWindow._(
      guaranteedUntil: _date(value['guaranteed_until']),
      estimatedUntil: _date(value['estimated_until']),
      refreshedAt: _date(value['refreshed_at']),
      tier: _text(value['tier']),
      confidence: switch (value['confidence']) {
        'proven' => PromptCacheConfidence.proven,
        'declared' => PromptCacheConfidence.declared,
        'assumed' => PromptCacheConfidence.assumed,
        _ => PromptCacheConfidence.unknown,
      },
      reason: _text(value['reason']),
      coverage: coverage,
      warmingOff: value['warming_off'] is bool
          ? value['warming_off'] as bool
          : null,
      tierPending: value['tier_pending'] is bool
          ? value['tier_pending'] as bool
          : null,
      learned: _text(value['learned']),
    );
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static DateTime? _date(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value < -8640000000000 ||
        value > 8640000000000) {
      return null;
    }
    final milliseconds = value * 1000;
    if (!milliseconds.isFinite || milliseconds.abs() > 8640000000000000) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds.round(),
      isUtc: true,
    );
  }
}

/// Server-reported occupancy and estimated composition for one session.
class ContextOccupancy {
  final int used;
  final int max;
  final double percent;
  final bool estimated;
  final int? configuredMax;
  bool get pinned => configuredMax != null && configuredMax == max;
  final List<ContextCategory> categories;

  ContextOccupancy({
    required this.used,
    required this.max,
    required this.percent,
    this.estimated = false,
    this.configuredMax,
    Iterable<ContextCategory> categories = const [],
  }) : categories = List.unmodifiable(categories);

  /// Composition is a separate server estimate, never a replacement for the
  /// latest reported occupancy.
  ContextOccupancy withCategories(Iterable<ContextCategory> categories) =>
      ContextOccupancy(
        used: used,
        max: max,
        percent: percent,
        estimated: estimated,
        configuredMax: configuredMax,
        categories: categories,
      );

  ContextOccupancy withoutCategories() => withCategories(const []);

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
      configuredMax: switch (value['config_context_length']) {
        final int length when length > 0 => length,
        _ => null,
      },
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
