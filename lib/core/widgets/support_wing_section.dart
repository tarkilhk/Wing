import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/wing_theme.dart';
import 'studio_action_label.dart';
import 'studio_error.dart';

/// Optional contributions, shown only in App settings / About.
class SupportWingSection extends StatefulWidget {
  const SupportWingSection({super.key, required this.uri});

  final Uri uri;

  @override
  State<SupportWingSection> createState() => _SupportWingSectionState();
}

class _SupportWingSectionState extends State<SupportWingSection> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    var opened = false;
    try {
      opened = await launchUrl(
        widget.uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // A missing browser or platform failure must leave settings usable.
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(WingSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Support Wing', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: WingSpacing.sm),
          const Text(
            'If Wing is useful in your day, you can buy me a coffee and help me keep improving it.',
          ),
          const SizedBox(height: WingSpacing.sm),
          Text(
            'Completely optional. Every feature is available either way.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: WingTokens.of(context).muted,
            ),
          ),
          const SizedBox(height: WingSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _opening ? null : _open,
              child: Semantics(
                hint: 'Opens Ko-fi in your browser',
                child: StudioActionLabel('Buy me a coffee', busy: _opening),
              ),
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: WingSpacing.md),
            const StudioError(
              'Could not open your browser. Please try again or open this link in a browser:',
            ),
            const SizedBox(height: WingSpacing.sm),
            SelectableText(widget.uri.toString()),
          ],
        ],
      ),
    );
  }
}
