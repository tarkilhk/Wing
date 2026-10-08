import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/profiles_management_session.dart';
import 'admin_widgets.dart';

class AdminProfilesPage extends StatefulWidget {
  const AdminProfilesPage({super.key, required this.createSession});
  final ProfilesManagementSession Function() createSession;
  @override
  State<AdminProfilesPage> createState() => _AdminProfilesPageState();
}

class _AdminProfilesPageState extends State<AdminProfilesPage> {
  late final ProfilesManagementSession _session;
  int? _announced;

  @override
  void initState() {
    super.initState();
    _session = widget.createSession();
    _session.addListener(_changed);
    unawaited(_session.reload());
  }

  void _changed() {
    if (!mounted) return;
    final outcome = _session.state.outcome;
    if (outcome != null &&
        outcome.announcesSuccess &&
        outcome.sequence != _announced) {
      _announced = outcome.sequence;
      adminMessage(context, outcome.message);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  Future<void> _edit(ProfilesManagementIntent? intent) async {
    if (intent == null) return;
    var draft = _session.state.draft;
    if (draft == null) return;
    if (draft.needsName) {
      final continued = await showDialog<bool>(
        context: context,
        builder: (_) => _ProfileNameDialog(session: _session, intent: intent),
      );
      if (!mounted) return;
      if (continued != true) {
        _session.cancel(intent);
        return;
      }
    }
    draft = _session.state.draft;
    if (draft == null) return;
    if (draft.needsConfirmation) {
      final confirmed = await adminConfirm(
        context,
        draft.confirmationTitle,
        draft.confirmationDetail,
        action: draft.confirmationAction,
      );
      if (!mounted) return;
      if (!confirmed) {
        _session.cancel(intent);
        return;
      }
    }
    await _session.submit(intent);
  }

  Future<void> _open(String name) async {
    final opened = await _session.open(name);
    if (mounted && opened) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = _session.state;
    final pending = _session.pendingIntent;
    return AdminPage(
      title: 'Profiles',
      scope: state.scope,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.loading || state.busy) const LinearProgressIndicator(),
          if (state.error != null) AdminNotice.error(state.error!),
          for (final settlement in state.settlements) ...[
            AdminNotice(settlement.message),
            SelectableText(settlement.manualGuidance!),
            const SizedBox(height: 12),
          ],
          if (!state.busy &&
              state.error != null &&
              pending != null &&
              state.draft != null)
            Wrap(
              spacing: 8,
              children: [
                if (state.draft!.canSubmit)
                  TextButton(
                    onPressed: () => unawaited(_session.submit(pending)),
                    child: const Text('Try again'),
                  ),
                if (state.draft!.canCancel)
                  TextButton(
                    onPressed: () => _session.cancel(pending),
                    child: const Text('Cancel change'),
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: state.canCreate
                  ? () => unawaited(_edit(_session.beginCreate()))
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Create profile'),
            ),
          ),
          const SizedBox(height: 16),
          AdminGroup(
            children: [
              for (final row in state.rows)
                ListTile(
                  title: Text(row.title),
                  subtitle: Text(row.subtitle),
                  onTap: state.canOpen
                      ? () => unawaited(_open(row.name))
                      : null,
                  trailing: PopupMenuButton<String>(
                    enabled: row.canClone || row.canRename || row.canDelete,
                    tooltip: 'Manage ${row.title}',
                    itemBuilder: (_) => [
                      if (row.canClone)
                        const PopupMenuItem(
                          value: 'clone',
                          child: Text('Clone configuration'),
                        ),
                      if (row.canRename)
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                      if (row.canDelete)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                    ],
                    onSelected: (action) => unawaited(
                      _edit(switch (action) {
                        'clone' => _session.beginClone(row.name),
                        'rename' => _session.beginRename(row.name),
                        'delete' => _session.beginDelete(row.name),
                        _ => null,
                      }),
                    ),
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: state.canRefresh
                ? () => unawaited(_session.reload())
                : null,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog({required this.session, required this.intent});
  final ProfilesManagementSession session;
  final ProfilesManagementIntent intent;
  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final draft = widget.session.state.draft;
      if (draft == null) return const SizedBox.shrink();
      return AlertDialog(
        scrollable: true,
        title: Text(draft.title),
        content: TextFormField(
          initialValue: draft.initialName,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Name',
            helperMaxLines: 4,
            helperText: draft.help,
            errorText: draft.validationError,
          ),
          onChanged: (value) => widget.session.updateName(widget.intent, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: draft.canContinue
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('Continue'),
          ),
        ],
      );
    },
  );
}
