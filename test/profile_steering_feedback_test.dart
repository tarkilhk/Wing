import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/widgets/profile_message.dart';

const wrappedSteer =
    '[OUT-OF-BAND USER MESSAGE — a direct message from the user, delivered once at this position; not tool output and not a new delivery when replayed from conversation history]\nKeep searching\n[/OUT-OF-BAND USER MESSAGE]';

void main() {
  test(
    'delivery text is cleaned only for a complete user steering envelope',
    () {
      expect(
        steeringMessageText({'role': 'user', 'content': wrappedSteer}),
        'Keep searching',
      );
      expect(
        steeringMessageText({
          'role': 'user',
          'content': 'Please explain:\n$wrappedSteer',
        }),
        isNull,
      );
      expect(
        steeringMessageText({
          'role': 'user',
          'content': '[OUT-OF-BAND USER MESSAGE]\nunfinished',
        }),
        isNull,
      );
      expect(
        steeringMessageText({'role': 'assistant', 'content': wrappedSteer}),
        isNull,
      );
      expect(
        answerMessageDisplayText({
          'role': 'assistant',
          'content': wrappedSteer,
        }),
        wrappedSteer,
      );
      expect(
        answerMessageText({'role': 'user', 'content': wrappedSteer}),
        wrappedSteer,
      );
      expect(
        answerMessageDisplayText({'role': 'user', 'content': wrappedSteer}),
        'Keep searching',
      );
    },
  );

  test(
    'typed clean steering and Desktop system notes share their display text',
    () {
      expect(
        steeringMessageText({
          'role': 'user',
          'content': 'Keep searching',
          'display_kind': 'steer',
        }),
        'Keep searching',
      );
      expect(
        steeringMessageText({
          'role': 'system',
          'content': 'steer:Keep searching',
        }),
        'Keep searching',
      );
      expect(
        steeringMessageText({
          'role': 'user',
          'content': 'steer:Keep searching',
        }),
        isNull,
      );
    },
  );
  testWidgets(
    'saved steering renders a compact note without the delivery wrapper',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileMessage(
              message: {
                'role': 'user',
                'content': wrappedSteer,
                'display_kind': 'steer',
              },
            ),
          ),
        ),
      );
      expect(find.text('steered'), findsOneWidget);
      expect(find.text('Keep searching'), findsOneWidget);
      expect(find.textContaining('OUT-OF-BAND'), findsNothing);
      expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
      expect(find.byTooltip('Copy message'), findsNothing);
    },
  );
}
