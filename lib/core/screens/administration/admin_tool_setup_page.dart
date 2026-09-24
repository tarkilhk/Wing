import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../widgets/model_chooser.dart';
import 'admin_widgets.dart';
import 'admin_operations_page.dart';
import 'admin_providers_page.dart';
import 'admin_settings_page.dart';
import 'admin_speech_synthesis_page.dart';

class AdminToolSetupList extends StatelessWidget {
  final ProfileAdministration profile;
  const AdminToolSetupList({super.key, required this.profile});
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Tool setup',
    scope: profile.label,
    child: AdminLoad(
      load: () => profile.read('tools/toolsets'),
      builder: (context, data, refresh) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AdminNotice(
            'Open a toolset to check its providers and setup requirements for this profile.',
          ),
          AdminGroup(
            children: [
              for (final row in administrationRows(data['data']))
                AdminRow(
                  title: '${row['label'] ?? row['name']}',
                  subtitle:
                      '${row['platform_label'] ?? row['platform']} · ${row['enabled'] == true ? 'Enabled' : 'Disabled'}',
                  icon: Icons.build_outlined,
                  onTap: () => adminPushProfile(
                    context,
                    profile,
                    (context, profile) => AdminToolSetupPage(
                      profile: profile,
                      name: row['name'] as String,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AdminToolSetupPage extends StatefulWidget {
  final ProfileAdministration profile;
  final String name;
  const AdminToolSetupPage({
    super.key,
    required this.profile,
    required this.name,
  });
  @override
  State<AdminToolSetupPage> createState() => _AdminToolSetupPageState();
}

class _AdminToolSetupPageState extends State<AdminToolSetupPage> {
  late final _profile = widget.profile;
  late final _base = 'tools/toolsets/${Uri.encodeComponent(widget.name)}';
  // The current Hermes matrix also contains credential/setup-only rows.
  // It does not expose a can-select flag; only these toolsets persist a choice.
  bool get _canSelectProvider => const {
    'web',
    'stt',
    'tts',
    'image_gen',
    'video_gen',
    'browser',
    'computer_use',
  }.contains(widget.name);
  bool _busy = false;
  String? _notice;
  bool _noticeIsError = false;

  String? _selectedLabel(Map<String, dynamic> data, Map<String, dynamic> row) {
    if (widget.name == 'web') {
      final backend = row['web_backend'];
      if (backend == null) return null;
      final capabilities = [
        for (final capability in ['search', 'extract'])
          if (data['active_${capability}_backend'] == backend) capability,
      ];
      return capabilities.isEmpty
          ? null
          : 'Selected for ${capabilities.join(' and ')}';
    }
    return row['is_active'] == true ||
            (data['active_provider'] != null &&
                data['active_provider'] == row['name'])
        ? 'Selected'
        : null;
  }

  Future<void> _provider(
    Map<String, dynamic> row,
    VoidCallback refresh, [
    String? capability,
  ]) async {
    setState(() {
      _busy = true;
      _notice = null;
      _noticeIsError = false;
    });
    try {
      final result = await _profile.write('PUT', '$_base/provider', {
        'provider': row['name'],
        'capability': ?capability,
      });
      final after = await _profile.read('$_base/config');
      final verified = capability == null
          ? after['active_provider'] == row['name'] ||
                administrationRows(after['providers'] ?? []).any(
                  (candidate) =>
                      candidate['name'] == row['name'] &&
                      candidate['is_active'] == true,
                )
          : after['active_${capability}_backend'] == row['web_backend'];
      // Managed selections are saved before entitlement is available, so the
      // readiness endpoint deliberately does not report them as active yet.
      final needsAccount =
          result['ok'] == true &&
          result['provider'] == row['name'] &&
          result['needs_nous_auth'] == true;
      if (!verified && !needsAccount) {
        throw const AdministrationFailure(
          'Provider selection could not be confirmed.',
        );
      }
      refresh();
      if (mounted) {
        setState(
          () => _notice = needsAccount
              ? 'Selection saved. This provider still needs account access.'
              : 'Provider selection saved.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = administrationError(e, writing: true);
          _noticeIsError = true;
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setup(String key, VoidCallback refresh) async {
    if (!await adminConfirm(
      context,
      'Install setup requirements?',
      'Hermes may download and install dependencies on the server. Other profiles can share those dependencies.',
      action: 'Run setup',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _profile.write('POST', '$_base/post-setup', {
        'key': key,
      });
      final action = AdministrationAction.fromJson(result);
      if (mounted) {
        await adminPush(
          context,
          (context) => AdminActionPage(
            server: _profile.server,
            action: action,
            title: 'Tool setup',
            scope: _profile.label,
          ),
        );
      }
      refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = administrationError(e, writing: true);
          _noticeIsError = true;
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.name == 'tts') {
      return AdminSpeechSynthesisPage(profile: _profile);
    }
    return _toolSetup(context);
  }

  Widget _toolSetup(BuildContext context) => AdminPage(
    title: '${widget.name} setup',
    scope: _profile.label,
    child: AdminLoad(
      load: () => _profile.read('$_base/config'),
      builder: (context, data, refresh) {
        final providers = administrationRows(data['providers']);
        final orderedProviders = [
          ...providers.where((row) => _selectedLabel(data, row) != null),
          ...providers.where((row) => _selectedLabel(data, row) == null),
        ];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_notice != null) AdminNotice(_notice!, isError: _noticeIsError),
            TextButton(
              onPressed: _busy ? null : refresh,
              child: const Text('Refresh readiness'),
            ),
            if (providers.isEmpty)
              const AdminNotice(
                'No guided provider setup is reported for this toolset.',
              ),
            for (final row in orderedProviders)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AdminGroup(
                  key: Key('tool-provider-${row['name']}'),
                  selected: _selectedLabel(data, row) != null,
                  children: [
                    Semantics(
                      selected: _selectedLabel(data, row) != null,
                      child: ListTile(
                        selected: _selectedLabel(data, row) != null,
                        title: Text('${row['name']}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedLabel(data, row) case final label?)
                              Text(
                                label,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text('${row['status'] ?? 'Unknown readiness'}'),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (widget.name == 'web') ...[
                            for (final cap in ['search', 'extract'])
                              if ((row['capabilities'] as List? ?? []).contains(
                                cap,
                              ))
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _provider(row, refresh, cap),
                                  child: Text('Use for $cap'),
                                ),
                          ] else if (_canSelectProvider)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _provider(row, refresh),
                              child: const Text('Use provider'),
                            ),
                          if (const {
                            'image_gen',
                            'video_gen',
                          }.contains(widget.name))
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => adminPushProfile(
                                      context,
                                      _profile,
                                      (context, profile) => AdminToolModelsPage(
                                        profile: profile,
                                        tool: widget.name,
                                        provider: row['name'] as String,
                                      ),
                                    ),
                              child: const Text('Models'),
                            ),
                          if (row['post_setup'] is String)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _setup(
                                      row['post_setup'] as String,
                                      refresh,
                                    ),
                              child: const Text('Setup requirements'),
                            ),
                        ],
                      ),
                    ),
                    for (final env in administrationRows(row['env_vars'] ?? []))
                      ListTile(
                        title: Text('${env['prompt'] ?? env['key']}'),
                        subtitle: Text(
                          env['is_set'] == true
                              ? 'Available to this profile'
                              : 'Not available',
                        ),
                        trailing: const Icon(Icons.key_outlined),
                        onTap: _busy
                            ? null
                            : () async {
                                await adminPushProfile(
                                  context,
                                  _profile,
                                  (context, profile) => AdminSecretPage(
                                    profile: profile,
                                    name: env['key'] as String,

                                    isSet: false,
                                  ),
                                );
                                refresh();
                              },
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AdminToolModelsPage extends StatefulWidget {
  final ProfileAdministration profile;
  final String tool, provider;
  const AdminToolModelsPage({
    super.key,
    required this.profile,
    required this.tool,
    required this.provider,
  });
  @override
  State<AdminToolModelsPage> createState() => _AdminToolModelsPageState();
}

class _AdminToolModelsPageState extends State<AdminToolModelsPage> {
  bool _busy = false;
  String? _error;
  String? _pendingModel;
  String get _base => 'tools/toolsets/${Uri.encodeComponent(widget.tool)}';

  Future<Map<String, dynamic>> _readCatalog() =>
      widget.profile.read('$_base/models', {'provider': widget.provider});

  List<ModelChoice> _choices(Map<String, dynamic> data) => [
    for (final model in administrationRows(data['models'] ?? []))
      if (model['id'] is String && (model['id'] as String).isNotEmpty)
        ModelChoice(
          provider: widget.provider,
          model: model['id'] as String,
          displayName: model['display']?.toString(),
          detail: [model['strengths'], model['speed'], model['price']]
              .where((value) => value != null && value.toString().isNotEmpty)
              .join(' · '),
        ),
  ];

  Future<void> _select(VoidCallback refresh) async {
    final model = _pendingModel;
    if (model == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.profile.write('PUT', '$_base/model', {
        'model': model,
        'provider': widget.provider,
      });
      final after = await _readCatalog();
      if (after['current'] != model) {
        throw const AdministrationFailure(
          'Model selection could not be confirmed.',
        );
      }
      if (mounted) setState(() => _pendingModel = null);
      refresh();
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: '${widget.provider} models',
    scope: widget.profile.label,
    child: AdminLoad(
      load: _readCatalog,
      builder: (context, data, refresh) {
        final choices = _choices(data);
        final current = data['current']?.toString();
        final selectedId = _pendingModel ?? current;
        return Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AdminNotice.error(_error!),
              ),
            if (data['has_models'] != true)
              const Expanded(
                child: Center(
                  child: AdminNotice(
                    'This tool provider does not expose a model catalog here.',
                  ),
                ),
              )
            else
              Expanded(
                child: ModelChooser(
                  choices: choices,
                  selected: selectedId == null || selectedId.isEmpty
                      ? null
                      : ModelSelection.model(
                          ModelChoice(
                            provider: widget.provider,
                            model: selectedId,
                          ),
                        ),
                  onSelected: (selection) =>
                      setState(() => _pendingModel = selection.choice?.model),
                  onRefresh: () async => _choices(await _readCatalog()),
                  scopeLabel: 'Models for ${widget.provider}',
                  keyPrefix: 'tool-model',
                  groupByProvider: false,
                  promoteSelected: true,
                  enabled: !_busy,
                ),
              ),
            if (data['has_models'] == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed:
                        _busy ||
                            _pendingModel == null ||
                            _pendingModel == current
                        ? null
                        : () => _select(refresh),
                    child: Text(_busy ? 'Saving…' : 'Use model'),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AdminVoicePage extends StatelessWidget {
  final ProfileAdministration profile;
  const AdminVoicePage({super.key, required this.profile});
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Voice',
    scope: profile.label,
    child: AdminLoad(
      load: () async {
        final data = await Future.wait([
          profile.config(),
          profile.read('config/schema'),
        ]);
        return {'config': data[0], 'schema': data[1]};
      },
      builder: (context, data, refresh) {
        final config = Map<String, dynamic>.from(data['config'] as Map);
        final schema = (data['schema'] as Map)['fields'] as Map;
        final keys = schema.keys.whereType<String>().where((key) {
          for (final kind in ['stt', 'tts']) {
            final provider = setting(config, '$kind.provider');
            if (provider is String &&
                key.startsWith('$kind.$provider.') &&
                RegExp(
                  r'\.(voice|voice_id|model|model_id|language|language_code)$',
                ).hasMatch(key)) {
              return true;
            }
          }
          return false;
        });
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AdminGroup(
              children: [
                AdminRow(
                  title: 'Speech recognition provider',
                  subtitle: 'Configured backend providers and keys',
                  icon: Icons.mic_none,
                  onTap: () => adminPushProfile(
                    context,
                    profile,
                    (context, profile) =>
                        AdminToolSetupPage(profile: profile, name: 'stt'),
                  ),
                ),
                AdminRow(
                  title: 'Speech synthesis provider',
                  subtitle: 'Configured backend providers and keys',
                  icon: Icons.volume_up_outlined,
                  onTap: () => adminPushProfile(
                    context,
                    profile,
                    (context, profile) =>
                        AdminToolSetupPage(profile: profile, name: 'tts'),
                  ),
                ),
                AdminRow(
                  title: 'Speech defaults',
                  subtitle: 'Language, model and automatic speech',
                  icon: Icons.tune,
                  onTap: () => adminPushProfile(
                    context,
                    profile,
                    (context, profile) => AdminSettingsPage(
                      profile: profile,
                      title: 'Speech defaults',
                      fields: [
                        ...voiceFields.where((f) => f.key != 'tts.provider'),
                        for (final key in keys.where(
                          (key) =>
                              !RegExp(r'\.(voice|voice_id)$').hasMatch(key),
                        ))
                          AdminField(
                            key,
                            key.split('.').skip(1).join(' '),
                            AdminFieldKind.text,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: refresh,
              child: const Text('Refresh configured providers'),
            ),
          ],
        );
      },
    ),
  );
}
