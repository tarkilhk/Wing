import 'dart:async';
import 'package:flutter/material.dart';
import '../../controllers/profile_voice_controller.dart';
import '../../controllers/voice_output_controller.dart';
import '../../services/administration_repository.dart';
import '../../services/android_voice.dart';
import '../../services/profile_voice_repository.dart';
import '../../services/voice_preferences.dart';
import '../../services/voice_sample.dart';
import '../../widgets/studio_selection_tile.dart';
import '../../widgets/studio_select.dart';
import 'admin_providers_page.dart';
import 'admin_operations_page.dart';
import 'admin_widgets.dart';

class AdminSpeechSynthesisPage extends StatefulWidget {
  final ProfileAdministration profile;
  final VoiceDevice? device;
  const AdminSpeechSynthesisPage({
    super.key,
    required this.profile,
    this.device,
  });
  @override
  State<AdminSpeechSynthesisPage> createState() =>
      _AdminSpeechSynthesisPageState();
}

class _AdminSpeechSynthesisPageState extends State<AdminSpeechSynthesisPage>
    with WidgetsBindingObserver {
  late final _profile = widget.profile;
  late final _voices = ProfileVoiceController(ProfileVoiceRepository(_profile));
  late final _player = VoiceOutputController(
    widget.device ?? AndroidVoice.instance,
  );
  final _custom = TextEditingController();
  List<Map<String, dynamic>> _providers = [];
  bool _busy = false;
  bool _confirmed = false;
  String? _error;
  static const _base = 'tools/toolsets/tts';
  Map<String, dynamic>? get _provider => _providers
      .where((row) => speechProviderRoute(row) == _voices.settings?.provider)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _profile.server.retain();
    _voices.addListener(_changed);
    _player.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    try {
      await _player.stop();
    } catch (_) {
      /* Native playback may already have ended. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voices.removeListener(_changed);
    _player.removeListener(_changed);
    _voices.dispose();
    _player.dispose();
    _custom.dispose();
    _profile.server.release();
    super.dispose();
  }

  void _select(String? voice) {
    if (voice == null) return;
    _custom.clear();
    unawaited(_stop());
    unawaited(_voices.select(voice));
  }

  void _customVoice() {
    if (_custom.text.trim().isNotEmpty &&
        _custom.text.trim() != _voices.selected) {
      _select(_custom.text);
    }
  }

  void _play() {
    if (_player.owner != null) {
      unawaited(_stop());
      return;
    }
    final settings = _voices.settings;
    if (settings == null || _voices.saving || !_voices.fresh) return;
    unawaited(
      _player.speak(
        'profile-voice',
        voiceSampleText,
        const VoicePreferences(output: VoiceProcessing.hermes),
        () => _voices.repository.speech(settings),
      ),
    );
  }

  Future<void> _read() async {
    if (!mounted) return;
    _custom.clear();
    final data = await _profile.read('$_base/config');
    _providers = administrationRows(data['providers']);
    await _voices.load();
    _confirmed = _voices.fresh;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _voices.saving) return;
    setState(() {
      _busy = true;
      _confirmed = false;
      _error = null;
    });
    _profile.server.retain();
    try {
      await _stop();
      await action();
    } catch (error) {
      _error = administrationError(error);
      _confirmed = false;
    } finally {
      _profile.server.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(_read);

  Future<void> _selectProvider(String? name) async {
    if (name == null || name == _provider?['name']) return;
    final provider = _providers.singleWhere((row) => row['name'] == name);
    _custom.clear();
    await _run(() async {
      await _profile.write('PUT', '$_base/provider', {'provider': name});
      await _read();
      if (!_confirmed ||
          _voices.settings?.provider != speechProviderRoute(provider)) {
        throw const AdministrationFailure(
          'Provider selection could not be confirmed. Refresh to continue.',
        );
      }
    });
  }

  Future<void> _setup(String key) async {
    if (!await adminConfirm(
      context,
      'Install setup requirements?',
      'Hermes may download and install dependencies on the server. Other profiles can share those dependencies.',
      action: 'Run setup',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      final result = await _profile.write('POST', '$_base/post-setup', {
        'key': key,
      });
      if (!mounted) return;
      await adminPush(
        context,
        (context) => AdminActionPage(
          server: _profile.server,
          action: AdministrationAction.fromJson(result),
          title: 'Speech setup',
          scope: _profile.label,
        ),
      );
      if (mounted) await _read();
    });
  }

  Future<void> _secret(Map<String, dynamic> env) => _run(() async {
    if (!mounted) return;
    await adminPushProfile(
      context,
      _profile,
      (context, profile) => AdminSecretPage(
        profile: profile,
        name: env['key'] as String,

        isSet: env['is_set'] == true,
      ),
    );
    if (mounted) await _read();
  });

  Future<void> _pickVoice(List<ProfileVoiceChoice> choices) async {
    await _stop();
    if (!mounted) return;
    var search = '';
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final filtered = choices.where((v) => v.matches(search)).toList();
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _voices.settings?.provider == 'edge'
                        ? 'Suggested voices'
                        : 'Voices',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (choices.length > 8) ...[
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search voices',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => update(() => search = value),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: _voices.selected,
                      onChanged: (value) => Navigator.pop(context, value),
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching voices.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final voice = filtered[index];
                                return StudioRadioTile<String>(
                                  value: voice.id,
                                  title: Text(voice.name),
                                  subtitle: voice.detail.isEmpty
                                      ? null
                                      : Text(voice.detail),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted && value != null) _select(value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _voices.settings;
    final provider = _provider;
    final enabled = _confirmed && !_busy && _voices.fresh && !_voices.loading;
    final ready = provider?['status'] == 'ready';
    final rows = [..._voices.choices];
    for (final id in {settings?.voice, _voices.selected}) {
      if (id != null && id.isNotEmpty && !rows.any((v) => v.id == id)) {
        rows.insert(0, ProfileVoiceChoice(id, id));
      }
    }
    final selectedName = rows
        .where((v) => v.id == _voices.selected)
        .firstOrNull
        ?.name;
    final playing = _player.owner != null;
    final play = TextButton.icon(
      onPressed: playing || (enabled && ready && !_voices.saving)
          ? _play
          : null,
      icon: Icon(playing ? Icons.stop : Icons.play_arrow),
      label: Text(playing ? 'Stop' : 'Play'),
    );
    final voice = Semantics(
      button: true,
      child: InkWell(
        onTap: enabled && ready && settings?.key != null && rows.isNotEmpty
            ? () => _pickVoice(rows)
            : null,
        borderRadius: BorderRadius.circular(6),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Voice',
            enabled: enabled && ready,
            suffixIcon: const Icon(Icons.expand_more),
          ),
          child: Text(selectedName ?? 'Provider default'),
        ),
      ),
    );
    return AdminPage(
      title: 'Speech synthesis',
      scope: _profile.label,
      actions: [
        IconButton(
          tooltip: 'Refresh speech settings',
          onPressed: _busy || _voices.saving ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) AdminNotice.error(_error!, retry: _refresh),
          if (_voices.error != null)
            AdminNotice.error(_voices.error!, retry: _refresh),
          if (_providers.isNotEmpty) ...[
            StudioSelect<String>(
              label: 'Provider',
              value: provider?['name'] as String?,
              options: [
                for (final row in _providers)
                  (value: row['name'] as String, label: row['name'] as String),
              ],
              onChanged: _busy || _voices.saving ? null : _selectProvider,
            ),
            const SizedBox(height: 20),
          ] else if (!_busy && _error == null)
            const AdminNotice('No speech providers are available.'),
          if (provider != null && !ready) ...[
            AdminNotice(switch (provider['status']) {
              'needs_keys' => 'Add the provider credentials to use its voices.',
              'needs_auth' =>
                'Sign in to this provider on Hermes, then refresh.',
              'needs_setup' => 'Complete provider setup to use its voices.',
              _ => 'Provider readiness is unavailable. Refresh to check again.',
            }),
            ..._credentials(provider),
            if (provider['post_setup'] is String)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _setup(provider['post_setup'] as String),
                child: const Text('Setup requirements'),
              ),
          ],
          if (ready && settings != null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                if (MediaQuery.textScalerOf(context).scale(16) > 24) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      voice,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: play),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: voice),
                    const SizedBox(width: 8),
                    play,
                  ],
                );
              },
            ),
            if (_voices.saving)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Saving…'),
              ),
            if (_player.preparing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Preparing audio…'),
              ),
            if (_player.error != null) AdminNotice.error(_player.error!),
            if (_voices.catalogueError != null)
              AdminNotice.error(_voices.catalogueError!, retry: _refresh),
          ],
          if (provider != null) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Advanced'),
              tilePadding: EdgeInsets.zero,
              children: [
                if (ready && settings?.key != null)
                  Focus(
                    onFocusChange: (focused) {
                      if (!focused && enabled) _customVoice();
                    },
                    child: TextField(
                      controller: _custom,
                      enabled: enabled,
                      maxLength: 256,
                      decoration: const InputDecoration(labelText: 'Voice ID'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _customVoice(),
                    ),
                  ),
                if (ready) ..._credentials(provider),
                if (ready && provider['post_setup'] is String)
                  TextButton(
                    onPressed: _busy || _voices.saving
                        ? null
                        : () => _setup(provider['post_setup'] as String),
                    child: const Text('Setup requirements'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _credentials(Map<String, dynamic> provider) => [
    for (final env in administrationRows(provider['env_vars'] ?? []))
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${env['prompt'] ?? env['key']}'),
        subtitle: Text(env['is_set'] == true ? 'Configured' : 'Not configured'),
        trailing: const Icon(Icons.key_outlined),
        onTap: _busy || _voices.saving ? null : () => _secret(env),
      ),
  ];
}
