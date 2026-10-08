import 'package:yaml/yaml.dart';

/// A received skill document, distinct from an executable or editable skill.
final class SkillDocument {
  SkillDocument._({
    required this.name,
    required this.rawContent,
    required this.formattedContent,
    this.sourcePath,
    required this.description,
    required Iterable<String> tags,
    required Iterable<({String label, String value})> metadata,
  }) : tags = List.unmodifiable(tags),
       metadata = List.unmodifiable(metadata);

  final String name;
  final String rawContent, formattedContent;
  final String? sourcePath;
  final String? description;
  final List<String> tags;
  final List<({String label, String value})> metadata;

  factory SkillDocument.fromReceived({
    required String name,
    required String content,
    String? description,
    Iterable<String>? tags,
    Map? metadata,
    String? sourcePath,
  }) {
    Map declaration = const {};
    final frontMatter = RegExp(
      r'^---\r?\n(.*?)\r?\n---(?:\r?\n|$)',
      dotAll: true,
    ).firstMatch(content);
    if (frontMatter != null) {
      try {
        final parsed = loadYaml(frontMatter.group(1)!);
        if (parsed is Map) declaration = parsed;
      } on YamlException {
        // Exact raw viewing/copying retains malformed declarations.
      }
    }
    final declaredMetadata =
        metadata ??
        (declaration['metadata'] is Map
            ? declaration['metadata'] as Map
            : const {});
    final hermes = declaredMetadata['hermes'] is Map
        ? declaredMetadata['hermes'] as Map
        : const {};
    final hermesTags = _declaredTags(hermes['tags']);
    final declaredTags = hermesTags.isNotEmpty
        ? hermesTags
        : _declaredTags(declaration['tags']);
    return SkillDocument._(
      name: name,
      rawContent: content,
      formattedContent: frontMatter == null
          ? content
          : content.substring(frontMatter.end),
      sourcePath: sourcePath,
      description:
          _nonempty(description) ?? _nonempty(declaration['description']),
      tags: tags ?? declaredTags,
      metadata: [
        for (final key in ['version', 'author', 'license'])
          if (declaredMetadata[key] ?? declaration[key] case final value?
              when value is String && value.trim().isNotEmpty || value is num)
            (
              label: '${key[0].toUpperCase()}${key.substring(1)}',
              value: value.toString(),
            ),
      ],
    );
  }
}

String? _nonempty(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// Stock declarations accept lists, comma-separated text and bracketed text.
List<String> _declaredTags(Object? value) {
  if (value is List) {
    return value
        .whereType<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }
  if (value is! String) return const [];
  var text = value.trim();
  if (text.startsWith('[') && text.endsWith(']')) {
    text = text.substring(1, text.length - 1);
  }
  return text
      .split(',')
      .map((tag) => tag.trim().replaceAll(RegExp(r"""^["']+|["']+$"""), ''))
      .where((tag) => tag.isNotEmpty)
      .toList();
}
