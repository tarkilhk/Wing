import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/server_connection_label.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'server label and details fit narrow enlarged ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final status = ServerConnectionStatus('Claw · a longer server name');
        status.beginRecovery('travel');
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ServerConnectionLabel(
                    label: status.label,
                    status: status,
                    suffix: 'Travel',
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final led = tester.getRect(
          find.byKey(const ValueKey('server-connection-led')),
        );
        final name = tester.getRect(find.text('${status.label} · Travel'));
        expect(led.size, const Size(8, 8));
        expect(name.left - led.right, 16);
        expect(
          tester.getSize(find.byType(InkWell)).height,
          greaterThanOrEqualTo(48),
        );
        final fade = tester.widget<FadeTransition>(
          find.byType(FadeTransition).last,
        );
        expect(fade.opacity.value, 1);
        await tester.tap(find.byType(ServerConnectionLabel));
        await tester.pumpAndSettle();
        expect(find.text('Server access: Not checked'), findsOneWidget);
        expect(find.text('Live chat: Not checked'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        status.dispose();
      },
    );
  }
}
