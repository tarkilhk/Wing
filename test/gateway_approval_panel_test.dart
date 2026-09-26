import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/gateway_approval_panel.dart';

import 'profile_workspace_controller_test.dart' show Host;

const _capture = bool.fromEnvironment('CAPTURE_APPROVALS');

void main() {
  setUpAll(() async {
    if (!_capture) return;
    const directory = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'monospace': 'RobotoMono-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '$directory/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('approval command scrolls independently: $brightness/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final host = Host();
        late ProfileWorkspaceController controller;
        await tester.runAsync(() async {
          controller = ProfileWorkspaceController(
            connectionIdentity: 'fixture',
            connection: SavedConnection(
              id: 'host',
              label: 'Home',
              host: 'localhost',
              port: 1,
              apiKey: '',
            ),
            preferences: await SharedPreferences.getInstance(),
            gatewayFactory: host.gateway,
          );
          await controller.initialize();
          final chat = await controller.createChat();
          chat.title = 'Review source verification';
          final records = List.generate(
            80,
            (i) => "records.append({'source': $i, 'verified': True})",
          ).join('\n');
          for (final id in ['one', 'two']) {
            host.event('a', 'approval', {
              'request_id': id,
              'command':
                  "execute_code <<'PY'\n# Write the source-verification artifact\nimport json, os\n$records\nPY",
              'choices': ['once', 'session', 'always', 'deny'],
            });
          }
        });
        addTearDown(controller.dispose);
        final frame = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: frame,
              child: ProfileWorkspaceScreen(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final command = find.byKey(const Key('approval-command-scroll'));
        expect(tester.getSize(command).height, lessThanOrEqualTo(160));
        expect(find.text('Approval needed (1/2)'), findsOneWidget);
        await tester.ensureVisible(command);
        await tester.pumpAndSettle();
        final controlsBefore = tester.getRect(find.text('Allow once'));
        await tester.drag(command, const Offset(0, -100));
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<SingleChildScrollView>(command)
            .controller!;
        expect(scroll.offset, greaterThan(0));
        expect(tester.getRect(find.text('Allow once')), controlsBefore);
        for (final label in [
          'Allow once',
          'Allow for session',
          'Always allow',
          'Deny',
        ]) {
          await tester.ensureVisible(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (w) => w is ButtonStyleButton,
                  ),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (_capture) {
          await tester.runAsync(() async {
            final render =
                frame.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/approval-review/${brightness.name}-$scale.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        // Responding disables every scope, including denial.
        host.approvalDelay = Completer<void>();
        final response = controller.approve(
          controller.current!.chat!,
          'once',
          requestId: 'one',
        );
        await tester.runAsync(
          () => controller.updateDraft(
            controller.current!.chat!,
            'Draft while reviewing',
          ),
        );
        await tester.pump();
        final panel = find.byType(GatewayApprovalPanel);
        for (final button in tester.widgetList<ButtonStyleButton>(
          find.descendant(
            of: panel,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )) {
          expect(button.onPressed, isNull);
        }
        host.approvalDelay!.complete();
        await tester.runAsync(() => response);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
