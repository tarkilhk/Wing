import 'package:flutter/material.dart';
import '../services/native_notification_sink.dart';

/// Android channel blocks are independent of the application's permission.
class NotificationChannelDiagnostics extends StatefulWidget {
  const NotificationChannelDiagnostics({super.key});
  @override
  State<NotificationChannelDiagnostics> createState() =>
      _NotificationChannelDiagnosticsState();
}

class _NotificationChannelDiagnosticsState
    extends State<NotificationChannelDiagnostics>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _blocked = const [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await NativeNotificationSink.channel
          .invokeListMethod<dynamic>('channels');
      if (!mounted) return;
      setState(() {
        _blocked = (rows ?? const [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .where((v) => v['blocked'] == true)
            .toList();
      });
    } catch (_) {
      /* Unavailable outside Android. */
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final channel in _blocked)
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text('${channel['name']} blocked'),
          subtitle: const Text(
            'Enable this category in Android notification settings.',
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () async {
            try {
              await NativeNotificationSink.channel.invokeMethod<void>(
                'openChannelSettings',
                channel['id'],
              );
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open Android notification settings.',
                    ),
                  ),
                );
              }
            }
          },
        ),
    ],
  );
}
