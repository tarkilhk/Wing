import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:wing/core/services/markdown_parse_worker.dart';

Object ast(md.Node node) => node is md.Text
    ? ['text', node.text]
    : [
        (node as md.Element).tag,
        node.attributes,
        node.generatedId,
        node.footnoteLabel,
        node.children?.map(ast).toList(),
      ];

void main() {
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
      expect(second.nodes.map(ast), stock.map(ast));
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
