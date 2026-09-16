import 'dart:async';
import '../../widgets/studio_select.dart';
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
    help:
        'Characters retained for this profile; this is a budget, not current usage.',
    minimum: 1,
  ),
  AdminField(
    'memory.user_char_limit',
    'User preference budget',
    AdminFieldKind.integer,
    help:
        'Characters retained for this profile; this is a budget, not current usage.',
    minimum: 1,
  ),
];
const executionFields = [
  AdminField(
    'agent.max_turns',
    'Maximum turns',
    AdminFieldKind.integer,
    help: 'Limit the model turns in one agent run.',
    minimum: 1,
  ),
  AdminField(
    'agent.run_budget_seconds',
    'Run time budget',
    AdminFieldKind.integer,
    help: 'Seconds per agent turn. 0 removes the time budget.',
    minimum: 0,
  ),
  AdminField(
    'agent.api_max_retries',
    'API retries',
    AdminFieldKind.integer,
    help: 'How many times Hermes may retry a failed model request.',
    minimum: 0,
  ),
  AdminField(
    'delegation.max_iterations',
    'Subagent iterations',
    AdminFieldKind.integer,
    help: 'Maximum iterations available to each child agent.',
    minimum: 1,
  ),
  AdminField(
    'delegation.max_concurrent_children',
    'Concurrent subagents',
    AdminFieldKind.integer,
    help: 'Maximum child agents working at the same time.',
    minimum: 1,
  ),
  AdminField(
    'delegation.max_spawn_depth',
    'Subagent depth',
    AdminFieldKind.integer,
    help:
        '1 allows one level of children. Extra levels allow children to delegate and can multiply cost.',
    minimum: 1,
  ),
  AdminField(
    'delegation.child_timeout_seconds',
    'Subagent timeout',
    AdminFieldKind.integer,
    help:
        'Seconds per child. 0 disables the timeout; positive values have a 30-second minimum on Hermes.',
    minimum: 0,
  ),
];
const approvalFields = [
  AdminField(
    'approvals.mode',
    'Approval mode',
    AdminFieldKind.choice,
    choices: ['manual', 'smart', 'off'],
    help:
        'Controls the server approval policy. Explicit deny rules still apply.',
  ),
  AdminField(
    'approvals.timeout',
    'Approval timeout',
    AdminFieldKind.integer,
    help:
        'Seconds to wait for a decision. An unanswered gateway request times out; 0 gives no waiting time.',
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
    help: 'Percent of context capacity',
    minimum: 0,
    maximum: 1,
  ),
  AdminField(
    'compression.target_ratio',
    'Target after compression',
    AdminFieldKind.decimal,
    help: 'Percent of context capacity',
    minimum: 0,
    maximum: 1,
  ),
  AdminField(
    'compression.protect_last_n',
    'Protect recent messages',
    AdminFieldKind.integer,
    help: 'Number of recent messages kept during compression.',
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
  final String? initialField;
  const AdminSettingsPage({
    super.key,
    required this.profile,
    required this.title,
    required this.fields,
    this.explanation,
    this.beforeSave,
    this.initialField,
  });
  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  late final _profile = widget.profile;
  final _form = GlobalKey<FormState>();
  final _noticeAnchor = GlobalKey();
  Map<String, dynamic>? _saved;
  List<AdminField> _fields = [];
  final _values = <String, dynamic>{};
  final _inputs = <String, TextEditingController>{};
  String? _error;
  bool _saving = false;
  bool _loading = true;
  bool _leave = false;
  final _anchors = <String, GlobalKey>{};
  final _conflicts = <String, Object?>{};
  bool _emphasizeField = false;
  Timer? _emphasisTimer;
  int get _dirtyCount => _saved == null
      ? 0
      : _values.entries
            .where(
              (entry) => !sameSetting(entry.value, setting(_saved!, entry.key)),
            )
            .length;

  bool _percentage(AdminField field) =>
      field.key == 'compression.threshold' ||
      field.key == 'compression.target_ratio';
  String _text(AdminField field, Object? value) => value is List
      ? value.join('\n')
      : _percentage(field) && value is num
      ? shiftDecimal(value.toString(), 2)
      : value?.toString() ?? '';

  Future<void> _revealField() async {
    await WidgetsBinding.instance.endOfFrame;
    final target = _anchors[widget.initialField]?.currentContext;
    if (!mounted || target == null || !target.mounted) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    setState(() => _emphasizeField = !reduced);
    await Scrollable.ensureVisible(
      target,
      alignment: .15,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 200),
    );
    if (!mounted || reduced) return;
    _emphasisTimer?.cancel();
    _emphasisTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _emphasizeField = false);
    });
  }

  void _resolve(AdminField field, {required bool useServer}) {
    final latest = _conflicts.remove(field.key);
    setState(() {
      setSetting(_saved!, field.key, latest);
      if (useServer) {
        _values[field.key] = latest;
        _inputs[field.key]?.text = _text(field, latest);
      }
      if (_conflicts.isEmpty) _error = null;
    });
  }

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
    _emphasisTimer?.cancel();
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
        final text = _text(field, value);
        _anchors.putIfAbsent(field.key, GlobalKey.new);
        (_inputs[field.key] ??= TextEditingController()).text = text;
      }
    } catch (e) {
      if (mounted) _error = administrationError(e);
    }
    if (mounted) {
      setState(() => _loading = false);
      if (widget.initialField != null) _revealField();
    }
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
    FocusScope.of(context).unfocus();
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
      _conflicts.clear();
      for (final key in changes.keys) {
        if (!sameSetting(setting(latest, key), setting(_saved!, key)) &&
            !sameSetting(setting(latest, key), changes[key])) {
          _conflicts[key] = setting(latest, key);
        }
      }
      if (_conflicts.isNotEmpty) {
        throw const AdministrationFailure(
          'These settings changed elsewhere. Compare the values below, then save your choices.',
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
    if (mounted) {
      setState(() => _saving = false);
      if (_error != null) revealAdminNotice(context, _noticeAnchor);
    }
  }

  Widget _field(AdminField field) {
    final value = _values[field.key];
    if (field.kind == AdminFieldKind.toggle) {
      if (value is! bool) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(field.label, style: Theme.of(context).textTheme.bodyLarge),
            const Text(
              'Current value unavailable. Choose explicitly to set it.',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final enabled in [true, false])
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _values[field.key] = enabled),
                    child: Text(enabled ? 'Enable' : 'Disable'),
                  ),
              ],
            ),
          ],
        );
      }
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSelect<String>(
            value: value is String ? value : null,
            label: field.label,
            options: [
              for (final v in choices)
                (value: v, label: v.isEmpty ? 'Server default' : v),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() => _values[field.key] = v),
          ),
          if (field.key == 'approvals.mode')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(switch (value) {
                'manual' => 'Ask you when a flagged action requires approval.',
                'smart' =>
                  'Hermes uses its approval model to assess flagged actions.',
                'off' =>
                  'Skip the recoverable approval prompts. Hard blocks and explicit deny rules still apply.',
                _ => 'This approval mode was not recognized.',
              }, style: Theme.of(context).textTheme.bodySmall),
            ),
          if (field.help.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                field.help,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );
    }
    final numeric = {
      AdminFieldKind.integer,
      AdminFieldKind.decimal,
    }.contains(field.kind);
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    final input = TextFormField(
      key: ValueKey('setting:${field.key}'),
      controller: _inputs[field.key],
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: largeText ? null : field.label,
        suffixText: _percentage(field) ? '%' : null,
        helperText: field.help.isEmpty ? null : field.help,
        helperMaxLines: 8,
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
            : double.tryParse(
                _percentage(field) ? shiftDecimal(text ?? '', -2) : text ?? '',
              );
        if (number == null || !number.isFinite) return 'Enter a valid number';
        if (field.minimum != null && number < field.minimum!) {
          return 'Minimum: ${_text(field, field.minimum)}${_percentage(field) ? '%' : ''}';
        }
        if (field.maximum != null && number > field.maximum!) {
          return 'Maximum: ${_text(field, field.maximum)}${_percentage(field) ? '%' : ''}';
        }
        return null;
      },
      onChanged: (text) => setState(() {
        _values[field.key] = switch (field.kind) {
          AdminFieldKind.integer => int.tryParse(text),
          AdminFieldKind.decimal => double.tryParse(
            _percentage(field) ? shiftDecimal(text, -2) : text,
          ),
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
    if (!largeText) return input;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(field.label, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 8),
        Semantics(label: field.label, child: input),
      ],
    );
  }

  Widget _comparison(AdminField field) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Current server value: ${_text(field, _conflicts[field.key])}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          'Your value: ${_text(field, _values[field.key])}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => _resolve(field, useServer: false),
              child: const Text('Keep my value'),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => _resolve(field, useServer: true),
              child: const Text('Use server value'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _compressionDiagram() => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Make room in long conversations',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Compression starts at the threshold and aims for the target below. Recent protected messages stay in context.',
        ),
        for (final (key, label) in [
          ('compression.threshold', 'Start at'),
          ('compression.target_ratio', 'Target'),
        ])
          if (_values[key] case final num value) ...[
            const SizedBox(height: 12),
            Text('$label ${shiftDecimal(value.toString(), 2)}%'),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: value.toDouble().clamp(0, 1),
              semanticsLabel:
                  '$label ${shiftDecimal(value.toString(), 2)} percent of capacity',
            ),
          ],
        const SizedBox(height: 8),
        Text(
          'Configured limits · Not live usage',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

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
          : AdminEditorActions(
              dirtyCount: _dirtyCount,
              saving: _saving,
              onClose: _close,
              onSave: _dirty && _conflicts.isEmpty ? _save : null,
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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Saved for this profile. Existing chats may keep their current settings.',
                          ),
                          const SizedBox(height: 16),
                          if (widget.fields.any((field) => _percentage(field)))
                            _compressionDiagram(),
                          if (widget.explanation != null)
                            AdminNotice(widget.explanation!),
                          if (_error != null)
                            AdminNotice.error(_error!, key: _noticeAnchor),
                          if (_fields.length < widget.fields.length)
                            const AdminNotice(
                              'Some settings are not exposed by this server.',
                            ),
                          for (final field in _fields)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Container(
                                key: _anchors[field.key],
                                decoration: BoxDecoration(
                                  color:
                                      _emphasizeField &&
                                          widget.initialField == field.key
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : null,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _field(field),
                                    if (_conflicts.containsKey(field.key))
                                      _comparison(field),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}

/// Shift decimal text without introducing binary floating-point display noise.
/// Invalid input stays invalid for the field validator.
String shiftDecimal(String input, int places) {
  final match = RegExp(
    r'^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$',
  ).firstMatch(input.trim());
  if (match == null) return input;
  final whole = match[2]!;
  final digits = whole + (match[3] ?? '');
  if (digits.isEmpty) return input;
  final exponent = int.tryParse(match[4] ?? '0');
  if (exponent == null) return input;
  final position = whole.length + places + exponent;
  if (position.abs() > 1000) return input;
  var result = position <= 0
      ? '0.${'0' * -position}$digits'
      : position >= digits.length
      ? '$digits${'0' * (position - digits.length)}'
      : '${digits.substring(0, position)}.${digits.substring(position)}';
  result = result.replaceFirst(RegExp(r'^0+(?=[0-9])'), '');
  if (result.contains('.')) {
    result = result
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return '${match[1]}$result';
}
