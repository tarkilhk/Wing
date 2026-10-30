import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reveal a mounted control after its route is current and has finished opening.
/// A keyboard can leave a loaded control below the viewport indefinitely; a
/// passive hit-test wait cannot recover it. Lazy list discovery stays with the
/// caller, which knows the owning scrollable and the direction to search.
Future<void> revealJourneyControl(
  WidgetTester tester,
  Finder control, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  do {
    await tester.pump(const Duration(milliseconds: 50));
    var reachable = false;
    final elements = control.evaluate().toList();
    if (elements.length == 1) {
      final route = ModalRoute.of(elements.single);
      if (route == null ||
          (route.isCurrent &&
              (route.animation == null ||
                  route.animation!.status == AnimationStatus.completed))) {
        await Scrollable.ensureVisible(elements.single, alignment: .5);
        await tester.pump();
        reachable = control.hitTestable().evaluate().length == 1;
      }
    }
    final exception = tester.takeException();
    if (exception != null) throw exception;
    if (reachable) return;
  } while (tester.binding.clock.now().isBefore(deadline));
  throw TestFailure(
    'Control did not become reachable within $timeout: $control; '
    'matches=${control.evaluate().length}, '
    'viewport=${tester.view.physicalSize / tester.view.devicePixelRatio}, '
    'keyboardInset=${tester.view.viewInsets.bottom / tester.view.devicePixelRatio}',
  );
}

/// Dispatch exactly once, only after the target can receive the pointer.
Future<void> tapJourneyControl(WidgetTester tester, Finder control) async {
  await revealJourneyControl(tester, control);
  await tester.tap(control);
}
