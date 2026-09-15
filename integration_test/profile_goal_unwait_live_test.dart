import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wing/core/models/session_control.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_goal_panel.dart';

({String processId, int pid})? _backgroundProcess(Object? value) {
  if (value is String) {
    try {
      return _backgroundProcess(jsonDecode(value));
    } on FormatException {
      return null;
    }
  }
  if (value is List) {
    for (final item in value) {
      final result = _backgroundProcess(item);
      if (result != null) return result;
    }
    return null;
  }
  if (value is Map) {
    final output = value['output'];
    final processId = value['session_id'];
    final pid = value['pid'];
    if (output == 'Background process started' &&
        processId is String &&
        processId.startsWith('proc_') &&
        pid is int &&
        pid > 0) {
      return (processId: processId, pid: pid);
    }
    for (final item in value.values) {
      final result = _backgroundProcess(item);
      if (result != null) return result;
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const port = int.fromEnvironment('HERMES_TEST_PORT');

  testWidgets(
    'real goal wait barrier resumes from the goal panel',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final connection = SavedConnection(
        id: 'goal-unwait-live-qa',
        label: 'Goal Unwait live QA',
        host: '127.0.0.1',
        port: port,
        dashboardPortOverride: port,
        apiKey: '',
      );
      final controller = ProfileWorkspaceController(
        connectionIdentity: 'goal-unwait-live-qa',
        connection: connection,
        preferences: preferences,
      );
      await controller.initialize();
      await controller.switchProfile('android-qa-a');
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );

      Future<void> until(
        bool Function() condition, {
        Duration timeout = const Duration(seconds: 90),
      }) async {
        final deadline = DateTime.now().add(timeout);
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(condition(), isTrue);
      }

      expect(controller.error, isNull);
      expect(controller.current!.scope.profileName, 'android-qa-a');
      final chat = await controller.createChat();
      ({String processId, int pid})? ownedProcess;
      ({String processId, int pid})? liveProcess;
      Object? cleanupFailure;
      void observeOwnedProcess() {
        for (final activity in chat.toolActivities) {
          final process = _backgroundProcess(activity.result);
          if (process != null) {
            liveProcess = process;
            ownedProcess = process;
          }
        }
      }

      controller.addListener(observeOwnedProcess);

      try {
        chat.draft =
            'Use the terminal tool with background=true to run this exact '
            'PowerShell command: Start-Sleep -Seconds 180. Report the returned '
            'session_id and numeric pid exactly. Do not use other tools or do '
            'other work.';
        await controller.send(chat);
        expect(chat.error, isNull);
        await until(() => !chat.busy, timeout: const Duration(minutes: 3));
        expect(chat.error, isNull);
        await controller.refreshHistory(chat);
        final persistedProcess = _backgroundProcess(chat.messages);
        ownedProcess ??= persistedProcess;
        expect(
          liveProcess,
          isNotNull,
          reason: 'The live terminal result must identify the owned process',
        );
        expect(
          persistedProcess,
          isNotNull,
          reason:
              'Authoritative terminal tool result must contain pid/session_id',
        );
        final startedProcess = persistedProcess!;
        final observedProcess = liveProcess!;
        expect(startedProcess.processId, observedProcess.processId);
        expect(startedProcess.pid, observedProcess.pid);

        final gateway = controller.current!.gateway;
        await gateway.call('command.dispatch', {
          'session_id': chat.runtimeId,
          'name': 'goal',
          'arg': 'Await Android goal Unwait QA verification',
        });
        await gateway.call('command.dispatch', {
          'session_id': chat.runtimeId,
          'name': 'goal',
          'arg': 'wait ${startedProcess.pid} Android owned QA process',
        });
        await controller.refreshSessionControl(chat);
        expect(chat.sessionControlError, isNull);
        expect(
          chat.sessionControl?.goal?.waitBarrier?.processId,
          startedProcess.pid,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfileGoalPanel(
                controller: controller,
                chat: chat,
                initiallyExpanded: true,
              ),
            ),
          ),
        );
        await until(
          () => find
              .widgetWithText(TextButton, 'Resume now')
              .evaluate()
              .any(
                (element) => (element.widget as TextButton).onPressed != null,
              ),
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                (widget.textSpan?.toPlainText() ?? widget.data ?? '').contains(
                  'Waiting:',
                ),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Resume now'));
        await tester.tap(find.text('Resume now'));
        await until(
          () =>
              !chat.sessionControlWorking &&
              chat.sessionControl?.goal?.waitBarrier == null,
        );
        await controller.refreshSessionControl(chat);
        expect(chat.sessionControlError, isNull);
        expect(chat.sessionControl?.goal?.waitBarrier, isNull);
      } finally {
        controller.removeListener(observeOwnedProcess);
        if (chat.busy) {
          try {
            await controller.stop(chat);
          } catch (error) {
            cleanupFailure ??= error;
          }
        }
        try {
          final cleared = await controller.controlSession(
            chat,
            SessionControlAction.goalClear,
          );
          if (!cleared) {
            throw StateError(chat.sessionControlError ?? 'Goal clear failed');
          }
          await controller.refreshSessionControl(chat);
          if (chat.sessionControl?.goal != null) {
            throw StateError('Goal remained after cleanup');
          }
        } catch (error) {
          cleanupFailure ??= error;
        }
        final cleanupProcess = ownedProcess;
        if (cleanupProcess != null) {
          try {
            await controller.refreshProcesses(chat);
            final process = chat.processes
                .where((item) => item.id == cleanupProcess.processId)
                .firstOrNull;
            if (process?.isRunning == true) {
              final stopped = await controller.stopProcess(
                chat,
                cleanupProcess.processId,
              );
              if (!stopped) {
                throw StateError(
                  chat.processesError ?? 'Owned process stop failed',
                );
              }
              await controller.refreshProcesses(chat);
              if (chat.processes.any(
                (item) => item.id == cleanupProcess.processId && item.isRunning,
              )) {
                throw StateError(
                  'Owned process remained running after cleanup',
                );
              }
            }
          } catch (error) {
            cleanupFailure ??= error;
          }
        }
        controller.dispose();
        if (cleanupFailure != null) {
          fail('Live QA cleanup failed: $cleanupFailure');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: port == 0,
  );
}
