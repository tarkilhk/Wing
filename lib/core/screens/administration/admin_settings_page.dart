import '../../widgets/studio_select.dart';
import '../../widgets/studio_action_label.dart';
import 'package:flutter/material.dart';
import '../../widgets/compact_switch.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';

enum AdminFieldKind { toggle, integer, decimal, text, lines, choice }

class AdminField {
  final String key;
  final String label;
  final String help;
  final AdminFieldKind kind;
  final List<String> choices;
  final num? minimum;
  final num? maximum;
  const AdminField(
    this.key,
    this.label,
    this.kind, {
    this.help = '',
    this.choices = const [],
    this.minimum,
    this.maximum,
  });
}

const memoryFields = [
  AdminField('memory.memory_enabled', 'Retain memories', AdminFieldKind.toggle),
  AdminField(
    'memory.user_profile_enabled',
    'Remember user preferences',
    AdminFieldKind.toggle,
  ),
  AdminField(
    'memory.memory_char_limit',
    'Memory budget',
    AdminFieldKind.integer,
    help: 'Characters',
    minimum: 1,
  ),
  AdminField(
    'memory.user_char_limit',
    'User preference budget',
    AdminFieldKind.integer,
    help: 'Characters',
    minimum: 1,
  ),
];
const executionFields = [
  AdminField(
    'agent.max_turns',
    'Maximum turns',
    AdminFieldKind.integer,
    minimum: 1,
  ),
  AdminField(
    'agent.run_budget_seconds',
    'Run time budget',
    AdminFieldKind.integer,
    help: 'Seconds',
    minimum: 0,
  ),
  AdminField(
    'agent.api_max_retries',
    'API retries',
    AdminFieldKind.integer,
    minimum: 0,
  ),
  AdminField(
    'delegation.max_iterations',
    'Subagent iterations',
    AdminFieldKind.integer,
    minimum: 1,
  ),
  AdminField(
    'delegation.max_concurrent_children',
    'Concurrent subagents',
    AdminFieldKind.integer,
    minimum: 1,
  ),
  AdminField(
    'delegation.max_spawn_depth',
    'Subagent depth',
    AdminFieldKind.integer,
    minimum: 0,
  ),
  AdminField(
    'delegation.child_timeout_seconds',
    'Subagent timeout',
    AdminFieldKind.integer,
    help: 'Seconds',
    minimum: 1,
  ),
];
const approvalFields = [
  AdminField(
    'approvals.mode',
    'Approval mode',
    AdminFieldKind.choice,
    choices: ['manual', 'smart', 'off'],
  ),
  AdminField(
    'approvals.timeout',
    'Approval timeout',
    AdminFieldKind.integer,
    help: 'Seconds',
    minimum: 0,
  ),
  AdminField(
    'command_allowlist',
    'Allowed commands',
    AdminFieldKind.lines,
    help: 'One command per line. These commands may run without asking.',
  ),
  AdminField(
    'approvals.mcp_reload_confirm',
    'Confirm connector reload',
    AdminFieldKind.toggle,
  ),
];
const compressionFields = [
  AdminField(
    'compression.enabled',
    'Compress long conversations',
    AdminFieldKind.toggle,
  ),
  AdminField(
    'compression.threshold',
    'Compression threshold',
    AdminFieldKind.decimal,
    help: 'Fraction of context capacity',
    minimum: 0,
    maximum: 1,
  ),
  AdminField(
    'compression.target_ratio',
    'Target after compression',
    AdminFieldKind.decimal,
    help: 'Fraction of context capacity',
    minimum: 0,
    maximum: 1,
  ),
  AdminField(
    'compression.protect_last_n',
    'Protect recent messages',
    AdminFieldKind.integer,
    minimum: 0,
  ),
];
const reachFields = [
  AdminField(
    'security.redact_secrets',
    'Redact secrets',
    AdminFieldKind.toggle,
  ),
  AdminField(
    'security.allow_private_urls',
    'Allow private URLs',
    AdminFieldKind.toggle,
    help: 'Allow backend requests to private network addresses.',
  ),
  AdminField(
    'checkpoints.enabled',
    'File checkpoints',
    AdminFieldKind.toggle,
    help: 'Keep supported file recovery checkpoints on the backend.',
  ),
];
const voiceFields = [
  AdminField('stt.enabled', 'Speech recognition', AdminFieldKind.toggle),
  AdminField('stt.language', 'Recognition language', AdminFieldKind.text),
  AdminField(
    'tts.provider',
    'Speech provider',
    AdminFieldKind.text,
    help: 'Use a provider configured in Skills and tools.',
  ),
  AdminField('voice.auto_tts', 'Automatic speech', AdminFieldKind.toggle),
];

class AdminSettingsPage extends StatefulWidget {
  final ProfileAdministration profile;
  final String title;
  final List<AdminField> fields;
  final String? explanation;
  final Future<void> Function()? beforeSave;
  const AdminSettingsPage({
    super.key,
    required this.profile,
    required this.title,
    required this.fields,
    this.explanation,
    this.beforeSave,
  });
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  late final _profile = widget.profile;
  final _form = GlobalKey<FormState>();
  Map<String, dynamic>? _saved;
  List<AdminField> _fields = [];
  final _values = <String, dynamic>{};
  final _inputs = <String, TextEditingController>{};
  String? _error;
  bool _saving = false;
  bool _loading = true;
  bool _leave = false;
  bool get _dirty =>
      _saved != null &&
      _values.entries.any(
        (e) => !sameSetting(e.value, setting(_saved!, e.key)),
      );
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _profile.config(),
        _profile.read('config/schema'),
      ]);
      final config = results[0];
      final schema = results[1]['fields'];
      if (schema is! Map) {
        throw const FormatException('Missing settings schema');
      }
      if (!mounted) return;
      _saved = config;
      _fields = widget.fields
          .where(
            (field) =>
                schema.containsKey(field.key) ||
                field.key == 'agent.reasoning_effort' ||
                setting(config, field.key) != null,
          )
          .toList();
      for (final field in _fields) {
        final value = setting(config, field.key);
        _values[field.key] = value;
        final text = value is List ? value.join('\n') : value?.toString() ?? '';
        (_inputs[field.key] ??= TextEditingController()).text = text;
      }
    } catch (e) {
      if (mounted) _error = administrationError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty &&
        !await adminConfirm(
          context,
          'Discard edits?',
          'Your unsaved changes to ${_profile.name} will be discarded.',
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
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final changes = Map<String, dynamic>.fromEntries(
        _values.entries.where(
          (e) => !sameSetting(e.value, setting(_saved!, e.key)),
        ),
      );
      await widget.beforeSave?.call();
      final latest = await _profile.config();
      if (changes.keys.any(
        (key) =>
            !sameSetting(setting(latest, key), setting(_saved!, key)) &&
            !sameSetting(setting(latest, key), changes[key]),
      )) {
        throw const AdministrationFailure(
          'These settings changed elsewhere. Your edits are kept. Close and reopen the editor to review the latest values.',
        );
      }
      await _profile.saveSettings(changes);
      if (!mounted) return;
      setState(() {
        for (final e in changes.entries) {
          setSetting(_saved!, e.key, e.value);
        }
      });
      adminMessage(
        context,
        'Defaults saved for ${_profile.name}. Existing sessions may keep their current settings.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _field(AdminField field) {
    final value = _values[field.key];
    if (field.kind == AdminFieldKind.toggle) {
      return CompactSwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.label),
        subtitle: field.help.isEmpty ? null : Text(field.help),
        value: value == true,
        onChanged: _saving
            ? null
            : (v) => setState(() => _values[field.key] = v),
      );
    }
    if (field.kind == AdminFieldKind.choice) {
      final choices = {...field.choices, if (value is String) value}.toList();
      return StudioSelect<String>(
        value: value is String ? value : null,
        label: field.label,
        options: [
          for (final v in choices)
            (value: v, label: v.isEmpty ? 'Server default' : v),
        ],
        onChanged: _saving
            ? null
            : (v) => setState(() => _values[field.key] = v),
      );
    }
    final numeric = {
      AdminFieldKind.integer,
      AdminFieldKind.decimal,
    }.contains(field.kind);
    return TextFormField(
      controller: _inputs[field.key],
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.help.isEmpty ? null : field.help,
        helperMaxLines: 3,
      ),
      minLines: field.kind == AdminFieldKind.lines ? 3 : 1,
      maxLines: field.kind == AdminFieldKind.lines ? 6 : 1,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      validator: (text) {
        if (!numeric) return null;
        if (sameSetting(_values[field.key], setting(_saved!, field.key))) {
          return null;
        }
        final number = field.kind == AdminFieldKind.integer
            ? int.tryParse(text ?? '')
            : double.tryParse(text ?? '');
        if (number == null || !number.isFinite) return 'Enter a valid number';
        if (field.minimum != null && number < field.minimum!) {
          return 'Minimum: ${field.minimum}';
        }
        if (field.maximum != null && number > field.maximum!) {
          return 'Maximum: ${field.maximum}';
        }
        return null;
      },
      onChanged: (text) => setState(() {
        _values[field.key] = switch (field.kind) {
          AdminFieldKind.integer => int.tryParse(text),
          AdminFieldKind.decimal => double.tryParse(text),
          AdminFieldKind.lines =>
            text
                .split('\n')
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList(),
          _ => text,
        };
      }),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leave || (!_dirty && !_saving),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: AdminPage(
      title: widget.title,
      scope: _profile.label,
      bottomNavigationBar: _loading || _saved == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _saving ? null : _close,
                      child: const Text('Close'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving || !_dirty ? null : _save,
                      child: StudioActionLabel('Save', busy: _saving),
                    ),
                  ],
                ),
              ),
            ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _saved == null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: AdminNotice.error(
                _error ?? 'Settings unavailable',
                retry: _load,
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (widget.explanation != null)
                          AdminNotice(widget.explanation!),
                        if (_error != null) AdminNotice.error(_error!),
                        if (_fields.length < widget.fields.length)
                          const AdminNotice(
                            'Some settings are not exposed by this server.',
                          ),
                        for (final field in _fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: _field(field),
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
