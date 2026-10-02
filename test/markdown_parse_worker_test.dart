import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:wing/core/services/markdown_parse_worker.dart';
import 'package:wing/core/services/markdown_segments.dart';
import 'package:wing/core/services/markdown_inline_parser.dart';

Object ast(md.Node node) => node is md.Text
    ? ['text', node.text]
    : [
        (node as md.Element).tag,
        Map<String, String>.of(node.attributes),
        node.generatedId,
        node.footnoteLabel,
        node.children?.map(ast).toList(),
      ];

void main() {
  test(
    'whole-message results carry exact fences and independently parsed prose',
    () async {
      final worker = MarkdownParseWorker();
      addTearDown(worker.dispose);
      const source =
          'Before **bold** and [label][ref].\n\n[ref]: https://example.test\n\n````dart\n```\nvalue\n````\nAfter [label][ref].\n\n~~~sh\necho hello';
      final result = await worker.parse(
        owner: 1,
        source: source,
        deliverables: false,
      );
      expect(result.segments, hasLength(4));
      final fences = result.segments.whereType<MarkdownFenceSegment>().toList();
      expect(fences.first.code, '```\nvalue\n');
      expect(fences.first.language, 'dart');
      expect(fences.first.closed, isTrue);
      expect(fences.last.code, 'echo hello');
      expect(fences.last.language, 'sh');
      expect(fences.last.closed, isFalse);
      for (final prose in result.segments.whereType<MarkdownProseSegment>()) {
        final stock = md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
          encodeHtml: false,
        ).parse(prose.source);
        expect(prose.nodes.map(ast), stock.map(ast));
      }
      final later = result.segments.whereType<MarkdownProseSegment>().last;
      expect(
        later.nodes.map((node) => node.textContent).join(),
        contains('[label][ref]'),
      );
      expect(result.fenceMicros, greaterThanOrEqualTo(0));
      expect(result.parseMicros, greaterThanOrEqualTo(0));
    },
  );

  test(
    'each prose segment retains its own inline cache and drops removed indices',
    () async {
      final worker = MarkdownParseWorker();
      addTearDown(worker.dispose);
      const before = 'First **fixed**.\n\nFirst tail';
      const after = '\nSecond **fixed**.\n\nSecond tail';
      const fence = '\n```dart\nvalue\n```';
      await worker.parse(
        owner: 1,
        source: '$before$fence$after',
        deliverables: false,
      );
      final growing = await worker.parse(
        owner: 1,
        source: '$before$fence$after grows',
        deliverables: false,
      );
      expect(growing.cacheHits, 1);
      expect(growing.inlineParses, 1);
      final changedFirst = await worker.parse(
        owner: 1,
        source: '$before grows$fence$after grows',
        deliverables: false,
      );
      expect(changedFirst.cacheHits, 1);
      expect(changedFirst.inlineParses, 1);
      await worker.parse(
        owner: 1,
        source: '$before grows\n',
        deliverables: false,
      );
      final restored = await worker.parse(
        owner: 1,
        source: '$before grows$fence$after returns',
        deliverables: false,
      );
      expect(restored.cacheHits, 0);
      expect(restored.inlineParses, 2);
    },
  );

  test(
    'UI AST mutations cannot corrupt isolate-retained completed segments',
    () async {
      final worker = MarkdownParseWorker();
      addTearDown(worker.dispose);
      const source =
          '# Heading **bold**\n\nRead [link](https://example.test).\n\n```dart\nvalue\n```\nTail';
      final first = await worker.parse(
        owner: 1,
        source: source,
        deliverables: false,
      );
      final prose = first.segments.whereType<MarkdownProseSegment>().first;
      final expected = prose.nodes.map(ast).toList();
      final heading = prose.nodes.first as md.Element;
      heading.attributes['id'] = 'mutated';
      heading.generatedId = 'mutated';
      heading.children!.clear();
      final second = await worker.parse(
        owner: 1,
        source: source,
        deliverables: false,
      );
      expect(
        second.segments.whereType<MarkdownProseSegment>().first.nodes.map(ast),
        expected,
      );
      expect(second.inlineParses, 0);
      final third = await worker.parse(
        owner: 1,
        source: '$source grows',
        deliverables: false,
      );
      expect(
        third.segments.whereType<MarkdownProseSegment>().first.nodes.map(ast),
        expected,
      );
    },
  );

  test(
    'configuration changes and owner release clear every segment cache',
    () async {
      final worker = MarkdownParseWorker();
      addTearDown(worker.dispose);
      const source =
          'Read [Report](/srv/report.md).\n\n```dart\nvalue\n```\nTail';
      await worker.parse(owner: 1, source: source, deliverables: false);
      final enabled = await worker.parse(
        owner: 1,
        source: source,
        deliverables: true,
      );
      final expected = MarkdownInlineParser(
        deliverables: true,
      ).parse((enabled.segments.first as MarkdownProseSegment).source);
      expect(
        (enabled.segments.first as MarkdownProseSegment).nodes.map(ast),
        expected.map(ast),
      );
      expect(enabled.cacheHits, 0);
      expect(enabled.inlineParses, greaterThan(0));
      await worker.parse(owner: 2, source: 'Keep', deliverables: false);
      worker.release(1);
      final fresh = await worker.parse(
        owner: 1,
        source: source,
        deliverables: true,
      );
      expect(fresh.cacheHits, 0);
      expect(fresh.inlineParses, enabled.inlineParses);
      worker.release(1);
      worker.release(2);
    },
  );

  test(
    'real reusable worker preserves Markdown and reuses completed inline text',
    () async {
      final worker = MarkdownParseWorker();
      addTearDown(worker.dispose);
      const source =
          'Completed **paragraph** and [link](https://example.test).\n\nTail';
      final first = await worker.parse(
        owner: 1,
        source: source,
        deliverables: false,
      );
      final second = await worker.parse(
        owner: 1,
        source: '$source grows',
        deliverables: false,
      );
      final stock = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      ).parse('$source grows');
      expect(second.segments.single, isA<MarkdownProseSegment>());
      expect(
        (second.segments.single as MarkdownProseSegment).nodes.map(ast),
        stock.map(ast),
      );
      expect(first.cacheHits, 0);
      expect(second.cacheHits, greaterThan(0));
      expect(second.inlineParses, 1);
      worker.release(1);
    },
  );

  test(
    'disposing during startup completes pending work instead of hanging',
    () async {
      final worker = MarkdownParseWorker();
      final pending = worker.parse(
        owner: 1,
        source: 'Text',
        deliverables: false,
      );
      final check = expectLater(pending, throwsStateError);
      await worker.dispose();
      await check;
      await expectLater(
        worker.parse(owner: 2, source: 'Other', deliverables: false),
        throwsStateError,
      );
    },
  );

  test(
    'release cancels its request and other owners retain their parser',
    () async {
      final worker = MarkdownParseWorker();
      addTearDown(worker.dispose);
      await worker.parse(owner: 2, source: 'Keep\n\nTail', deliverables: false);
      final pending = worker.parse(
        owner: 1,
        source: 'Canceled',
        deliverables: false,
      );
      final check = expectLater(pending, throwsStateError);
      worker.release(1);
      await check;
      final result = await worker.parse(
        owner: 2,
        source: 'Keep\n\nTail grows',
        deliverables: false,
      );
      expect(result.cacheHits, 1);
    },
  );
}
