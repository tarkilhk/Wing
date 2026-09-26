import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_message.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_workspace_controller_test.dart' show Host;

void main() {
  testWidgets('streaming leaves unchanged saved Markdown unbuilt', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final host = Host();
    final controller = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'streaming-work-budget',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final chat = await controller.createChat();
    chat.messages = [
      for (var i = 1; i <= 20; i++)
        {
          'id': i,
          'role': i.isEven ? 'assistant' : 'user',
          'content': 'Saved message $i with **formatted** content.',
        },
    ];
    host.event('a', 'message.start');
    host.event('a', 'message.delta', {'text': 'Live answer'});
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byWidgetPredicate((w) => w is ProfileMessage && !w.streaming),
      findsWidgets,
    );
    var savedBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget case MarkdownBody(
        data: final text,
      ) when text.startsWith('Saved message')) {
        savedBuilds++;
      }
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    for (var i = 0; i < 30; i++) {
      host.event('a', 'message.delta', {'text': '.'});
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrint('Streaming 30 deltas: $savedBuilds saved Markdown builds');
    expect(chat.streaming, 'Live answer${'.' * 30}');
    expect(
      savedBuilds,
      0,
      reason: 'New answer text must not re-render unchanged saved Markdown.',
    );
  });
}
