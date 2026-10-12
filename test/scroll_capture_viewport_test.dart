import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/scroll_capture_bridge.dart';
import 'package:wing/core/widgets/scroll_capture_viewport.dart';

Future<Object?> _native(String method, Map<String, Object> args) async {
  final response = Completer<Object?>();
  const channel = ScrollCaptureBridge.channel;
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, args)),
        (bytes) => response.complete(
          bytes == null ? null : channel.codec.decodeEnvelope(bytes),
        ),
      );
  return response.future;
}

void main() {
  for (final reversed in [false, true]) {
    testWidgets(
      'capture scrolls only the viewport, clamps and restores reading reversed=$reversed',
      (tester) async {
        final registrations = <Map<Object?, Object?>>[];
        final methods = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(ScrollCaptureBridge.channel, (
          call,
        ) async {
          methods.add(call.method);
          if (call.method == 'register') {
            registrations.add(
              Map<Object?, Object?>.from(call.arguments as Map),
            );
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            ScrollCaptureBridge.channel,
            null,
          ),
        );
        final controller = ScrollController(initialScrollOffset: 200);
        addTearDown(controller.dispose);
        final states = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Group')),
              body: Column(
                children: [
                  Expanded(
                    child: ScrollCaptureViewport(
                      controller: controller,
                      onCaptureChanged: states.add,
                      child: ListView(
                        controller: controller,
                        reverse: reversed,
                        children: [
                          for (var i = 0; i < 50; i++)
                            SizedBox(height: 80, child: Text('Message $i')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 100, child: Text('Composer')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final id = registrations.last['id'] as int;
        final metrics = await _native('metrics', {'id': id}) as Map;
        expect(
          metrics['offset'],
          reversed
              ? (controller.position.maxScrollExtent - 200) *
                    tester.view.devicePixelRatio
              : 200 * tester.view.devicePixelRatio,
        );
        expect(metrics['top'], greaterThan(0));
        expect(metrics['bottom'], lessThan(tester.view.physicalSize.height));
        expect(await _native('metrics', {'id': id + 1}), isNull);
        await _native('start', {'id': id});
        expect(states, [true]);
        final capture = _native('scroll', {'id': id, 'offset': 800});
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect((await capture as Map)['offset'], closeTo(800, .001));
        expect(
          controller.offset,
          reversed
              ? controller.position.maxScrollExtent -
                    800 / tester.view.devicePixelRatio
              : 800 / tester.view.devicePixelRatio,
        );
        final clamped = _native('scroll', {'id': id, 'offset': -100});
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect((await clamped as Map)['offset'], 0);
        await _native('end', {'id': id});
        expect(controller.offset, 200);
        expect(states, [true, false]);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(methods.last, 'unregister');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
