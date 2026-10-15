import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_question.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/hermes_question_card.dart';
import 'package:wing/core/widgets/source_code_block.dart';

HermesQuestion question(HermesQuestionStatus status) => HermesQuestion(
  id: 'approval/request',
  requestId: 'request',
  kind: HermesQuestionKind.approval,
  status: status,
  timestamp: DateTime(2026, 10, 15, 13, 27),
  description: 'Inspect the selected source',
  command: 'cat selected.txt',
  sender: 'Research bot',
);

Future<void> showQuestion(
  WidgetTester tester,
  HermesQuestion value, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: wingTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: HermesQuestionCard(question: value)),
    ),
  ),
);

void main() {
  for (final (status, label) in [
    (HermesQuestionStatus.pending, 'Pending'),
    (HermesQuestionStatus.approved, 'Approved'),
    (HermesQuestionStatus.rejected, 'Rejected'),
    (HermesQuestionStatus.answered, 'Answered'),
    (HermesQuestionStatus.expired, 'Expired'),
    (HermesQuestionStatus.cancelled, 'Cancelled'),
    (HermesQuestionStatus.closed, 'Closed'),
  ]) {
    testWidgets('history reports the $label outcome without live controls', (
      tester,
    ) async {
      await showQuestion(tester, question(status));
      expect(find.text('Hermes question - $label'), findsOneWidget);
      expect(find.textContaining('Research bot'), findsOneWidget);
      // A recorded pending request is historical information; response
      // authority belongs to the live request owner and its separate controls.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Allow once'), findsNothing);
      expect(find.byTooltip('Confirm answer and continue'), findsNothing);
    });
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'question details disclose and retire at ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final value = question(HermesQuestionStatus.expired);
          await showQuestion(
            tester,
            value,
            brightness: brightness,
            scale: scale,
          );
          expect(find.byType(SourceCodeBlock), findsNothing);
          expect(find.text(value.description), findsNothing);

          await tester.tap(find.text('Hermes question - Expired'));
          await tester.pumpAndSettle();
          expect(find.text(value.description), findsOneWidget);
          expect(find.byType(SourceCodeBlock), findsOneWidget);
          expect(
            tester.widget<SourceCodeBlock>(find.byType(SourceCodeBlock)).code,
            'cat selected.txt',
          );
          await tester.ensureVisible(find.byTooltip('Copy code'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Copy code').hitTestable(), findsOneWidget);

          await tester.ensureVisible(find.text('Hermes question - Expired'));
          await tester.tap(find.text('Hermes question - Expired'));
          await tester.pumpAndSettle();
          expect(find.byType(SourceCodeBlock), findsNothing);
          expect(find.text(value.description), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('settled observation updates the expanded history in place', (
    tester,
  ) async {
    final pending = question(HermesQuestionStatus.pending);
    await showQuestion(tester, pending);
    await tester.tap(find.text('Hermes question - Pending'));
    await tester.pumpAndSettle();

    await showQuestion(
      tester,
      pending.withStatus(HermesQuestionStatus.approved),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hermes question - Pending'), findsNothing);
    expect(find.text('Hermes question - Approved'), findsOneWidget);
    expect(find.text(pending.description), findsOneWidget);
    expect(find.byType(SourceCodeBlock), findsOneWidget);
  });

  testWidgets(
    'a clarification without a command has only its authored details',
    (tester) async {
      final value = HermesQuestion(
        id: 'clarification/request',
        requestId: 'request',
        kind: HermesQuestionKind.clarification,
        status: HermesQuestionStatus.answered,
        timestamp: DateTime(2026, 10, 15),
        description: 'Which source should I inspect?',
      );
      await showQuestion(tester, value);
      await tester.tap(find.text('Hermes question - Answered'));
      await tester.pumpAndSettle();
      expect(find.text(value.description), findsOneWidget);
      expect(find.byType(SourceCodeBlock), findsNothing);
      expect(find.byTooltip('Copy code'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );
}
