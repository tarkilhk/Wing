import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/connection_icon.dart';
import 'package:wing/core/services/server_connection_status.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/server_connection_label.dart';

void main() {
  testWidgets('connection details retain live status and retry behavior', (
    tester,
  ) async {
    final status = ServerConnectionStatus('Claw');
    addTearDown(status.dispose);
    status.liveChanged('chat', false);
    var retries = 0;
    status.retry = () async {
      retries++;
      status.beginRecovery('chat');
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: ServerConnectionLabel(label: 'Claw', status: status),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('connection-status-target')),
      ),
      matchesSemantics(
        label: 'Claw, Disconnected. Connection details',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
    await tester.tap(find.byKey(const ValueKey('connection-status-target')));
    await tester.pumpAndSettle();
    expect(find.text('Disconnected'), findsOneWidget);
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(find.text('Reconnecting'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    status.accessAvailable();
    status.liveChanged('chat', true);
    status.endRecovery('chat');
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Available'), findsNWidgets(2));
    expect(find.text('Retry connection'), findsNothing);
    await tester.tap(find.byTooltip('Close connection details'));
    await tester.pumpAndSettle();
    expect(find.text('Connection details'), findsNothing);
  });

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
            builder: (context, child) => MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: ServerConnectionLabel(
                  label: status.label,
                  icon: ConnectionIcon.rocket,
                  status: status,
                  suffix: 'Travel',
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
        final icon = tester.getRect(find.byIcon(Icons.rocket_launch_outlined));
        expect(led.size, const Size(8, 8));
        expect(led.left - icon.right, 8);
        expect(name.left - led.right, 16);
        expect(
          tester.getSize(find.byType(InkWell).first).height,
          greaterThanOrEqualTo(48),
        );
        final fade = tester.widget<FadeTransition>(
          find.byType(FadeTransition).last,
        );
        expect(fade.opacity.value, 1);
        await tester.tap(
          find.byKey(const ValueKey('connection-status-target')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Server access'), findsOneWidget);
        expect(find.text('Live chat'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        status.dispose();
      },
    );
  }
}
