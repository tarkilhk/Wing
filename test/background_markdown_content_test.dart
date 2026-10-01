import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:wing/core/services/markdown_parse_worker.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';
import 'package:wing/core/widgets/studio_error.dart';

void main() {
  testWidgets('grammar changes reparse identical source before rendering', (
    tester,
  ) async {
    final jobs = <Completer<MarkdownParseResult>>[];
    Future<MarkdownParseResult> parse(String source) {
      final result = Completer<MarkdownParseResult>();
      jobs.add(result);
      return result.future;
    }

    Widget host(bool deliverables) => Directionality(
      textDirection: TextDirection.ltr,
      child: BackgroundMarkdownContent(
        data: 'Same source',
        deliverables: deliverables,
        parse: parse,
        builder: (text, _) => Text(text),
      ),
    );
    await tester.pumpWidget(host(true));
    jobs.first.complete(const MarkdownParseResult([], 1, 0, 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('Same source'), findsOneWidget);
    await tester.pumpWidget(host(false));
    expect(jobs, hasLength(2));
    expect(find.text('Same source'), findsNothing);
    jobs.last.complete(const MarkdownParseResult([], 1, 0, 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('Same source'), findsOneWidget);
  });

  testWidgets(
    'failed parse retries on new data and disposal ignores late work',
    (tester) async {
      final jobs = <Completer<MarkdownParseResult>>[];
      Future<MarkdownParseResult> parse(String source) {
        final result = Completer<MarkdownParseResult>();
        jobs.add(result);
        return result.future;
      }

      Widget host(String data) => Directionality(
        textDirection: TextDirection.ltr,
        child: BackgroundMarkdownContent(
          data: data,
          deliverables: false,
          parse: parse,
          builder: (text, _) => Text(text),
        ),
      );
      await tester.pumpWidget(host('A'));
      final state = tester.state<BackgroundMarkdownContentState>(
        find.byType(BackgroundMarkdownContent),
      );
      expect(state.pending, isTrue);
      jobs.first.completeError(StateError('Injected failure'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(StudioError), findsOneWidget);
      // A terminal failure must not keep restoration or test waiters pending.
      expect(state.pending, isFalse);
      await tester.pumpWidget(host('AB'));
      expect(state.pending, isTrue);
      jobs.last.complete(const MarkdownParseResult([], 1, 0, 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('AB'), findsOneWidget);
      expect(find.byType(StudioError), findsNothing);
      expect(state.pending, isFalse);
      await tester.pumpWidget(host('ABC'));
      await tester.pumpWidget(const SizedBox());
      jobs.last.complete(const MarkdownParseResult([], 1, 0, 1));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'latest update waits behind one parse while completed progress stays visible',
    (tester) async {
      final jobs = <(String, Completer<MarkdownParseResult>)>[];
      Future<MarkdownParseResult> parse(String source) {
        final result = Completer<MarkdownParseResult>();
        jobs.add((source, result));
        return result.future;
      }

      Widget host(String source) => Directionality(
        textDirection: TextDirection.ltr,
        child: BackgroundMarkdownContent(
          data: source,
          deliverables: false,
          parse: parse,
          builder: (text, _) => Text(text),
        ),
      );
      await tester.pumpWidget(host('A'));
      await tester.pumpWidget(host('AB'));
      await tester.pumpWidget(host('ABC'));
      expect(jobs.map((job) => job.$1), ['A']);
      jobs.first.$2.complete(MarkdownParseResult([md.Text('A')], 1, 0, 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('A'), findsOneWidget);
      expect(jobs.map((job) => job.$1), ['A', 'ABC']);
      jobs.last.$2.complete(MarkdownParseResult([md.Text('ABC')], 1, 0, 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('ABC'), findsOneWidget);
      expect(
        tester
            .state<BackgroundMarkdownContentState>(
              find.byType(BackgroundMarkdownContent),
            )
            .pending,
        isFalse,
      );
    },
  );

  testWidgets('replacement rejects a late result from a different snapshot', (
    tester,
  ) async {
    final jobs = <Completer<MarkdownParseResult>>[];
    Future<MarkdownParseResult> parse(String source) {
      final result = Completer<MarkdownParseResult>();
      jobs.add(result);
      return result.future;
    }

    Widget host(String source) => Directionality(
      textDirection: TextDirection.ltr,
      child: BackgroundMarkdownContent(
        data: source,
        deliverables: false,
        parse: parse,
        builder: (text, _) => Text(text),
      ),
    );
    await tester.pumpWidget(host('Old message'));
    await tester.pumpWidget(host('Replacement'));
    jobs.last.complete(MarkdownParseResult([md.Text('Replacement')], 1, 0, 1));
    await tester.pump();
    await tester.pump();
    jobs.first.complete(MarkdownParseResult([md.Text('Old message')], 1, 0, 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('Replacement'), findsOneWidget);
    expect(find.text('Old message'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'backgrounding cancels display publication and resumes latest source',
    (tester) async {
      final jobs = <(String, Completer<MarkdownParseResult>)>[];
      Future<MarkdownParseResult> parse(String source) {
        final result = Completer<MarkdownParseResult>();
        jobs.add((source, result));
        return result.future;
      }

      Widget host(String source) => Directionality(
        textDirection: TextDirection.ltr,
        child: BackgroundMarkdownContent(
          data: source,
          deliverables: false,
          parse: parse,
          builder: (text, _) => Text(text),
        ),
      );
      await tester.pumpWidget(host('A'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(host('ABC'));
      jobs.first.$2.complete(MarkdownParseResult([md.Text('A')], 1, 0, 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('A'), findsNothing);
      expect(jobs, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(jobs.last.$1, 'ABC');
      jobs.last.$2.complete(MarkdownParseResult([md.Text('ABC')], 1, 0, 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('ABC'), findsOneWidget);
    },
  );
}
