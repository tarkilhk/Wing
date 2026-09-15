import 'package:flutter/material.dart';
import '../../models/hermes_profile.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';

class AdminProfilesPage extends StatefulWidget {
  final AdministrationRepository server;
  final Future<bool> Function(String name) onOpenProfile;
  const AdminProfilesPage({
    super.key,
    required this.server,
    required this.onOpenProfile,
  });
  @override
  State<AdminProfilesPage> createState() => _AdminProfilesPageState();
}

class _AdminProfilesPageState extends State<AdminProfilesPage> {
  bool _busy = false;
  String? _error;
  Future<String?> _name(
    String title, {
    String initial = '',
    bool displayOnly = false,
  }) => showDialog<String>(
    context: context,
    builder: (context) => _ProfileNameDialog(
      title: title,
      initial: initial,
      displayOnly: displayOnly,
    ),
  );

  Future<void> _create(VoidCallback refresh, [String? source]) async {
    final name = await _name(
      source == null ? 'Create profile' : 'Clone $source',
    );
    if (name == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.server.write('POST', 'profiles', {
        'name': name,
        'clone_from': ?source,
        'clone_all': false,
        'clone_channels': false,
      });
      final created = result['name'];
      if (created is! String ||
          (await widget.server.discover()).named(created) == null) {
        throw const AdministrationFailure(
          'Creation could not be confirmed. Refresh before trying again.',
        );
      }
      if (mounted) {
        adminMessage(
          context,
          source == null
              ? 'Profile created. Open it to configure access and defaults.'
              : 'Profile cloned. Check inherited access and defaults before using it.',
        );
      }
      refresh();
    } catch (e) {
      if (mounted) _error = administrationError(e, writing: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _change(
    HermesProfile profile,
    String action,
    VoidCallback refresh,
  ) async {
    String? name;
    if (action == 'rename') {
      name = await _name(
        'Rename ${profile.label}',
        initial: profile.isDefault ? profile.label : profile.name,
        displayOnly: profile.isDefault,
      );
      if (name == null || !mounted) return;
    }
    if (!mounted ||
        !await adminConfirm(
          context,
          action == 'delete'
              ? 'Delete ${profile.label}?'
              : 'Rename ${profile.label}?',
          action == 'delete'
              ? 'This removes the profile and its retained data. A running profile gateway may be stopped.'
              : profile.isDefault
              ? 'Only the display name changes. The default profile keeps its identity.'
              : 'A running profile gateway may be stopped. Open editors will keep their original target.',
          action: action == 'delete' ? 'Delete profile' : 'Rename',
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.server.write(
        action == 'delete' ? 'DELETE' : 'PATCH',
        'profiles/${Uri.encodeComponent(profile.name)}',
        action == 'rename' ? {'new_name': name} : {},
      );
      final after = await widget.server.discover();
      final verified = action == 'delete'
          ? after.named(profile.name) == null
          : profile.isDefault
          ? after.named('default')?.displayName == name
          : result['name'] is String && after.named(result['name']) != null;
      if (!verified) {
        throw const AdministrationFailure(
          'The change could not be confirmed. Refresh before retrying.',
        );
      }
      refresh();
      if (mounted) {
        adminMessage(
          context,
          action == 'delete' ? 'Profile deleted.' : 'Profile renamed.',
        );
      }
    } catch (e) {
      if (mounted) _error = administrationError(e, writing: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Profiles',
    scope: widget.server.connectionLabel,
    child: AdminLoad(
      load: () => widget.server.read('profiles'),
      builder: (context, data, refresh) {
        final profiles = administrationRows(
          data['profiles'],
        ).map(HermesProfile.fromJson);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) AdminNotice.error(_error!),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _create(refresh),
                icon: const Icon(Icons.add),
                label: const Text('Create profile'),
              ),
            ),
            const SizedBox(height: 16),
            AdminGroup(
              children: [
                for (final profile in profiles)
                  ListTile(
                    title: Text(profile.label),
                    subtitle: Text(profile.description ?? profile.name),
                    onTap: _busy
                        ? null
                        : () async {
                            final opened = await widget.onOpenProfile(
                              profile.name,
                            );
                            if (context.mounted && opened) {
                              Navigator.pop(context);
                            }
                          },
                    trailing: PopupMenuButton<String>(
                      enabled: !_busy,
                      tooltip: 'Manage ${profile.label}',
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'clone',
                          child: Text('Clone configuration'),
                        ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        if (!profile.isDefault)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                      ],
                      onSelected: (value) => value == 'clone'
                          ? _create(refresh, profile.name)
                          : _change(profile, value, refresh),
                    ),
                  ),
              ],
            ),
            TextButton(
              onPressed: _busy ? null : refresh,
              child: const Text('Refresh'),
            ),
          ],
        );
      },
    ),
  );
}

class _ProfileNameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final bool displayOnly;
  const _ProfileNameDialog({
    required this.title,
    required this.initial,
    this.displayOnly = false,
  });
  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  late String _name = widget.initial;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: TextFormField(
      initialValue: widget.initial,
      autofocus: true,
      decoration: InputDecoration(
        labelText: 'Name',
        helperMaxLines: 4,
        helperText: widget.displayOnly
            ? 'Display name. The default identity stays unchanged.'
            : 'Lowercase letters, numbers, hyphens or underscores.',
      ),
      onChanged: (v) => setState(() => _name = v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.displayOnly
            ? (_name.isEmpty ? null : () => Navigator.pop(context, _name))
            : !HermesProfile.isCanonicalName(_name) || _name == 'current'
            ? null
            : () => Navigator.pop(context, _name),
        child: const Text('Continue'),
      ),
    ],
  );
}
