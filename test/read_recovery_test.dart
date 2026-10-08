import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/network_availability.dart';
import 'package:wing/core/widgets/read_recovery.dart';

Future<void> resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

Future<void> networkReturn(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'com.tarkilhk.wing/network',
    const StandardMethodCodec().encodeMethodCall(const MethodCall('available')),
    (_) {},
  );
  await tester.pump();
}

void main() {
  testWidgets('focus/network recover visible failures once, never on a timer', (
    tester,
  ) async {
    final network = NetworkAvailability()..start(() {}, () {});
    addTearDown(network.dispose);
    final navigator = GlobalKey<NavigatorState>();
    var calls = 0;
    var failed = true;
    Completer<void>? pending;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: ReadRecovery(
          shouldRetry: () => failed,
          retry: () async {
            calls++;
            await pending?.future;
          },
          child: const Scaffold(body: Text('Read')),
        ),
      ),
    );
    expect(calls, 0);
    await resume(tester);
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 1);
    pending = Completer<void>();
    await networkReturn(tester);
    await resume(tester);
    expect(calls, 2);
    pending.complete();
    await tester.pump();
    pending = null;
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await resume(tester);
    await networkReturn(tester);
    expect(calls, 2);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, 3);
    failed = false;
    await resume(tester);
    await networkReturn(tester);
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox());
    await resume(tester);
    await networkReturn(tester);
    expect(calls, 3);
  });
}
