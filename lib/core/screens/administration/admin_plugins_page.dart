import 'package:flutter/material.dart';
import '../../models/profile_plugins.dart';
import '../../services/profile_plugins_session.dart';
import '../../widgets/compact_switch.dart';
import '../../widgets/read_recovery.dart';
import 'admin_widgets.dart';

class AdminPluginsPage extends StatefulWidget {
  const AdminPluginsPage({super.key, required this.createSession});
  final ProfilePluginsSession Function() createSession;
  @override
  State<AdminPluginsPage> createState() => _AdminPluginsPageState();
}

class _AdminPluginsPageState extends State<AdminPluginsPage> {
  late final _session = widget.createSession();
  @override
  void initState() {
    super.initState();
    _session.refresh();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _choose(ProfilePlugin row, bool enabled) async {
    await _session.toggle(row, enabled);
    if (!mounted) {
      return;
    }
    final state = _session.state;
    if (state.error != null) {
      adminMessage(context, state.error!, isError: true);
    } else if (state.acknowledgement?.restartRequired == true) {
      adminMessage(
        context,
        'Plugin change saved. Restart Hermes to apply it to running handlers.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Agent plugins',
    scope: _session.scopeLabel,
    child: ReadRecovery(
      shouldRetry: () => _session.canRecover,
      retry: _session.refresh,
      child: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          final state = _session.state;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.busy) const LinearProgressIndicator(),
              if (state.error != null)
                AdminNotice.error(
                  state.error!,
                  retry: state.canRefresh ? _session.refresh : null,
                ),
              const AdminNotice(
                'Backend capabilities for this profile. Desktop plugin screens are not Android screens.',
              ),
              if (state.verified && state.rows.isEmpty)
                const AdminNotice('No agent plugins reported.'),
              AdminGroup(
                children: [
                  for (final row in state.rows)
                    CompactSwitchListTile(
                      title: Text(row.name),
                      subtitle: Text(
                        '${row.source} · ${row.status.label}\n${row.description}',
                      ),
                      value: row.enabled,
                      onChanged: state.canToggle
                          ? (value) => _choose(row, value)
                          : null,
                    ),
                ],
              ),
              TextButton(
                onPressed: state.canRefresh ? _session.refresh : null,
                child: const Text('Refresh'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
