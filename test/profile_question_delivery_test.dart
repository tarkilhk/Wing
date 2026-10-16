import 'package:wing/core/services/app_preferences.dart';
import 'dart:async';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'support/form_family_capture.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  setUpAll(loadFormFamilyFonts);
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'desktop-resolved question closes after a pending snapshot overtakes skip $brightness/$scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({});
          final host = Host();
          final preferences = await SharedPreferences.getInstance();
          final appPreferences = AppPreferences(preferences);
          addTearDown(appPreferences.dispose);
          final controller = ProfileWorkspaceController(
            access: ConnectionAccess(
              connection: identityTestConnection(),
              dashboardOAuth: null,
            ),
            connectionIdentity: 'test-identity',
            preferences: preferences,
            appPreferences: appPreferences,
            gatewayFactory: host.gateway,
          );
          addTearDown(controller.dispose);
          await controller.initialize();
          final chat = await controller.createChat(canDispatch: () => true);
          await tester.pumpWidget(
            RepaintBoundary(
              key: formFamilyCapture,
              child: MaterialApp(
                theme: profileWorkspaceTheme(ThemeData(brightness: brightness)),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: scale == 2,
                  ),
                  child: child!,
                ),
                home: ProfileWorkspaceScreen(controller: controller),
              ),
            ),
          );
          final question = {
            'questions': [
              {'qid': 'q0', 'question': 'Already answered on desktop?'},
            ],
          };
          host.event('a', 'clarify', {'request_id': 'request', ...question});
          await tester.pump();
          await tester.pump();
          final reply = Completer<void>();
          host.onClarifyResponse = () => reply.future;
          host.clarifyResult = {'status': 'expired'};
          final resume = Completer<void>();
          host.resumeDelay = resume;
          addTearDown(() {
            if (!resume.isCompleted) resume.complete();
          });
          await tester.ensureVisible(find.byKey(const Key('clarify-skip')));
          await tester.tap(find.byKey(const Key('clarify-skip')));
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          await captureFormFamily(
            tester,
            'clarify-${brightness.name}-$scale-held',
          );
          host.event('a', 'session.info', {
            'open_requests': [
              {
                'id': 'request',
                'method': 'clarify',
                'params': {'session_id': chat.runtime.runtimeId, ...question},
              },
            ],
          });
          await tester.pump();
          reply.complete();
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(chat.runtime.pendingQuestion, isNull);
          expect(find.byKey(const Key('clarify-skip')), findsNothing);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is StudioLoading && widget.label == 'Reconnecting',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await captureFormFamily(
            tester,
            'clarify-${brightness.name}-$scale-closed',
          );
          resume.complete();
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(chat.runtime.pendingQuestion, isNull);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'incoming question shows choices inline and confirms explicitly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final host = Host();
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
          connection: identityTestConnection(),
          dashboardOAuth: null,
        ),
        connectionIdentity: 'test-identity',
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: host.gateway,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.createChat(canDispatch: () => true);
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
