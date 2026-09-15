import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  testWidgets(
    'incoming question shows choices inline and confirms explicitly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final host = Host();
      final controller = ProfileWorkspaceController(
        connection: identityTestConnection(),
        connectionIdentity: 'test-identity',
        preferences: await SharedPreferences.getInstance(),
        gatewayFactory: host.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.createChat();
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      host.event('a', 'clarify', {
        'request_id': 'request',
        'questions': [
          {
            'qid': 'q0',
            'question': 'Which review should I run?',
            'choices': ['Detailed review', 'Quick review'],
          },
        ],
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('Detailed review'), findsOneWidget);
      expect(find.text('Quick review'), findsOneWidget);
      expect(find.text('Reply'), findsNothing);
      await tester.tap(find.text('Quick review'));
      await tester.pump();
      expect(host.calls.where((c) => c.$2 == 'clarify.lock'), isEmpty);
      await tester.ensureVisible(find.byKey(const Key('clarify-continue')));
      await tester.tap(find.byKey(const Key('clarify-continue')));
      await tester.pump();
      expect(host.calls.last.$2, 'clarify.lock');
      expect(host.calls.last.$3['question_id'], 'q0');
      expect(host.calls.last.$3['request_id'], 'request');
      expect(host.calls.last.$3['answer'], 'Quick review');
      expect(host.calls.last.$3['profile'], 'a');
      expect(find.text('Quick review'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
