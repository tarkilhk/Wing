import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_connectors_page.dart';
import 'package:wing/core/screens/administration/admin_mcp_setup_page.dart';
import 'package:wing/core/services/mcp_oauth.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/administration_fixture.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_MCP');
  setUpAll(() async {
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((b) => b.buffer.asByteData()),
          ))
          .load();
    }
  });
  for (final brightness in Brightness.values) {
    for (final enlarged in [false, true]) {
      for (final page in ['setup', 'callback']) {
        final name =
            '$page-${brightness.name}-${enlarged ? 'large' : 'normal'}';
        testWidgets('MCP setup and callback controls remain reachable: $name', (
          tester,
        ) async {
          tester.view.physicalSize = Size(enlarged ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = AdministrationFixture('Claw');
          fixture.configs['personal']!['mcp_servers'] = {
            'aspire': {
              'url': 'https://aspire-mcp.aspireapp.com/mcp',
              'auth': 'oauth',
            },
          };
          fixture.rpcOverride = (method, params) async => {
            'ok': true,
            'status': 'pending',
            'session_id': 'flow',
            'flow': 'pkce',
            if (method.endsWith('.start'))
              'auth_url': Uri.https('example.test', '/authorize', {
                'state': 'fixture-state',
                'redirect_uri': params['client_redirect_uri'] as String,
              }).toString(),
          };
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(enlarged ? 2 : 1)),
                  child: child!,
                ),
                home: page == 'setup'
                    ? AdminMcpSetupPage(
                        profile: fixture.server.profile('personal'),
                      )
                    : AdminMcpSignIn(
                        profile: fixture.server.profile('personal'),
                        name: 'aspire',
                        openBrowser: (_) async => true,
                        bindLoopback: (target, _) async => McpLoopback(
                          redirectUri: target,
                          close: () async {},
                        ),
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (page == 'setup') {
            await tester.scrollUntilVisible(
              find.text('Use Aspire settings'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text('Use Aspire settings'));
          } else {
            await tester.scrollUntilVisible(
              find.text('Start sign-in'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text('Start sign-in'));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (capture) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('build/mcp-review/$name.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.scrollUntilVisible(
            find.text(page == 'setup' ? 'Add and sign in' : 'Complete sign-in'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
