import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:wing/core/services/markdown_segments.dart';

Object _value(MarkdownSegment segment) => switch (segment) {
  MarkdownProseSegment() => ['prose', segment.source],
  MarkdownFenceSegment() => [
    'fence',
    segment.code,
    segment.language,
    segment.closed,
  ],
};

void main() {
  // Digests freeze the original scanner's outputs for every source prefix,
  // including incomplete opening/info/closing lines. Full-source expectations
  // below also document the grammar cases directly.
  final fixtures = <String, String>{
    'Before\n```dart extra\none\n```\nAfter':
        'd4f823e4565faf1b4fa74a703bdf380143b33dc029dc2d82f1641f216a74aebd',
    '  ~~~~txt\r\none\r\n~~~\r\ntwo\r\n  ~~~~\t\r\nAfter':
        '61084c5fd9fb40e48f5e8f2df679417a0869c33ed750914fd561c47fb65f46db',
    '````md\n```\nembedded\n````\n':
        '00de0da582794811c63f652bb1e2c88e00b933abd2494d9e4ad8cf0b7ed9c75c',
    'Inline ``` stays prose\n    ```dart\nindented\n    ```\nTail\n~~~\nopen':
        'b40ac0ba0a3f38210f75daa748a2a8f7e5979ea8d0ca880be28cf18e5ea8b847',
  };
  for (final (index, entry) in fixtures.entries.indexed) {
    test(
      'original grammar remains exact at every prefix for fixture $index',
      () {
        final outputs = [
          for (var end = 0; end <= entry.key.length; end++)
            splitMarkdownSegments(
              entry.key.substring(0, end),
            ).map(_value).toList(),
        ];
        expect(
          sha256.convert(utf8.encode(jsonEncode(outputs))).toString(),
          entry.value,
        );
      },
    );
  }

  test('code and surrounding source retain exact whitespace and metadata', () {
    expect(
      splitMarkdownSegments(
        'Before\n```dart extra\none\n```\nAfter',
      ).map(_value),
      [
        ['prose', 'Before\n'],
        ['fence', 'one\n', 'dart', true],
        ['prose', '\nAfter'],
      ],
    );
    expect(
      splitMarkdownSegments(
        '  ~~~~txt\r\none\r\n~~~\r\ntwo\r\n  ~~~~\t\r\nAfter',
      ).map(_value),
      [
        ['fence', 'one\r\n~~~\r\ntwo\r\n', 'txt', true],
        ['prose', '\nAfter'],
      ],
    );
    expect(splitMarkdownSegments('````md\n```\nembedded\n````\n').map(_value), [
      ['fence', '```\nembedded\n', 'md', true],
      ['prose', '\n'],
    ]);
    expect(splitMarkdownSegments('inline ``` stays prose').map(_value), [
      ['prose', 'inline ``` stays prose'],
    ]);
    expect(splitMarkdownSegments('~~~sh\necho hello').map(_value), [
      ['fence', 'echo hello', 'sh', false],
    ]);
    expect(splitMarkdownSegments(''), isEmpty);
  });

  test(
    'copied preparation keeps metadata without sharing mutable AST nodes',
    () {
      final text = md.Text('original');
      final element = md.Element('p', [text])
        ..attributes['id'] = 'anchor'
        ..generatedId = 'generated'
        ..footnoteLabel = 'note';
      const fence = MarkdownFenceSegment(
        code: 'value\n',
        language: 'dart',
        closed: true,
      );
      final copied = copyMarkdownSegments([
        MarkdownProseSegment(source: 'original', nodes: [element]),
        fence,
      ]);
      final copiedElement =
          (copied.first as MarkdownProseSegment).nodes.single as md.Element;
      expect(copiedElement.attributes, {'id': 'anchor'});
      expect(copiedElement.generatedId, 'generated');
      expect(copiedElement.footnoteLabel, 'note');
      expect(copiedElement, isNot(same(element)));
      expect(copiedElement.children!.single, isNot(same(text)));
      expect(copied.last, same(fence));
      copiedElement.attributes.clear();
      copiedElement.children!.clear();
      expect(element.attributes, {'id': 'anchor'});
      expect(element.textContent, 'original');
    },
  );
}
