import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';
import 'admin_operations_page.dart';
import 'admin_providers_page.dart';
import 'admin_settings_page.dart';

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
                  onTap: () => adminPush(
                    context,
                    AdminToolSetupPage(
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
          AdminActionPage(
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
  Widget build(BuildContext context) => AdminPage(
    title: '${widget.name} setup',
    scope: _profile.label,
    child: AdminLoad(
      load: () => _profile.read('$_base/config'),
      builder: (context, data, refresh) {
        final providers = administrationRows(data['providers']);
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
            for (final row in providers)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AdminGroup(
                  children: [
                    ListTile(
                      title: Text('${row['name']}'),
                      subtitle: Text(
                        '${row['status'] ?? 'Unknown readiness'}${row['is_active'] == true ? ' · Selected' : ''}',
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
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => adminPush(
                                    context,
                                    AdminToolModelsPage(
                                      profile: _profile,
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
                                await adminPush(
                                  context,
                                  AdminSecretPage(
                                    profile: _profile,
                                    name: env['key'] as String,
                                    shared: false,
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
  String get _base => 'tools/toolsets/${Uri.encodeComponent(widget.tool)}';
  Future<void> _select(String model, VoidCallback refresh) async {
    setState(() => _busy = true);
    try {
      await widget.profile.write('PUT', '$_base/model', {
        'model': model,
        'provider': widget.provider,
      });
      final after = await widget.profile.read('$_base/models', {
        'provider': widget.provider,
      });
      if (after['current'] != model) {
        throw const AdministrationFailure(
          'Model selection could not be confirmed.',
        );
      }
      refresh();
    } catch (e) {
      if (mounted) {
        adminMessage(
          context,
          administrationError(e, writing: true),
          isError: true,
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: '${widget.provider} models',
    scope: widget.profile.label,
    child: AdminLoad(
      load: () =>
          widget.profile.read('$_base/models', {'provider': widget.provider}),
      builder: (context, data, refresh) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (data['has_models'] != true)
            const AdminNotice(
              'This tool provider does not expose a model catalog here.',
            ),
          for (final model in administrationRows(data['models'] ?? []))
            ListTile(
              selected: data['current'] == model['id'],
              enabled: !_busy,
              title: Text('${model['display'] ?? model['id']}'),
              subtitle: Text(
                '${model['strengths'] ?? ''} ${model['price'] ?? ''}',
              ),
              onTap: _busy
                  ? null
                  : () => _select(model['id'] as String, refresh),
            ),
        ],
      ),
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
            const AdminNotice(
              'These speech settings belong to this server profile. Changes to '
              'providers, language or voice affect every client using this profile. '
              'Choose Local or Hermes processing and Android voices in App settings.',
            ),
            AdminGroup(
              children: [
                AdminRow(
                  title: 'Speech recognition provider',
                  subtitle: 'Configured backend providers and keys',
                  icon: Icons.mic_none,
                  onTap: () => adminPush(
                    context,
                    AdminToolSetupPage(profile: profile, name: 'stt'),
                  ),
                ),
                AdminRow(
                  title: 'Speech synthesis provider',
                  subtitle: 'Configured backend providers and keys',
                  icon: Icons.volume_up_outlined,
                  onTap: () => adminPush(
                    context,
                    AdminToolSetupPage(profile: profile, name: 'tts'),
                  ),
                ),
                AdminRow(
                  title: 'Speech defaults',
                  subtitle: 'Language, voice, model and automatic speech',
                  icon: Icons.tune,
                  onTap: () => adminPush(
                    context,
                    AdminSettingsPage(
                      profile: profile,
                      title: 'Speech defaults',
                      fields: [
                        ...voiceFields.where((f) => f.key != 'tts.provider'),
                        for (final key in keys)
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
