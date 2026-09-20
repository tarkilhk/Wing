import 'dart:async';
import 'package:flutter/services.dart';
import 'turn_notification_service.dart';

/// Android owns rendering, immutable action intents, unlock and dismissal.
/// The existing plugin continues to own the runtime permission dialog.
class NativeNotificationSink extends PluginTurnNotificationSink {
  static const channel = MethodChannel('com.tarkilhk.wing/chat_notifications');
  final Future<void> Function(Map<String, dynamic>) onInteraction;
  NativeNotificationSink({required this.onInteraction});
  Future<void>? _nativeInitialization;

  @override
  Future<void> initialize() async {
    final pending = _nativeInitialization;
    if (pending != null) return pending;
    final attempt = _initializeNative();
    _nativeInitialization = attempt;
    try {
      await attempt;
    } catch (_) {
      _nativeInitialization = null;
      rethrow;
    }
  }

  Future<void> _dispatch(Map<String, dynamic> data) async {
    await onInteraction(data);
    if (data['interaction_id'] is String) {
      await channel.invokeMethod<void>('acknowledge', data['interaction_id']);
    }
  }

  Future<void> _initializeNative() async {
    await super.initialize();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'interaction') {
        await _dispatch(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    final pending = await channel.invokeListMethod<dynamic>('initialize');
    for (final item in pending ?? const []) {
      unawaited(_dispatch(Map<String, dynamic>.from(item as Map)));
    }
  }

  @override
  Future<void> show(TurnNotification notification) async {
    await initialize();
    await channel.invokeMethod<void>('show', notification.toJson());
  }

  @override
  Future<void> cancel(int id) => channel.invokeMethod<void>('cancel', id);
  @override
  Future<void> cancelAll() => channel.invokeMethod<void>('cancelAll');

  Future<List<Map<String, dynamic>>> channelStatus() async =>
      (await channel.invokeListMethod<dynamic>('channels') ?? const [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<void> openChannelSettings(String id) =>
      channel.invokeMethod<void>('openChannelSettings', id);
}
