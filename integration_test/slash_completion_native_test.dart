import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/slash_command_suggestions.dart';

import '../test/slash_commands_test.dart' show CommandHost;

/// Production Android composer with a strict stock completion-contract fixture.
/// No live server or model requests. Run only on a disposable emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const captureKey = ValueKey('slash-capture');

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('/app selection ${brightness.name} $scale', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final host = CommandHost()
          ..warning =
              'slash command /handoff unavailable — name taken by built-in; use /skill handoff; '
              'slash command /plan unavailable — name taken by built-in; use /skill plan';
        final controller = ProfileWorkspaceController(
          connectionIdentity: 'native-slash-completion',
          connection: SavedConnection(
            id: 'native-slash-completion',
            label: 'Completion QA',
            host: 'unused',
            port: 1,
            apiKey: '',
          ),
          preferences: await SharedPreferences.getInstance(),
          gatewayFactory: host.gateway,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        final chat = await controller.createChat();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: ProfileWorkspaceScreen(controller: controller),
            ),
          ),
        );
        Future<void> frames() async {
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        Future<void> reveal(Finder item) async {
          await frames();
          final list = find.descendant(
            of: find.byType(SlashCommandSuggestions),
            matching: find.byType(ListView),
          );
          for (
            var i = 0;
            i < 15 && item.hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(list, const Offset(0, -80));
            await frames();
          }
          expect(item.hitTestable(), findsOneWidget);
        }

        await frames();
        final composer = find.byKey(const Key('profile-message-composer'));
        await tester.tap(composer);
        await tester.enterText(composer, '/app');
        await frames();
        final approval = find.descendant(
          of: find.byType(SlashCommandSuggestions),
          matching: find.text('/approvals'),
        );
        await reveal(approval);
        await tester.tap(approval.hitTestable());
        await frames();
        expect(chat.draft, '/approvals ');

        final failed = find
            .text('Could not load commands. Tap to retry.')
            .evaluate()
            .isNotEmpty;
        final name =
            'slash-${failed ? 'error' : 'fixed'}-${brightness.name}-$scale';
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final frame = await boundary.toImage();
        final bytes = (await frame.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        frame.dispose();
        final directory = await getExternalStorageDirectory();
        await File('${directory!.path}/$name.png').writeAsBytes(bytes);
        expect(
          find.text('Could not load commands. Tap to retry.'),
          findsNothing,
        );
        expect(
          host.commandCalls
              .singleWhere((call) => call.$1 == 'complete.slash')
              .$2,
          {'session_id': chat.runtimeId, 'text': '/approvals '},
        );
        expect(
          host.commandCalls.where((call) => call.$1 == 'prompt.submit'),
          isEmpty,
        );
        await reveal(find.text('smart'));
        await tester.tap(find.text('smart').hitTestable());
        await frames();
        expect(chat.draft, '/approvals smart ');
        expect(
          host.commandCalls.where((call) => call.$1 == 'command.dispatch'),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
