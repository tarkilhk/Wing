import 'package:flutter/material.dart';

import '../models/gateway_approval.dart';

/// One review surface; a failed send leaves the decision explicit and retryable.
class NotificationApprovalReview extends StatefulWidget {
  const NotificationApprovalReview({
    super.key,
    required this.request,
    required this.choice,
    required this.changes,
    required this.offline,
    required this.pending,
    required this.submit,
  });
  final GatewayApprovalRequest request;
  final String choice;
  final Listenable changes;
  final bool Function() offline;
  final bool Function() pending;
  final Future<void> Function() submit;

  @override
  State<NotificationApprovalReview> createState() => _ReviewState();
}

class _ReviewState extends State<NotificationApprovalReview> {
  bool sending = false;
  String? error;

  Future<void> send() async {
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.submit();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          sending = false;
          error = 'Decision not confirmed. Check the connection, then retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.changes,
    builder: (context, _) {
      final offline = widget.offline();
      final pending = widget.pending();
      final status = !pending
          ? 'This approval is no longer pending.'
          : sending
          ? 'Sending decision…'
          : error ??
                (offline
                    ? 'Offline—approval not sent. Reconnect to retry.'
                    : null);
      final scope = switch (widget.choice) {
        'always' =>
          'Permanently allow matching commands, including in future chats.',
        'session' => 'Allow matching commands for this session.',
        'deny' => 'Reject this request. The command will not run.',
        _ => 'Allow this request once.',
      };
      return PopScope(
        canPop: !sending,
        child: AlertDialog(
          titleTextStyle: Theme.of(context).textTheme.titleLarge,
          title: Text(
            widget.choice == 'always' ? 'Always allow?' : 'Review command',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scope, style: Theme.of(context).textTheme.titleSmall),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(widget.request.command),
                        if (widget.request.description.isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Hermes request details'),
                            children: [Text(widget.request.description)],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              child: Text(pending ? 'Cancel' : 'Close'),
            ),
            FilledButton(
              onPressed: sending || offline || !pending ? null : send,
              child: Text(
                sending
                    ? 'Sending…'
                    : switch (widget.choice) {
                        'always' => 'Always allow',
                        'session' => 'Allow for session',
                        'deny' => 'Deny',
                        _ => 'Allow once',
                      },
              ),
            ),
          ],
        ),
      );
    },
  );
}
