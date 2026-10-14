import 'dart:io';
import 'dart:ui' as ui;

import 'package:wing/core/models/transcript_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/wing_icons.dart';
import 'package:wing/core/widgets/answer_actions.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/widgets/profile_live_execution.dart';
import 'package:wing/core/widgets/profile_live_work_dock.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/pump_markdown_widget.dart';
import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  const capture = bool.fromEnvironment('CAPTURE_SAVED_NOTICE');
  setUpAll(() async {
    if (!capture) return;
    for (final font in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(
            font.key,
          )..addFont(File(font.value).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  });
  const task =
      'Subagent Task Completed: Implement a bounded Renovate research validator '
      'fix, tests and matching operator documentation. Do not push, commit, '
      'deploy, rerun cron or call external services. Report exact files/diff '
      'and test results.';
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('notice actions stay aligned ${brightness.name} at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ProfileMessage(
                    message: TranscriptMessage.fromRow(const {
                      'role': 'user',
                      'display_kind': 'async_delegation_complete',
                      'display_metadata': {
                        'task_count': 1,
                        'display_text': task,
                      },
                      'content':
                          'Background result with enough detail to span several lines when expanded.',
                    }),
                    actions: AnswerActions(
                      onBranch: () {},
                      onReadAloud: () {},
                      onRegenerate: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final arrow = find.byIcon(Icons.expand_more);
        final branch = find.byIcon(WingIcons.fork);
        final retry = find.byIcon(Icons.refresh);
        await tester.ensureVisible(find.text('View result'));
        await tester.pumpAndSettle();
        final headerCenter = tester.getCenter(arrow).dy;
        final noticeText = tester.getRect(find.text(task));
        expect(
          noticeText.width,
          greaterThanOrEqualTo(tester.view.physicalSize.width - 64),
          reason:
              'Saved completion text must not be squeezed by answer actions.',
        );
        expect(
          tester.getRect(branch).top,
          greaterThanOrEqualTo(noticeText.bottom),
        );
        void expectAligned() {
          final center = tester.getCenter(arrow).dy;
          expect(tester.getCenter(branch).dy, closeTo(center, .01));
          expect(tester.getCenter(retry).dy, closeTo(center, .01));
          // ExpansionTile removes its one-pixel collapsed border on opening.
          // The controls must stay in the header, not follow the result body.
          expect(center, closeTo(headerCenter, 1));
          expect(tester.takeException(), isNull);
        }

        expectAligned();
        for (final tooltip in [
          'Branch in new session',
          'Read aloud',
          'Regenerate response',
        ]) {
          final size = tester.getSize(find.byTooltip(tooltip));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.text('View result'));
        await tester.pumpAndSettle();
        await tester.settleMarkdown();
        expectAligned();
        expect(
          find.text(
            'Background result with enough detail to span several lines when expanded.',
          ),
          findsOneWidget,
        );
      });
      testWidgets('completed notice route ${brightness.name} at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final app = AppPreferences(prefs);
        final rows = <Map<String, dynamic>>[
          {'id': 1, 'role': 'user', 'content': 'Fix the validator.'},
          {
            'id': 2,
            'role': 'assistant',
            'content': 'The validator change is underway.',
          },
          {
            'id': 3,
            'role': 'user',
            'display_kind': 'async_delegation_complete',
            'display_metadata': {'display_text': task, 'task_count': 1},
            'content': 'Implemented the validator with matching tests.',
          },
          {
            'id': 4,
            'role': 'assistant',
            'content': 'Updated and deployed the validator.',
          },
        ];
        final host = Host()..historyMessages = rows;
        final controller = ProfileWorkspaceController(
          connectionIdentity: 'completed-notice',
          access: ConnectionAccess(
            connection: identityTestConnection(),
            dashboardOAuth: null,
          ),
          preferences: prefs,
          appPreferences: app,
          gatewayFactory: host.gateway,
        );
        addTearDown(() {
          controller.dispose();
          app.dispose();
        });
        await controller.initialize();
        final chat = await controller.createChat(canDispatch: () => true);
        await controller.refreshHistory(chat);
        final frame = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: RepaintBoundary(key: frame, child: child!),
            ),
            home: ProfileWorkspaceScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        await tester.settleMarkdown();
        expect(chat.runtime.executionActive, isFalse);
        expect(chat.reading.streamingMessage, isNull);
        expect(find.byType(ProfileLiveExecution), findsNothing);
        expect(find.byType(ProfileLiveWorkDock), findsNothing);
        expect(chat.reading.messages, rows);
        expect(find.byKey(const ValueKey('answer-actions-2')), findsOneWidget);
        expect(
          tester.getSize(find.text(task)).width,
          greaterThanOrEqualTo(tester.view.physicalSize.width - 64),
        );
        await tester.ensureVisible(find.text('View result'));
        await tester.pumpAndSettle();
        Future<void> picture(String state) async {
          if (!capture) return;
          await tester.runAsync(() async {
            final bitmap =
                await (frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            try {
              final bytes = await bitmap.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('build/design-previews/saved-notice')
                ..createSync(recursive: true);
              await File(
                '${dir.path}/${brightness.name}-$scale-$state.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              bitmap.dispose();
            }
          });
        }

        await picture('folded');
        await tester.tap(find.text('View result'));
        await tester.pumpAndSettle();
        await tester.settleMarkdown();
        expect(
          find.text(
            'Implemented the validator with matching tests.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.text(
            'Implemented the validator with matching tests.',
            findRichText: true,
          ),
        );
        await tester.pumpAndSettle();
        await picture('expanded');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
