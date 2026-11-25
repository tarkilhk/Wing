import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/scheduled_task.dart';
import 'package:wing/core/screens/administration/admin_scheduled_task_detail_page.dart';
import 'package:wing/core/screens/administration/admin_scheduled_task_editor_page.dart';
import 'package:wing/core/screens/administration/admin_scheduled_tasks_page.dart';
import 'package:wing/core/services/scheduled_tasks_controller.dart';
import 'package:wing/core/services/scheduled_tasks_repository.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_select.dart';

import '../test/helpers/journey_controls.dart';
import 'hermes_next_conversation_prod_test.dart'
    show productionWorkspace, waitForProductionState;
import 'support/journey_capture.dart';

const _nonce = String.fromEnvironment('WING_QA_NONCE');
const _name = 'Wing QA $_nonce wrapping';
const _prompt =
    'Reply only with WRAPPING_QA. Do not use tools, files, network or delegation.';

Future<void> _visible(WidgetTester tester, Finder control) async {
  if (control.evaluate().isEmpty) {
    // The first scrollable belongs to the current page, as in the scheduled
    // task native journey. A text field can own the last vertical scrollable.
    // Drag the page gutter through the shared helper so the focused native
    // input cannot consume lazy-list discovery gestures.
    await dragViewportToControl(tester, find.byType(Scrollable).first, control);
  }
  await revealJourneyControl(tester, control);
}

Future<void> _tap(WidgetTester tester, Finder control) async {
  await _visible(tester, control);
  await tapJourneyControl(tester, control);
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await _tap(tester, field);
  await waitForProductionState(
    tester,
    () => tester.view.viewInsets.bottom > 0,
    '$label native keyboard opens',
    seconds: 15,
  );
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
  expect(tester.widget<TextFormField>(field).controller!.text, value);
}

Future<void> _closeKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await waitForProductionState(
    tester,
    () => tester.view.viewInsets.bottom == 0,
    'Native keyboard dismissal completes before select-only controls',
    seconds: 15,
  );
  await tester.pumpAndSettle();
}

Future<void> _chooseDelay(WidgetTester tester) async {
  await _closeKeyboard(tester);
  final control = find.byType(StudioSelect<TaskScheduleKind>);
  await tester.scrollUntilVisible(
    control,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(of: control, matching: find.byIcon(Icons.arrow_drop_down))
        .hitTestable(),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .widgetWithText(MenuItemButton, TaskScheduleKind.delay.label)
        .hitTestable(),
  );
  await tester.pumpAndSettle();
  expect(
    tester.widget<StudioSelect<TaskScheduleKind>>(control).value,
    TaskScheduleKind.delay,
  );
}

Future<void> _revealWrapping(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(StudioSelect<TaskOutputWrapping>),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

// Keep the proven scheduled_tasks_native_test selector interaction: reveal,
// settle layout, tap its trailing arrow once, then choose the actual menu item.
Future<void> _chooseWrapping(
  WidgetTester tester,
  TaskOutputWrapping value,
) async {
  await _closeKeyboard(tester);
  await _revealWrapping(tester);
  await tester.tap(
    find
        .descendant(
          of: find.byType(StudioSelect<TaskOutputWrapping>),
          matching: find.byIcon(Icons.arrow_drop_down),
        )
        .hitTestable(),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(MenuItemButton, value.label).hitTestable(),
  );
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<StudioSelect<TaskOutputWrapping>>(
          find.byType(StudioSelect<TaskOutputWrapping>),
        )
        .value,
    value,
  );
}

Future<void> _expectEditor(
  WidgetTester tester,
  TaskOutputWrapping value,
) async {
  await waitForProductionState(
    tester,
    () => find.byType(AdminScheduledTaskEditorPage).evaluate().isNotEmpty,
    'Owned task editor opens',
  );
  final control = find.byType(StudioSelect<TaskOutputWrapping>);
  await _visible(tester, control);
  expect(tester.widget<StudioSelect<TaskOutputWrapping>>(control).value, value);
}

Future<void> _edit(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Actions for $_name'));
  await _tap(tester, find.text('Edit task'));
  await waitForProductionState(
    tester,
    () => find.byType(AdminScheduledTaskEditorPage).evaluate().isNotEmpty,
    'Owned task editor finishes loading',
  );
}

Future<void> _save(WidgetTester tester, String tooltip) async {
  await _tap(tester, find.byTooltip(tooltip));
  await waitForProductionState(
    tester,
    () => find.byType(AdminScheduledTaskEditorPage).evaluate().isEmpty,
    'Task save finishes and returns to its owner',
  );
}

/// Production Android controls and stock service readback in the runner's
/// exact fresh profile. No task execution, provider call or group is required
/// to verify this stored override; delivery formatting remains a separate path.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets(
    'Production task output wrapping persists inherit on off and reset',
    (tester) async {
      final workspace = await productionWorkspace(
        'wing-prod-$_nonce-task-wrapping',
        profile: _nonce,
      );
      final tasks = ScheduledTasksRepository(
        workspace.administration().profile(_nonce),
      );
      final manifest = File(
        '${Directory.systemTemp.path}/wing-prod-owned-$_nonce-task-wrapping.json',
      );
      expect(await manifest.exists(), isFalse);
      expect(
        await tasks.list(),
        isEmpty,
        reason: 'Requires fresh owned profile',
      );
      final taskIds = <String, String>{};
      final readbacks = <Map<String, dynamic>>[];
      final receipt = <String, dynamic>{
        'nonce': _nonce,
        'origin': const String.fromEnvironment('WING_HERMES_URL'),
        'kind': 'task-wrapping',
        'profile': _nonce,
        'task_names': [_name],
        'task_ids': taskIds,
        'readbacks': readbacks,
        'creation': 'not requested',
        'creation_dispatch': false,
        'outcome': 'incomplete',
        'cleanup': 'not started',
        'provider_execution': false,
      };
      Future<void> checkpoint() async {
        final pending = File('${manifest.path}.pending');
        await pending.writeAsString(jsonEncode(receipt), flush: true);
        await pending.rename(manifest.path);
      }

      Future<ScheduledTask> readback(TaskOutputWrapping value) async {
        final members = await tasks.list();
        final member = members.singleWhere((task) => task.name == _name);
        expect(member.profileName, _nonce);
        if (taskIds.isNotEmpty) expect(member.id, taskIds.keys.single);
        taskIds[member.id] = _name;
        await checkpoint();
        final saved = await tasks.get(member.id);
        expect(saved.profileName, _nonce);
        expect(saved.name, _name);
        expect(saved.data['wrap_response'], value.wireValue);
        expect(saved.outputWrapping, value);
        expect(member.outputWrapping, value);
        expect(member.running, isFalse);
        expect(await tasks.runs(member.id), isEmpty);
        readbacks.add({
          'task_id': member.id,
          'wrap_response': saved.data['wrap_response'],
          'choice': value.name,
          'execution_count': 0,
        });
        await checkpoint();
        return saved;
      }

      Object? failure, cleanupFailure;
      StackTrace? failureStack, cleanupStack;
      await checkpoint();
      try {
        final preferences = await SharedPreferences.getInstance();
        late ScheduledTasksController controller;
        await tester.pumpWidget(
          journeyCaptureBoundary(
            MaterialApp(
              theme: wingTheme(Brightness.dark),
              home: AdminScheduledTasksPage(
                profile: tasks.profile,
                acquireController: () =>
                    controller = ScheduledTasksController.acquire(
                      tasks.profile,
                      preferences,
                    ),
                onOpenSession: (_) async {},
              ),
            ),
          ),
        );
        await waitForProductionState(
          tester,
          () => controller.tasks != null && !controller.loading,
          'Fresh profile task list loads',
        );
        expect(controller.error, isNull);
        await _tap(tester, find.text('New task'));
        await waitForProductionState(
          tester,
          () => find.byType(AdminScheduledTaskEditorPage).evaluate().isNotEmpty,
          'New task editor finishes loading',
        );
        await _enter(tester, 'Name (optional)', _name);
        await _enter(tester, 'Instructions', _prompt);
        // A one-week delay prevents any scheduled execution during verification.
        await _chooseDelay(tester);
        await _enter(tester, 'Run once after (minutes)', '10080');
        final delayController = tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Run once after (minutes)'),
            )
            .controller!;
        await _closeKeyboard(tester);
        expect(delayController.text, '10080');
        final delaySummary = find.text(
          'Runs once, 10080 minutes after creation',
        );
        await _visible(tester, delaySummary);
        expect(delaySummary.hitTestable(), findsOneWidget);
        await captureJourney(tester, 'prod-task-wrapping-delay-confirmed');
        await _chooseWrapping(tester, TaskOutputWrapping.inherit);
        await _expectEditor(tester, TaskOutputWrapping.inherit);
        await captureJourney(tester, 'prod-task-wrapping-create-inherit');
        expect(delayController.text, '10080');
        receipt['creation'] = 'requested through New task';
        receipt['creation_dispatch'] = true;
        await checkpoint();
        await _save(tester, 'Create task');
        await readback(TaskOutputWrapping.inherit);
        receipt['creation'] = 'confirmed';
        await checkpoint();

        for (final value in [
          TaskOutputWrapping.on,
          TaskOutputWrapping.off,
          TaskOutputWrapping.inherit,
        ]) {
          await _edit(tester);
          await _chooseWrapping(tester, value);
          await _expectEditor(tester, value);
          await _save(tester, 'Save changes');
          await readback(value);
          await _edit(tester);
          await _expectEditor(tester, value);
          await captureJourney(
            tester,
            'prod-task-wrapping-${value.name}-reopened',
          );
          await _tap(tester, find.byTooltip('Cancel'));
          await waitForProductionState(
            tester,
            () => find.byType(AdminScheduledTaskEditorPage).evaluate().isEmpty,
            'Reopened editor closes',
          );
          await _tap(tester, find.text(_name));
          await waitForProductionState(
            tester,
            () =>
                find.byType(AdminScheduledTaskDetailPage).evaluate().isNotEmpty,
            'Owned task details open',
          );
          await _visible(tester, find.text('Output wrapping'));
          final wrappingFact = find.byWidgetPredicate(
            (widget) =>
                widget is Column &&
                widget.children.any(
                  (child) => child is Text && child.data == 'Output wrapping',
                ),
          );
          final displayedValue = find.descendant(
            of: wrappingFact,
            matching: find.text(value.label),
          );
          await _visible(tester, displayedValue);
          expect(displayedValue.hitTestable(), findsOneWidget);
          await captureJourney(
            tester,
            'prod-task-wrapping-${value.name}-detail',
          );
          await tester.pageBack();
          await waitForProductionState(
            tester,
            () => find.byType(AdminScheduledTaskDetailPage).evaluate().isEmpty,
            'Task list is restored',
          );
        }
        expect(readbacks.map((entry) => entry['choice']), [
          'inherit',
          'on',
          'off',
          'inherit',
        ]);
        receipt['outcome'] = 'passed';
        await checkpoint();
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
        receipt['outcome'] = 'failed';
        try {
          await checkpoint();
          await captureJourney(
            tester,
            'prod-task-wrapping-failure',
            failure: true,
          );
        } catch (_) {
          // Retain the original production failure if diagnostics also fail.
        }
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
        try {
          receipt['cleanup'] = 'checking exact owned task';
          await checkpoint();
          // Recover a lost create reply only by the recorded unique name in the
          // exact profile proven empty before the single UI create dispatch.
          final remaining = (await tasks.list())
              .where((task) => task.name == _name)
              .toList();
          expect(remaining.length, lessThanOrEqualTo(1));
          for (var task in remaining) {
            expect(task.profileName, _nonce);
            if (taskIds.isNotEmpty) expect(task.id, taskIds.keys.single);
            taskIds[task.id] = _name;
            await checkpoint();
            if (task.running) await tasks.cancel(task.id);
            final deadline = DateTime.now().add(const Duration(seconds: 120));
            while (task.running && DateTime.now().isBefore(deadline)) {
              await tester.pump(const Duration(seconds: 1));
              task = (await tasks.list()).singleWhere(
                (row) => row.id == task.id,
              );
            }
            expect(task.running, isFalse);
            await tasks.delete(task.id);
          }
          final after = await tasks.list();
          expect(after.any((task) => task.name == _name), isFalse);
          expect(after.any((task) => taskIds.containsKey(task.id)), isFalse);
          receipt['cleanup_readback'] = {
            'profile': _nonce,
            'profile_task_count': after.length,
            'owned_task_count': after
                .where(
                  (task) => task.name == _name || taskIds.containsKey(task.id),
                )
                .length,
            'recorded_task_ids_absent': true,
          };
          receipt['no_create_confirmed_empty'] =
              receipt['creation_dispatch'] == false &&
              taskIds.isEmpty &&
              after.isEmpty;
          receipt['empty_profile_tasks_confirmed'] = after.isEmpty;
          receipt['cleanup'] = 'confirmed absent';
          await checkpoint();
        } catch (error, stack) {
          cleanupFailure = error;
          cleanupStack = stack;
          receipt['cleanup'] = 'failed; ownership retained';
          try {
            await checkpoint();
          } catch (_) {
            debugPrint('WING_PROD_MANIFEST_WRITE_FAILED task-wrapping');
          }
        }
      }
      if (failure != null) {
        if (cleanupFailure != null) {
          debugPrint(
            'WING_PROD_CLEANUP_FAILED task-wrapping; inspect manifest',
          );
        }
        Error.throwWithStackTrace(failure, failureStack!);
      }
      if (cleanupFailure != null) {
        Error.throwWithStackTrace(cleanupFailure, cleanupStack!);
      }
    },
  );
}
