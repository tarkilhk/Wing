class SlashInvocation {
  final String name;
  final String argument;
  const SlashInvocation(this.name, this.argument);

  static SlashInvocation? parse(String text) {
    final match = RegExp(
      r'^/([^\s/]+)(?:\s+([\s\S]*))?$',
    ).firstMatch(text.trim());
    return match == null ? null : SlashInvocation(match[1]!, match[2] ?? '');
  }
}

class SlashCommand {
  final String text;
  final String description;
  final String category;
  const SlashCommand(this.text, this.description, this.category);
}

/// The gateway owns the catalog, including user commands, plugins and skills.
class SlashCatalog {
  final List<SlashCommand> commands;
  final Map<String, String> canonical;
  final Map<String, dynamic> metadata;
  final String warning;
  const SlashCatalog(
    this.commands,
    this.canonical,
    this.metadata,
    this.warning,
  );

  static String _withSlash(String name) =>
      name.startsWith('/') ? name : '/$name';

  factory SlashCatalog.fromJson(Map<String, dynamic> value) {
    final pairs = value['pairs'];
    if (pairs is! List) throw const FormatException('Missing command catalog');
    final categories = <String, String>{};
    for (final category in (value['categories'] as List? ?? [])) {
      for (final pair in category['pairs'] as List) {
        categories[_withSlash(pair[0] as String)] = category['name'] as String;
      }
    }
    // Hermes appends skills to pairs and supplies their identity separately;
    // they are not included in the registry's categories array.
    for (final name in (value['skills'] as Map? ?? {}).keys) {
      categories[_withSlash(name as String)] = 'Skills';
    }
    return SlashCatalog(
      pairs.map((pair) {
        if (pair is! List ||
            pair.length != 2 ||
            pair[0] is! String ||
            pair[1] is! String) {
          throw const FormatException('Invalid command catalog entry');
        }
        final name = _withSlash(pair[0]);
        return SlashCommand(name, pair[1], categories[name] ?? 'Commands');
      }).toList(),
      Map<String, String>.from(value['canon'] as Map? ?? {}).map(
        (key, value) =>
            MapEntry(_withSlash(key).toLowerCase(), _withSlash(value)),
      ),
      Map<String, dynamic>.from(value['commands'] as Map? ?? {}),
      value['warning'] as String? ?? '',
    );
  }

  String resolve(String name) =>
      (canonical['/${name.toLowerCase()}'] ?? '/$name').substring(1);

  String? unavailable(String name) {
    final entry = metadata['/$name'];
    final desktop = entry is Map ? entry['desktop'] : null;
    return switch (desktop) {
      'terminal' => '/$name requires the Hermes terminal.',
      'messaging' =>
        '/$name is only available through a Hermes messaging integration.',
      'composer-voice' =>
        'This command records audio on the Hermes host. Phone voice control is not available in this workspace.',
      _ => null,
    };
  }

  List<SlashCommand> search(String text) {
    final query = text.replaceFirst(RegExp(r'^/'), '').toLowerCase();
    return commands
        .where(
          (c) =>
              c.text.toLowerCase().contains(query) ||
              c.description.toLowerCase().contains(query) ||
              canonical.entries.any(
                (e) => e.value == c.text && e.key.contains(query),
              ),
        )
        .toList();
  }
}

/// One immutable response for the exact query before the Flutter cursor.
/// Protocol offsets count Unicode code points; replacement offsets count UTF-16.
class SlashCompletion {
  SlashCompletion._(
    this.query,
    Iterable<SlashCommand> items,
    this.replaceFrom,
    this.warning,
  ) : items = List.unmodifiable(items);

  final String query;
  final List<SlashCommand> items;
  final int replaceFrom;
  final String warning;

  static bool isQuery(String query) => query.startsWith('/');
  static bool usesCatalog(String query) => !query.contains(RegExp(r'\s'));
  bool get showsNoMatches => items.isEmpty && !query.contains(' ');

  factory SlashCompletion.fromCatalog(String query, SlashCatalog catalog) =>
      SlashCompletion._(query, catalog.search(query), 0, catalog.warning);

  factory SlashCompletion.fromJson(
    String query,
    Map<String, dynamic> value, {
    required String warning,
  }) {
    final rows = value['items'];
    final offset = value['replace_from'];
    final codePoints = query.runes;
    if (rows is! List ||
        offset is! int ||
        offset < 0 ||
        offset > codePoints.length) {
      throw const FormatException('Invalid slash completion');
    }
    final items = <SlashCommand>[];
    for (final row in rows) {
      if (row is! Map ||
          row['text'] is! String ||
          (row['meta'] != null && row['meta'] is! String)) {
        throw const FormatException('Invalid slash completion item');
      }
      items.add(
        SlashCommand(row['text'] as String, row['meta'] as String? ?? '', ''),
      );
    }
    return SlashCompletion._(
      query,
      items,
      String.fromCharCodes(codePoints.take(offset)).length,
      warning,
    );
  }

  /// Selection applies only to this query and an item issued by this response.
  /// Cursor extraction is rendering work; insertion and suffix rules live here.
  SlashCompletionEdit? select(
    SlashCommand item, {
    required String text,
    required int cursor,
  }) {
    if (cursor < 0 ||
        cursor > text.length ||
        text.substring(0, cursor) != query ||
        !items.any((issued) => identical(issued, item))) {
      return null;
    }
    final suffix = text.substring(cursor);
    final insertion = '${item.text}${suffix.startsWith(' ') ? '' : ' '}';
    return SlashCompletionEdit._(
      text.replaceRange(replaceFrom, cursor, insertion),
      replaceFrom + insertion.length,
    );
  }
}

class SlashCompletionEdit {
  const SlashCompletionEdit._(this.text, this.cursor);
  final String text;
  final int cursor;
}
