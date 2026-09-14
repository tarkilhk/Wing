import 'package:flutter/material.dart';
import '../../widgets/compact_switch.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';
import 'admin_operations_page.dart';

class AdminSkillLibraryPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminSkillLibraryPage({super.key, required this.profile});
  @override
  State<AdminSkillLibraryPage> createState() => _AdminSkillLibraryPageState();
}

class _AdminSkillLibraryPageState extends State<AdminSkillLibraryPage> {
  String _query = '';
  bool _usageOrder = false;
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Skill library',
    scope: widget.profile.label,
    child: AdminLoad(
      load: () => widget.profile.read('skills'),
      builder: (context, data, refresh) {
        final rows = administrationRows(data['data']);
        if (_usageOrder) rows.sort((a, b) => _usage(b).compareTo(_usage(a)));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search installed skills',
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            CompactSwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Order by recorded usage'),
              value: _usageOrder,
              onChanged: (v) => setState(() => _usageOrder = v),
            ),
            for (final row in rows.where(
              (r) => '${r['name']} ${r['description']}'.toLowerCase().contains(
                _query,
              ),
            ))
              ListTile(
                title: Text('${row['name']}'),
                subtitle: Text(
                  '${row['provenance'] ?? 'Unknown origin'} · ${_usage(row)} recorded uses',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await adminPush(
                    context,
                    AdminSkillDetail(profile: widget.profile, row: row),
                  );
                  refresh();
                },
              ),
            if (rows.isEmpty)
              const AdminNotice('No skills reported for this profile.'),
          ],
        );
      },
    ),
  );
  int _usage(Map<String, dynamic> row) {
    final usage = row['usage'];
    return usage is num
        ? usage.toInt()
        : usage is Map
        ? (usage['count'] as num? ?? 0).toInt()
        : 0;
  }
}

class AdminSkillDetail extends StatefulWidget {
  final ProfileAdministration profile;
  final Map<String, dynamic> row;
  const AdminSkillDetail({super.key, required this.profile, required this.row});
  @override
  State<AdminSkillDetail> createState() => _AdminSkillDetailState();
}

class _AdminSkillDetailState extends State<AdminSkillDetail> {
  late final _name = widget.row['name'] as String;
  bool _busy = false;
  Future<void> _archive() async {
    if (!await adminConfirm(
      context,
      'Archive $_name?',
      'Move this local or learned skill out of the active skill library for ${widget.profile.name}.',
      action: 'Archive',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.profile.write('DELETE', 'learning/node', {'id': _name});
      final rows = administrationRows(
        (await widget.profile.read('skills'))['data'],
      );
      if (rows.any((r) => r['name'] == _name)) {
        throw const AdministrationFailure('Archive could not be confirmed.');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) adminMessage(context, administrationError(e, writing: true));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _uninstall() async {
    if (!await adminConfirm(
      context,
      'Uninstall $_name?',
      'Remove this Hub skill from ${widget.profile.name}.',
      action: 'Uninstall',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.profile.write(
        'POST',
        'skills/hub/uninstall',
        {'name': _name},
      );
      if (mounted) {
        await adminPush(
          context,
          AdminActionPage(
            server: widget.profile.server,
            action: AdministrationAction.fromJson(result),
            title: 'Uninstall skill',
            scope: widget.profile.label,
          ),
        );
      }
    } catch (e) {
      if (mounted) adminMessage(context, administrationError(e, writing: true));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: _name,
    scope: widget.profile.label,
    child: AdminLoad(
      load: () => widget.profile.read('skills/content', {'name': _name}),
      builder: (context, data, refresh) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminNotice('Origin: ${widget.row['provenance'] ?? 'Unknown'}'),
          SelectableText(data['content'] as String? ?? ''),
          const SizedBox(height: 16),
          if (widget.row['provenance'] == 'agent')
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await adminPush(
                            context,
                            AdminSkillEditor(
                              profile: widget.profile,
                              name: _name,
                              initial: data['content'] as String? ?? '',
                            ),
                          );
                          refresh();
                        },
                  child: const Text('Edit instructions'),
                ),
                TextButton(
                  onPressed: _busy ? null : _archive,
                  child: const Text('Archive skill'),
                ),
              ],
            ),
          if (widget.row['provenance'] == 'hub')
            TextButton(
              onPressed: _busy ? null : _uninstall,
              child: const Text('Uninstall Hub skill'),
            ),
          TextButton(
            onPressed: _busy ? null : refresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
    ),
  );
}

class AdminSkillEditor extends StatefulWidget {
  final ProfileAdministration profile;
  final String name, initial;
  const AdminSkillEditor({
    super.key,
    required this.profile,
    required this.name,
    required this.initial,
  });
  @override
  State<AdminSkillEditor> createState() => _AdminSkillEditorState();
}

class _AdminSkillEditorState extends State<AdminSkillEditor> {
  late final _input = TextEditingController(text: widget.initial);
  late String _saved = widget.initial;
  bool _busy = false;
  bool _leave = false;
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_input.text != _saved &&
        !await adminConfirm(
          context,
          'Discard instruction edits?',
          'The unsaved instructions will be discarded.',
          action: 'Discard',
        )) {
      return;
    }
    if (mounted) {
      setState(() => _leave = true);
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final current = await widget.profile.read('skills/content', {
        'name': widget.name,
      });
      if (current['content'] != _saved) {
        throw const AdministrationFailure(
          'Instructions changed on the server. Keep your draft and reopen the skill to review the changes.',
        );
      }
      final result = await widget.profile.write('PUT', 'skills/content', {
        'name': widget.name,
        'content': _input.text,
      });
      if (result['success'] != true) {
        throw const AdministrationFailure(
          'Instruction save was not acknowledged.',
        );
      }
      final after = await widget.profile.read('skills/content', {
        'name': widget.name,
      });
      if (after['content'] != _input.text) {
        throw const AdministrationFailure(
          'Instruction save could not be confirmed. Your draft is kept.',
        );
      }
      if (mounted) setState(() => _saved = _input.text);
      if (mounted) {
        adminMessage(context, 'Instructions saved for new sessions.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leave || (!_busy && _input.text == _saved),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: AdminPage(
      title: 'Edit ${widget.name}',
      scope: widget.profile.label,
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AdminNotice(_error!),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _input,
                enabled: !_busy,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(labelText: 'Instructions'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _close,
                    child: const Text('Close'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        _busy ||
                            _input.text == _saved ||
                            _input.text.trim().isEmpty
                        ? null
                        : _save,
                    child: Text(_busy ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class AdminSkillHubPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminSkillHubPage({super.key, required this.profile});
  @override
  State<AdminSkillHubPage> createState() => _AdminSkillHubPageState();
}

class _AdminSkillHubPageState extends State<AdminSkillHubPage> {
  String _query = '';
  bool _busy = false;
  Future<void> _update(VoidCallback refresh) async {
    if (!await adminConfirm(
      context,
      'Update installed Hub skills?',
      'Hermes will update installed Hub skills in ${widget.profile.name} as a group.',
      action: 'Update skills',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.profile.write('POST', 'skills/hub/update');
      if (mounted) {
        await adminPush(
          context,
          AdminActionPage(
            server: widget.profile.server,
            action: AdministrationAction.fromJson(result),
            title: 'Update skills',
            scope: widget.profile.label,
          ),
        );
      }
      refresh();
    } catch (e) {
      if (mounted) adminMessage(context, administrationError(e, writing: true));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Skill Hub',
    scope: widget.profile.label,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search catalogs',
              helperText: 'Submit to search configured sources.',
            ),
            onSubmitted: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: AdminLoad(
            key: ValueKey(_query),
            load: () => _query.isEmpty
                ? widget.profile.read('skills/hub/official')
                : widget.profile.read('skills/hub/search', {
                    'q': _query,
                    'limit': '30',
                  }),
            builder: (context, data, refresh) {
              final rows = administrationRows(
                _query.isEmpty ? data['skills'] : data['results'],
              );
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _update(refresh),
                    child: const Text('Update installed Hub skills'),
                  ),
                  if ((data['timed_out'] as List? ?? []).isNotEmpty)
                    const AdminNotice(
                      'Some sources did not respond. Showing partial results.',
                    ),
                  if (rows.isEmpty) const AdminNotice('No skills found.'),
                  for (final row in rows)
                    ListTile(
                      title: Text('${row['name']}'),
                      subtitle: Text(
                        '${row['source'] ?? 'Official'} · ${row['description'] ?? ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await adminPush(
                          context,
                          AdminSkillPreview(
                            profile: widget.profile,
                            identifier: row['identifier'] as String,
                          ),
                        );
                        refresh();
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class AdminSkillPreview extends StatefulWidget {
  final ProfileAdministration profile;
  final String identifier;
  const AdminSkillPreview({
    super.key,
    required this.profile,
    required this.identifier,
  });
  @override
  State<AdminSkillPreview> createState() => _AdminSkillPreviewState();
}

class _AdminSkillPreviewState extends State<AdminSkillPreview> {
  bool _busy = false;
  Future<void> _install() async {
    if (!await adminConfirm(
      context,
      'Install this skill?',
      'Install ${widget.identifier} into ${widget.profile.name}. Review its source and instructions first.',
      action: 'Install',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.profile.write('POST', 'skills/hub/install', {
        'identifier': widget.identifier,
      });
      if (mounted) {
        await adminPush(
          context,
          AdminActionPage(
            server: widget.profile.server,
            action: AdministrationAction.fromJson(result),
            title: 'Install skill',
            scope: widget.profile.label,
          ),
        );
      }
      final rows = administrationRows(
        (await widget.profile.read('skills'))['data'],
      );
      if (mounted) {
        adminMessage(
          context,
          'Inventory refreshed: ${rows.length} installed skills. Check the operation result above.',
        );
      }
    } catch (e) {
      if (mounted) adminMessage(context, administrationError(e, writing: true));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Skill preview',
    scope: widget.profile.label,
    child: AdminLoad(
      load: () => widget.profile.read('skills/hub/preview', {
        'identifier': widget.identifier,
      }),
      builder: (context, data, refresh) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${data['name']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          AdminNotice('${data['source']} · ${data['trust_level']}'),
          SelectableText('${data['skill_md'] ?? ''}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _install,
            child: Text(_busy ? 'Installing…' : 'Install'),
          ),
        ],
      ),
    ),
  );
}
