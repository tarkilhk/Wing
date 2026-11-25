import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/scheduled_task.dart';
import 'package:wing/core/screens/administration/admin_scheduled_task_editor_page.dart';
import 'package:wing/core/screens/administration/admin_scheduled_tasks_page.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/scheduled_tasks_controller.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_form_actions.dart';
import 'package:wing/core/widgets/studio_select.dart';

import '../test/support/scheduled_tasks_fixture.dart';
import 'support/journey_capture.dart';

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue);
}

Future<void> _revealWrapping(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byType(StudioSelect<TaskOutputWrapping>),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _chooseWrapping(
  WidgetTester tester,
  TaskOutputWrapping value, {
  String? capture,
}) async {
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
  if (capture != null) await captureJourney(tester, capture);
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

Future<void> _editCreatedTask(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Actions for Android acceptance'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit task').hitTestable());
  await tester.pumpAndSettle();
  expect(find.byType(AdminScheduledTaskEditorPage), findsOneWidget);
}

/// Disposable Android, production controls and isolated transport. No provider
/// or live scheduler is contacted. The narrow render constrains the app to
/// 320 dp while retaining the real Android View and its keyboard insets.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testJourney(
    'Android task creation, keyboard, anchored menu and back navigation',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final large in [false, true]) {
          SharedPreferences.setMockInitialValues({});
          final fixture = ScheduledTasksFixture(
            serverId: 'Task fixture ${brightness.name} $large',
          );
          addTearDown(fixture.admin.server.close);
          final taskPreferences = await SharedPreferences.getInstance();
          final variant =
              'tasks-${brightness.name}-${large ? 'large' : 'normal'}';
          await tester.pumpWidget(
            journeyCaptureBoundary(
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: large ? 320 : null,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: profileWorkspaceTheme(
                      wingTheme(brightness),
                      accent: WorkspaceAccent.teal,
                    ),
                    builder: (context, child) => LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: constraints.biggest,
                          textScaler: TextScaler.linear(large ? 2 : 1),
                          disableAnimations: true,
                        ),
                        child: child!,
                      ),
                    ),
                    home: AdminScheduledTasksPage(
                      profile: fixture.profile,
                      acquireController: () => ScheduledTasksController.acquire(
                        fixture.profile,
                        taskPreferences,
                      ),
                      onOpenSession: (_) async {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('New task'));
          await tester.pumpAndSettle();
          final name = find.widgetWithText(TextFormField, 'Name (optional)');
          await tester.tap(name);
          await tester.enterText(name, 'Android acceptance');
          await _wait(
            tester,
            () => View.of(tester.element(name)).viewInsets.bottom > 0,
          );
          await tester.pumpAndSettle();
          final instructions = find.widgetWithText(
            TextFormField,
            'Instructions',
          );
          await tester.scrollUntilVisible(
            instructions,
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(instructions);
          await tester.enterText(instructions, 'Prepare a daily summary.');
          await tester.pumpAndSettle();
          final view = View.of(tester.element(instructions));
          expect(view.viewInsets.bottom, greaterThan(0));
          final keyboardTop =
              (view.physicalSize.height - view.viewInsets.bottom) /
              view.devicePixelRatio;
          for (final label in ['Cancel', 'Create task']) {
            final action = find.byTooltip(label).hitTestable();
            expect(action, findsOneWidget);
            expect(
              tester.getRect(action).bottom,
              lessThanOrEqualTo(keyboardTop),
            );
            expect(tester.getSize(action), const Size(48, 48));
          }
          if (large) {
            expect(
              tester.getSize(find.byType(AdminScheduledTaskEditorPage)).width,
              320,
            );
          }
          await captureJourney(tester, '$variant-keyboard');
          expect(view.viewInsets.bottom, greaterThan(0));
          FocusManager.instance.primaryFocus?.unfocus();
          await _wait(tester, () => view.viewInsets.bottom == 0);
          await tester.pumpAndSettle();
          await _chooseWrapping(
            tester,
            TaskOutputWrapping.on,
            capture: '$variant-menu',
          );
          fixture.gate = Completer<void>();
          await tester.tap(find.byTooltip('Create task'));
          await tester.pump();
          expect(
            find
                .descendant(
                  of: find.byType(StudioFormActions),
                  matching: find.byType(CircularProgressIndicator),
                )
                .hitTestable(),
            findsOneWidget,
          );
          await _wait(tester, () => fixture.mutations == 1);
          await tester.pump(const Duration(milliseconds: 250));
          expect(
            tester
                .widget<StudioFormActions>(find.byType(StudioFormActions))
                .busy,
            isTrue,
          );
          await captureJourney(tester, '$variant-create-held');
          fixture.gate!.complete();
          await _wait(
            tester,
            () => find.byType(AdminScheduledTaskEditorPage).evaluate().isEmpty,
          );
          await tester.pumpAndSettle();
          final created = fixture.jobs.values.singleWhere(
            (j) => j['name'] == 'Android acceptance',
          );
          expect(created['wrap_response'], isTrue);
          fixture.gate = null;
          await tester.ensureVisible(find.text('Android acceptance'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Actions for Android acceptance'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Pause schedule'));
          await tester.pumpAndSettle();
          expect(created['enabled'], isFalse);
          final createdTitle = find.text('Android acceptance');
          await Scrollable.ensureVisible(
            tester.element(createdTitle),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          expect(createdTitle.hitTestable(), findsOneWidget);
          await tester.tap(createdTitle.hitTestable());
          await tester.pumpAndSettle();
          expect(
            find.byTooltip('Resume and run').hitTestable(),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.text('Output wrapping'),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await captureJourney(tester, '$variant-detail-on');
          await _editCreatedTask(tester);
          await _revealWrapping(tester);
          expect(
            tester
                .widget<StudioSelect<TaskOutputWrapping>>(
                  find.byType(StudioSelect<TaskOutputWrapping>),
                )
                .value,
            TaskOutputWrapping.on,
          );
          await _chooseWrapping(tester, TaskOutputWrapping.off);
          fixture.gate = Completer<void>();
          fixture.mutationError = const AdministrationFailure(
            'Task save was refused. Try again.',
          );
          final beforeSave = fixture.mutations;
          await tester.tap(find.byTooltip('Save changes'));
          await tester.pump();
          expect(
            find
                .descendant(
                  of: find.byType(StudioFormActions),
                  matching: find.byType(CircularProgressIndicator),
                )
                .hitTestable(),
            findsOneWidget,
          );
          await _wait(tester, () => fixture.mutations == beforeSave + 1);
          await tester.pump(const Duration(milliseconds: 250));
          await captureJourney(tester, '$variant-save-held');
          fixture.gate!.complete();
          await _wait(
            tester,
            () => !tester
                .widget<StudioFormActions>(find.byType(StudioFormActions))
                .busy,
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Task save was refused. Try again.').hitTestable(),
            findsOneWidget,
          );
          expect(created['wrap_response'], isTrue);
          await captureJourney(tester, '$variant-save-failed');
          fixture.gate = null;
          fixture.mutationError = null;
          await _revealWrapping(tester);
          expect(
            tester
                .widget<StudioSelect<TaskOutputWrapping>>(
                  find.byType(StudioSelect<TaskOutputWrapping>),
                )
                .value,
            TaskOutputWrapping.off,
          );
          await tester.tap(find.byTooltip('Save changes'));
          await tester.pumpAndSettle();
          expect(created['wrap_response'], isFalse);
          await _editCreatedTask(tester);
          await _revealWrapping(tester);
          expect(
            tester
                .widget<StudioSelect<TaskOutputWrapping>>(
                  find.byType(StudioSelect<TaskOutputWrapping>),
                )
                .value,
            TaskOutputWrapping.off,
          );
          await _chooseWrapping(tester, TaskOutputWrapping.inherit);
          await tester.tap(find.byTooltip('Save changes'));
          await tester.pumpAndSettle();
          expect(
            fixture.admin.requests
                .where((r) => r.$1 == 'PUT')
                .last
                .$4!['updates'],
            {'wrap_response': null},
          );
          expect(created.containsKey('wrap_response'), isTrue);
          expect(created['wrap_response'], isNull);
          await _editCreatedTask(tester);
          await _revealWrapping(tester);
          expect(
            tester
                .widget<StudioSelect<TaskOutputWrapping>>(
                  find.byType(StudioSelect<TaskOutputWrapping>),
                )
                .value,
            TaskOutputWrapping.inherit,
          );
          await captureJourney(tester, '$variant-reset-reopened');
          await tester.tap(find.byTooltip('Cancel'));
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Scheduled tasks'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
