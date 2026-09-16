import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/android_launch_intent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidLaunchIntentService.channelName);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final action in AndroidLaunchAction.values) {
    test('consumes cold-start ${action.name} once', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getInitialLaunchAction');
            calls++;
            return action.name;
          });
      final service = AndroidLaunchIntentService();
      addTearDown(service.dispose);
      await service.initialize();
      await service.initialize();
      expect(calls, 1);
      expect(service.pendingAction.value, action);
      expect(service.takePendingAction(), action);
      expect(service.takePendingAction(), isNull);
    });

    test('receives repeated warm ${action.name} launches', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      final service = AndroidLaunchIntentService();
      addTearDown(service.dispose);
      await service.initialize();
      for (var i = 0; i < 2; i++) {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(
                MethodCall('launchAction', action.name),
              ),
              (_) {},
            );
        expect(service.takePendingAction(), action);
        expect(service.takePendingAction(), isNull);
      }
    });
  }

  test('ignores unknown Android actions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'unknown');
    final service = AndroidLaunchIntentService();
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.pendingAction.value, isNull);
  });
}
