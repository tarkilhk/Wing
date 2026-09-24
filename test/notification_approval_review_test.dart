import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_approval.dart';
import 'package:wing/core/widgets/notification_approval_review.dart';

const capture = bool.fromEnvironment('CAPTURE_REVIEW');
void main() {
  setUpAll(() async {
    if (!capture) return;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '/tmp/approval-fonts/${font.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets('failed decision keeps review open and retries only explicitly', (
    tester,
  ) async {
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => NotificationApprovalReview(
                request: GatewayApprovalRequest.fromEventData({
                  'command': 'print(1)',
                  'choices': ['once', 'deny'],
                }),
                choice: 'once',
                changes: changes,
                offline: () => false,
                pending: () => true,
                submit: () async {
                  attempts++;
                  if (attempts == 1) throw StateError('offline');
                },
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();
    expect(find.text('Review command'), findsOneWidget);
    expect(
      find.text('Decision not confirmed. Check the connection, then retry.'),
      findsOneWidget,
    );
    changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Review command'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('scope and controls visible $brightness $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final changes = ChangeNotifier();
        addTearDown(changes.dispose);
        final frame = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: wingTheme(brightness),
            builder: (context, child) => RepaintBoundary(
              key: frame,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => NotificationApprovalReview(
                    request: GatewayApprovalRequest.fromEventData({
                      'command': List.filled(
                        30,
                        'print("long test command")',
                      ).join('\n'),
                      'description': 'Backend says this is one-shot.',
                      'choices': ['always', 'deny'],
                    }),
                    choice: 'always',
                    changes: changes,
                    offline: () => false,
                    pending: () => true,
                    submit: () async {},
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Permanently allow matching commands, including in future chats.',
          ),
          findsOneWidget,
        );
        expect(find.text('Backend says this is one-shot.'), findsNothing);
        expect(
          tester
              .getRect(
                find.text(
                  'Permanently allow matching commands, including in future chats.',
                ),
              )
              .bottom,
          lessThan(915),
        );
        expect(tester.getRect(find.text('Always allow')).bottom, lessThan(915));
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final boundary =
                frame.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/wing-notification-fixes/review-${brightness.name}-$scale.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
