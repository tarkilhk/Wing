import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_todo.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/profile_activity_tabs.dart';
import 'package:wing/core/widgets/profile_execution_activity.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';

const _capture = bool.fromEnvironment('CAPTURE_TASK_ICONS');
const _todos = [
  GatewayTodo(
    id: 'done',
    content: 'Audit original sources and create blind calibration cases',
    status: GatewayTodoStatus.completed,
  ),
  GatewayTodo(
    id: 'running',
    content: 'Independently grade real answers and controlled variants',
    status: GatewayTodoStatus.inProgress,
  ),
  GatewayTodo(
    id: 'pending',
    parent: 'running',
    content: 'Resolve the remaining source-scope decision',
    status: GatewayTodoStatus.pending,
  ),
  GatewayTodo(
    id: 'cancelled',
    content: 'Repeat the superseded comparison',
    status: GatewayTodoStatus.cancelled,
  ),
];

void main() {
  setUpAll(() async {
    if (!_capture) return;
    const dir = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '$dir/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('task states fit and remain accessible: $brightness/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ProfileActivitySection(
                      initiallyExpanded: true,
                      tabs: const [
                        ProfileActivityTab(
                          id: 'tasks',
                          label: 'Tasks 1/4',
                          child: ProfileTodoPanel(
                            todos: _todos,
                            embedded: true,
                          ),
                        ),
                      ],
                      children: const [],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [
          'Completed task',
          'Task in progress',
          'Pending task',
          'Cancelled task',
        ]) {
          expect(find.bySemanticsLabel(label), findsOneWidget);
        }
        expect(find.byIcon(Icons.flag_outlined), findsNothing);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.check_circle)).color,
          WingTokens.forBrightness(brightness).success,
        );
        expect(find.byIcon(Icons.block), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
        if (_capture) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/task-icons/${brightness.name}-$scale.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }

  testWidgets('completion replaces the live spinner and updates task count', (
    tester,
  ) async {
    var status = GatewayTodoStatus.inProgress;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ProfileTodoPanel(
                todos: [
                  GatewayTodo(id: 'one', content: 'Review', status: status),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tasks 0/1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      isNull,
    );
    update(() => status = GatewayTodoStatus.completed);
    await tester.pumpAndSettle();
    expect(find.text('Tasks 1/1'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
