/// Benchmark variants exist only on the isolated QA branch.
enum MarkdownQaVariant { baseline, guard, cache, background }

MarkdownQaVariant get markdownQaVariant => switch (const String.fromEnvironment(
  'WING_QA_MARKDOWN_VARIANT',
  defaultValue: 'baseline',
)) {
  'baseline' => MarkdownQaVariant.baseline,
  'guard' => MarkdownQaVariant.guard,
  'cache' => MarkdownQaVariant.cache,
  'background' => MarkdownQaVariant.background,
  _ => throw StateError('Unknown QA Markdown variant.'),
};
