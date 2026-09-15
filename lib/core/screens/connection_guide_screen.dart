import 'package:flutter/material.dart';

import '../services/web_preview.dart';
import '../widgets/studio_error.dart';

/// Available offline before the first host is configured.
class ConnectionGuideScreen extends StatelessWidget {
  const ConnectionGuideScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connection guide')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final step in const [
          (
            '1  Prepare your agent',
            'Use a Hermes host you operate or have permission to use. '
                'Check that your agent can answer a message on that host.',
          ),
          (
            '2  Make the dashboard reachable',
            'Start an authenticated Hermes dashboard. Open its address from '
                'your phone’s browser and check your dashboard credentials. '
                'For a private-network dashboard, the address usually looks '
                'like http://hermes.home:9119. An HTTPS proxy might use '
                'https://hermes.example.com. Include any custom port or path. '
                'Use your computer’s network address: localhost on your phone '
                'means the phone itself. '
                'Use HTTPS or an encrypted private network for remote access.',
          ),
          (
            '3  Connect in Wing',
            'Return to the welcome screen and choose Connect your agent. '
                'Enter the complete dashboard address, then your dashboard '
                'login. Wing checks profiles, live chat and history. Name '
                'the verified connection and choose Save and open. '
                'Custom setup is only for extra settings supplied by your '
                'administrator. Keep model-provider keys on your Hermes host.',
          ),
          (
            'Already have a backup?',
            'Choose Restore configuration on the welcome screen to import '
                'a Wing configuration backup with its passphrase.',
          ),
        ]) ...[
          Text(step.$1, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(step.$2),
          const SizedBox(height: 24),
        ],
        OutlinedButton(
          onPressed: () async {
            final opened = await openWebPreview(
              Uri.parse(
                'https://github.com/tarkilhk/wing/blob/main/docs/GETTING_STARTED.md',
              ),
            );
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: StudioError('Could not open the guide'),
                ),
              );
            }
          },
          child: const Text('Full setup instructions'),
        ),
      ],
    ),
  );
}
