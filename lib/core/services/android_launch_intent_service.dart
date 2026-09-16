import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AndroidLaunchAction { quickChat, activity, searchChats }

/// Bridges Android launcher actions into the Flutter navigation lifecycle.
class AndroidLaunchIntentService {
  static const channelName = 'com.tarkilhk.wing/launch';

  final MethodChannel _channel;
  final pendingAction = ValueNotifier<AndroidLaunchAction?>(null);
  bool _initialized = false;

  AndroidLaunchIntentService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      _publish(await _channel.invokeMethod<String>('getInitialLaunchAction'));
    } on MissingPluginException {
      // Non-Android builds do not provide launcher shortcuts.
    } on PlatformException {
      // A launcher failure must never prevent the app from opening normally.
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'launchAction') return;
    _publish(call.arguments as String?);
  }

  void _publish(String? action) {
    final parsed = AndroidLaunchAction.values
        .where((value) => value.name == action)
        .firstOrNull;
    if (parsed != null) pendingAction.value = parsed;
  }

  AndroidLaunchAction? takePendingAction() {
    final pending = pendingAction.value;
    pendingAction.value = null;
    return pending;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    pendingAction.dispose();
  }
}
