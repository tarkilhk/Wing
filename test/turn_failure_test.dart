import 'dart:async';
import 'support/form_family_capture.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/chat_notification_content.dart';
import 'package:wing/core/models/turn_failure.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/services/chat_runtime.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/turn_failure_view.dart';

Map<String, dynamic> limitedTurn() => {
  'status': 'error',
  'error': 'Provider diagnostic with a private endpoint',
  'error_surface': {
    'layer': 'billing',
    'code': 'usage_limit',
    'retryable': false,
    'provider': 'nous',
    'model': 'large',
    'usage_limit': {
      'limit_name': 'Daily',
      'message': 'Daily allowance exhausted',
      'scope': 'all',
      'resets_at_ms': 1793203200000,
      'suggestions': [
        {
          'provider': 'nous',
          'model': 'free',
          'label': 'Free model',
          'note': 'free',
        },
      ],
      'credits': {'action': 'use_credits'},
    },
  },
};

void main() {
  setUpAll(loadFormFamilyFonts);
  test(
    'idle resume retains received failure facts until a new outcome or runtime',
    () {
      for (final successor in [
        'running',
        'replacement',
        'success',
        'newerIdle',
        'newFailure',
        'unknownFailure',
      ]) {
        final runtime = ChatRuntime(runtimeId: 'same');
        final failure = TurnFailure.fromCompletion({
          'status': 'error',
          'text': 'Received refusal',
          'error_surface': {'code': 'content_policy_blocked'},
        })!;
        runtime.completeTurn(
          failed: true,
          cancelled: false,
          error: failure.message,
          failure: failure,
          executionGeneration: 4,
        );
        runtime.installResume({
          'session_id': 'same',
          'running': false,
          'inflight': null,
          'execution_generation': 4,
        });
        runtime.installResume({'session_id': 'same', 'running': false});
        expect(runtime.observation.execution, ChatExecution.failed);
        expect(runtime.observation.failure, same(failure));
        expect(runtime.observation.error, 'Received refusal');
        switch (successor) {
          case 'running':
            runtime.installResume({'session_id': 'same', 'running': true});
          case 'replacement':
            runtime.installResume({
              'session_id': 'replacement',
              'running': false,
            });
          case 'success':
            runtime.beginTurn(submitting: false);
            runtime.completeTurn(failed: false, cancelled: false, error: null);
            runtime.installResume({'session_id': 'same', 'running': false});
          case 'newerIdle':
            runtime.installResume({
              'session_id': 'same',
              'running': false,
              'execution_generation': 5,
            });
            expect(runtime.observation.execution, ChatExecution.idle);
          case 'newFailure':
            runtime.installResume({
              'session_id': 'same',
              'running': false,
              'execution_generation': 5,
              'inflight': {'status': 'error', 'text': 'New provider error'},
            });
            expect(runtime.observation.execution, ChatExecution.failed);
            expect(runtime.observation.failure, isNot(same(failure)));
            expect(runtime.observation.error, 'New provider error');
            runtime.dispose();
            continue;
          case 'unknownFailure':
            runtime.beginTurn(submitting: false);
            runtime.completeTurn(
              failed: true,
              cancelled: false,
              error: failure.message,
              failure: failure,
            );
            runtime.installResume({
              'session_id': 'same',
              'running': false,
              'execution_generation': 5,
            });
            expect(runtime.observation.execution, ChatExecution.failed);
            expect(runtime.observation.failure, same(failure));
            runtime.dispose();
            continue;
        }
        expect(runtime.observation.execution, isNot(ChatExecution.failed));
        expect(runtime.observation.failure, isNull);
        expect(runtime.observation.error, isNull);
        runtime.dispose();
      }
    },
  );
  test('content refusal stays a failure without provider recovery actions', () {
    for (final byReason in [false, true]) {
      final failure = TurnFailure.fromCompletion({
        'status': 'error',
        'text': 'Provider refusal detail',
        if (byReason) 'failure_reason': 'content_policy_blocked',
        'error_surface': {
          'layer': 'provider',
          if (!byReason) 'code': 'content_policy_blocked',
          'retryable': false,
        },
      })!;
      expect(failure.contentRefused, isTrue);
      expect(failure.title, 'Message refused');
      expect(failure.canChooseModel, isFalse);
      expect(failure.canReviewProvider, isFalse);
      expect(failure.canContinue, isFalse);
      final notification = ChatNotificationContent.failure(failure);
      expect(notification.category, ChatNotificationCategory.stopped);
      expect(notification.needsAttention, isTrue);
      expect(notification.status, 'Message refused');
    }
  });
  test('local endpoint recovery never offers provider sign-in', () {
    final failure = TurnFailure.fromCompletion({
      'status': 'error',
      'error_surface': {
        'code': 'local_runtime_unavailable',
        'layer': 'endpoint',
      },
    })!;
    expect(failure.canReviewProvider, isFalse);
    expect(failure.canChooseModel, isTrue);
    expect(failure.recovery, contains('Start the local model server'));
    expect(failure.blocking, isTrue);
  });
  test('cut-off replies expose explicit Continue as degraded recovery', () {
    final failure = TurnFailure.fromCompletion({
      'status': 'error',
      'error_surface': {'code': 'truncated', 'layer': 'streaming'},
    })!;
    expect(failure.canContinue, isTrue);
    expect(failure.blocking, isFalse);
  });
  test(
    'launch credential refusal requires a new chat and keeps supplied explanation',
    () {
      final failure = TurnFailure.fromCompletion({
        'status': 'error',
        'error_surface': {
          'code': 'launch_credentials_unavailable',
          'layer': 'auth',
          'message': 'The original launch key is no longer available.',
          'provider': 'nous',
          'provider_label': 'Nous Portal',
        },
      })!;
      expect(failure.recovery, contains('start a new chat'));
      expect(
        failure.description,
        'The original launch key is no longer available.',
      );
      expect(failure.providerLabel, 'Nous Portal');
    },
  );
  test(
    'structured failure retains exact identity without leaking diagnostics to notifications',
    () {
      final failure = TurnFailure.fromCompletion(limitedTurn())!;
      expect(failure.retryable, isFalse);
      expect(failure.provider, 'nous');
      expect(failure.model, 'large');
      expect(
        failure.usageLimit!.resetsAt!.millisecondsSinceEpoch,
        1793203200000,
      );
      expect(failure.usageLimit!.suggestions.single.model, 'free');
      final notification = ChatNotificationContent.failure(failure);
      expect(notification.status, 'Plan allowance reached');
      expect(notification.preview, isNot(contains('private endpoint')));
      expect(
        TurnFailure.fromCompletion({
          'status': 'complete',
          'error_surface': limitedTurn()['error_surface'],
        }),
        isNull,
      );
    },
  );

  test(
    'unknown descriptors do not invent retry or recovery, bad epochs stay absent',
    () {
      final failure = TurnFailure.fromCompletion({
        'status': 'error',
        'error_surface': {
          'code': 'future_failure',
          'resets_at': double.infinity,
        },
      })!;
      expect(failure.retryable, isNull);
      expect(failure.resetsAt, isNull);
      expect(failure.recovery, isNull);
      expect(failure.canChooseModel, isFalse);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Continue failure holds feedback $brightness $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final held = Completer<void>();
        var calls = 0;
        final failure = TurnFailure.fromCompletion({
          'status': 'error',
          'error': 'Response ended early',
          'error_surface': {'code': 'truncated', 'layer': 'streaming'},
        })!;
        await tester.pumpWidget(
          RepaintBoundary(
            key: formFamilyCapture,
            child: MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: TurnFailureView(
                    failure: failure,
                    onContinue: () {
                      calls++;
                      return held.future;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await captureFormFamily(
          tester,
          'failure-continue-${brightness.name}-$scale',
        );
        await tester.ensureVisible(find.byTooltip('Continue'));
        await tester.pump();
        expect(find.byTooltip('Continue').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Continue'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await captureFormFamily(
          tester,
          'failure-continue-pending-${brightness.name}-$scale',
        );
        await tester.ensureVisible(find.byTooltip('Continue'));
        await tester.pump();
        expect(find.byTooltip('Continue').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Continue'));
        expect(calls, 1);
        held.completeError(StateError('Connection unavailable'));
        await tester.pump();
        await tester.pump();
        final feedback = find.textContaining('Connection unavailable');
        await tester.ensureVisible(feedback);
        await tester.pump();
        expect(feedback.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
      testWidgets(
        'limit recovery acknowledges held action and preserves failure $brightness $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final held = Completer<bool>();
          var calls = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: TurnFailureView(
                      failure: TurnFailure.fromCompletion(limitedTurn())!,
                      onSelectModel: (suggestion) {
                        calls++;
                        expect(suggestion.provider, 'nous');
                        return held.future;
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byTooltip('Use Free model'));
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('Daily allowance exhausted'), findsOneWidget);
          await tester.tap(find.byTooltip('Use Free model'));
          expect(calls, 1);
          held.completeError(StateError('Provider is unavailable'));
          await tester.pump();
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            find.textContaining('Provider is unavailable'),
            findsOneWidget,
          );
          expect(find.text('Daily allowance exhausted'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
