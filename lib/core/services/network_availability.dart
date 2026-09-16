import 'package:flutter/services.dart';

/// A device-network event is a reason to retry, never proof of server access.
class NetworkAvailability {
  static const _channel = MethodChannel('com.tarkilhk.wing/network');
  void start(void Function() onAvailable, void Function() onUnavailable) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'available') onAvailable();
      if (call.method == 'unavailable') onUnavailable();
    });
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
