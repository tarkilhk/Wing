import 'package:flutter/material.dart';

import '../services/diagnostic_export.dart';
import '../theme/wing_theme.dart';
import 'studio_error.dart';

/// Shared by connected and offline App settings; collection needs no server.
class DiagnosticLogsTile extends StatefulWidget {
  const DiagnosticLogsTile({super.key});

  @override
  State<DiagnosticLogsTile> createState() => _DiagnosticLogsTileState();
}

class _DiagnosticLogsTileState extends State<DiagnosticLogsTile> {
  final _session = DiagnosticExportSession();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Diagnostic logs'),
          subtitle: const Text(
            'Recent app events and device details as a ZIP. Chats and credentials excluded.',
          ),
          trailing: StudioButtonPress(
            child: IconButton(
              tooltip: 'Share diagnostic logs',
              onPressed: _session.busy ? null : _session.share,
              icon: _session.busy
                  ? SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: MediaQuery.disableAnimationsOf(context)
                            ? 0.7
                            : null,
                        semanticsLabel: 'Preparing and sharing diagnostic logs',
                      ),
                    )
                  : const Icon(Icons.share_outlined),
            ),
          ),
        ),
        if (_session.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: StudioError(_session.error!),
          ),
      ],
    ),
  );
}
