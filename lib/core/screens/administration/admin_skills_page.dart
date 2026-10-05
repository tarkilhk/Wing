import 'package:flutter/material.dart';
import '../../models/profile_skills.dart';
import '../../services/profile_skills_session.dart';
import '../../services/administration_operation_session.dart';
import '../../widgets/studio_action_label.dart';
import '../../widgets/compact_switch.dart';
import '../../widgets/read_recovery.dart';
import 'admin_widgets.dart';
import 'admin_operations_page.dart';

Future<void> _showResult(
  BuildContext context,
  ProfileSkillsSession session,
  AdministrationOperationSession operation,
  String title,
) => adminPush(
  context,
  (context) => AdminActionPage(
    operation: operation,
    title: title,
    scope: session.scopeLabel,
  ),
);

class AdminSkillLibraryPage extends StatefulWidget {
  const AdminSkillLibraryPage({super.key, required this.createSession});
  final ProfileSkillsSession Function() createSession;
  @override
  State<AdminSkillLibraryPage> createState() => _AdminSkillLibraryPageState();
}

class _AdminSkillLibraryPageState extends State<AdminSkillLibraryPage> {
  late final _session = widget.createSession();
  final _search = TextEditingController();
  String _query = '';
  bool _usageOrder = false;
  @override
  void initState() {
    super.initState();
    _session.refresh();
  }

  @override
  void dispose() {
    _session.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(InstalledSkill skill) async {
    final route = _session.openSkill(skill);
    try {
      await adminPush(
        context,
        (_) => AdminSkillDetail(session: _session, route: route),
      );
    } finally {
      _session.releaseDetail(route);
    }
    await _session.refresh();
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Skill library',
    scope: _session.scopeLabel,
    child: _SkillsRead(
      session: _session,
      retry: _session.refresh,
      builder: (state) {
        final rows = [...state.installed];
        if (_usageOrder) rows.sort((a, b) => b.usage.compareTo(a.usage));
        final matches = rows.where((s) => s.matches(_query)).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search installed skills',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
            ),
            CompactSwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Order by recorded usage'),
              value: _usageOrder,
              onChanged: (value) => setState(() => _usageOrder = value),
            ),
            for (final skill in matches)
              ListTile(
                title: Text(skill.name),
                subtitle: Text(
                  '${skill.provenance} · ${skill.usage} recorded uses',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: state.canMutate ? () => _open(skill) : null,
              ),
            if (rows.isEmpty)
              const AdminNotice('No skills reported for this profile.')
            else if (matches.isEmpty) ...[
              const AdminNotice('No installed skills match this search.'),
              TextButton(
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
                child: const Text('Clear search'),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class AdminSkillDetail extends StatefulWidget {
  const AdminSkillDetail({
    super.key,
    required this.session,
    required this.route,
  });
  final ProfileSkillsSession session;
  final SkillDetailRoute route;
  @override
  State<AdminSkillDetail> createState() => _AdminSkillDetailState();
}

class _AdminSkillDetailState extends State<AdminSkillDetail> {
  late final _session = widget.session;
  late final _route = widget.route;
  @override
  void initState() {
    super.initState();
    _session.loadDetail(_route);
  }

  @override
  void dispose() {
    _session.releaseDetail(_route);
    super.dispose();
  }

  Future<void> _edit() async {
    final editor = _session.openEditor(_route);
    try {
      await adminPush(
        context,
        (_) =>
            AdminSkillEditor(session: _session, route: editor, detail: _route),
      );
    } finally {
      _session.releaseEditor(editor);
    }
    await _session.loadDetail(_route);
  }

  Future<void> _archive() async {
    final removed = await _session.archive(
      _route,
      () => adminConfirm(
        context,
        'Archive ${_route.skill.name}?',
        'Move this local or learned skill out of the active skill library for ${_session.profileName}.',
        action: 'Archive',
      ),
    );
    if (!mounted) return;
    if (removed) {
      Navigator.pop(context);
    } else if (_session.state.error case final error?) {
      adminMessage(context, error, isError: true);
    }
  }

  Future<void> _uninstall() => _session.uninstall(
    _route,
    confirm: () => adminConfirm(
      context,
      'Uninstall ${_route.skill.name}?',
      'Remove this Hub skill from ${_session.profileName}.',
      action: 'Uninstall',
    ),
    showResult: (operation) async {
      if (mounted) {
        await _showResult(context, _session, operation, 'Uninstall skill');
      }
    },
  );
  @override
  Widget build(BuildContext context) => AdminPage(
    title: _route.skill.name,
    scope: _session.scopeLabel,
    child: _SkillsRead(
      session: _session,
      retry: () => _session.loadDetail(_route),
      builder: (state) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminNotice(
            'Origin: ${_session.currentSkill(_route)?.provenance ?? _route.skill.provenance}',
          ),
          SelectableText(state.instructions?.content ?? ''),
          const SizedBox(height: 16),
          if ((_session.currentSkill(_route) ?? _route.skill).editable)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _session.canEdit(_route) ? _edit : null,
                  child: const Text('Edit instructions'),
                ),
                TextButton(
                  onPressed: _session.canEdit(_route) ? _archive : null,
                  child: const Text('Archive skill'),
                ),
              ],
            ),
          if ((_session.currentSkill(_route) ?? _route.skill).uninstallable)
            TextButton(
              onPressed: _session.canUninstall(_route) ? _uninstall : null,
              child: const Text('Uninstall Hub skill'),
            ),
          TextButton(
            onPressed: state.busy ? null : () => _session.loadDetail(_route),
            child: const Text('Refresh'),
          ),
        ],
      ),
    ),
  );
}

class AdminSkillEditor extends StatefulWidget {
  const AdminSkillEditor({
    super.key,
    required this.session,
    required this.route,
    required this.detail,
  });
  final ProfileSkillsSession session;
  final SkillEditorRoute route;
  final SkillDetailRoute detail;
  @override
  State<AdminSkillEditor> createState() => _AdminSkillEditorState();
}

class _AdminSkillEditorState extends State<AdminSkillEditor> {
  late final _session = widget.session;
  late final _route = widget.route;
  late final _detail = widget.detail;
  late final _input = TextEditingController(text: _route.initial);
  @override
  void dispose() {
    _session.releaseEditor(_route);
    _input.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (await _session.requestClose(
          _route,
          () => adminConfirm(
            context,
            'Discard instruction edits?',
            'The unsaved instructions will be discarded.',
            action: 'Discard',
          ),
        ) &&
        mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    await _session.save(_route);
    if (mounted) {
      if (_session.state.notice case final notice?) {
        adminMessage(context, notice);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      final state = _session.state;
      return PopScope(
        canPop: state.canPopEditor,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: AdminPage(
          title: 'Edit ${_route.name}',
          scope: _session.scopeLabel,
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: state.busy ? null : _close,
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: state.canSave ? _save : null,
                    child: StudioActionLabel('Save', busy: state.saving),
                  ),
                ],
              ),
            ),
          ),
          child: Column(
            children: [
              if (state.error ?? state.edit?.validationError case final error?)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AdminNotice.error(
                      error,
                      retry: state.busy
                          ? null
                          : () => _session.loadDetail(_detail),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _input,
                    enabled: !state.busy,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: 'Instructions',
                    ),
                    onChanged: (value) => _session.edit(_route, value),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class AdminSkillHubPage extends StatefulWidget {
  const AdminSkillHubPage({super.key, required this.createSession});
  final ProfileSkillsSession Function() createSession;
  @override
  State<AdminSkillHubPage> createState() => _AdminSkillHubPageState();
}

class _AdminSkillHubPageState extends State<AdminSkillHubPage> {
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

  Future<void> _open(HubSkill skill) async {
    final route = _session.openPreview(skill);
    try {
      await adminPush(
        context,
        (_) => AdminSkillPreview(session: _session, route: route),
      );
    } finally {
      _session.releasePreview(route);
    }
    await _session.refresh();
  }

  Future<void> _update() => _session.update(
    confirm: () => adminConfirm(
      context,
      'Update installed Hub skills?',
      'Hermes will update installed Hub skills in ${_session.profileName} as a group.',
      action: 'Update skills',
    ),
    showResult: (operation) async {
      if (mounted) {
        await _showResult(context, _session, operation, 'Update skills');
      }
    },
  );
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Skill Hub',
    scope: _session.scopeLabel,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search catalogs',
              helperMaxLines: 4,
              helperText: 'Submit to search configured sources.',
            ),
            onSubmitted: (value) => _session.refresh(query: value),
          ),
        ),
        Expanded(
          child: _SkillsRead(
            session: _session,
            retry: _session.refresh,
            builder: (state) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextButton(
                  onPressed: state.canMutate ? _update : null,
                  child: const Text('Update installed Hub skills'),
                ),
                if (state.partial)
                  const AdminNotice(
                    'Some sources did not respond. Showing partial results.',
                  ),
                if (state.catalog.isEmpty)
                  const AdminNotice('No skills found.'),
                for (final skill in state.catalog)
                  ListTile(
                    title: Text(skill.name),
                    subtitle: Text('${skill.source} · ${skill.description}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: state.canMutate ? () => _open(skill) : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class AdminSkillPreview extends StatefulWidget {
  const AdminSkillPreview({
    super.key,
    required this.session,
    required this.route,
  });
  final ProfileSkillsSession session;
  final SkillPreviewRoute route;
  @override
  State<AdminSkillPreview> createState() => _AdminSkillPreviewState();
}

class _AdminSkillPreviewState extends State<AdminSkillPreview> {
  late final _session = widget.session;
  late final _route = widget.route;
  @override
  void initState() {
    super.initState();
    _session.loadPreview(_route);
  }

  @override
  void dispose() {
    _session.releasePreview(_route);
    super.dispose();
  }

  Future<void> _install() => _session.install(
    _route,
    confirm: () => adminConfirm(
      context,
      'Install this skill?',
      'Install ${_route.skill.identifier} into ${_session.profileName}. Review its source and instructions first.',
      action: 'Install',
    ),
    showResult: (operation) async {
      if (mounted) {
        await _showResult(context, _session, operation, 'Install skill');
      }
    },
  );
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Skill preview',
    scope: _session.scopeLabel,
    child: _SkillsRead(
      session: _session,
      retry: () => _session.loadPreview(_route),
      builder: (state) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.preview case final preview?) ...[
            Text(preview.name, style: Theme.of(context).textTheme.titleLarge),
            AdminNotice('${preview.source} · ${preview.trust}'),
            SelectableText(preview.content),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: state.canMutate ? _install : null,
              child: StudioActionLabel('Install', busy: state.saving),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Read progress/recovery are presentation; the session decides retry eligibility.
class _SkillsRead extends StatelessWidget {
  const _SkillsRead({
    required this.session,
    required this.retry,
    required this.builder,
  });
  final ProfileSkillsSession session;
  final Future<void> Function() retry;
  final Widget Function(ProfileSkillsState) builder;
  @override
  Widget build(BuildContext context) => ReadRecovery(
    shouldRetry: () => session.canRecoverRead,
    retry: retry,
    child: ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final state = session.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.phase == SkillsPhase.reading || state.saving)
              const LinearProgressIndicator(),
            if (state.error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AdminNotice.error(
                  error,
                  retry: state.busy ? null : retry,
                ),
              ),
            if (state.notice case final notice?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AdminNotice(notice),
              ),
            if (state.hasObservation)
              Expanded(key: const ValueKey('content'), child: builder(state)),
          ],
        );
      },
    ),
  );
}
