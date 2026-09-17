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
import 'admin_widgets.dart';

class AdminProfileVoicePage extends StatefulWidget {
  final ProfileAdministration profile;
  final VoiceDevice? device;
  const AdminProfileVoicePage({super.key, required this.profile, this.device});
  @override
  State<AdminProfileVoicePage> createState() => _AdminProfileVoicePageState();
}

class _AdminProfileVoicePageState extends State<AdminProfileVoicePage>
    with WidgetsBindingObserver {
  late final _profile = widget.profile;
  late final _voices = ProfileVoiceController(ProfileVoiceRepository(_profile));
  late final _player = VoiceOutputController(
    widget.device ?? AndroidVoice.instance,
  );
  final _custom = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _profile.server.retain();
    _voices.addListener(_changed);
    _player.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_voices.load());
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

  Future<void> _refresh() async {
    await _stop();
    if (mounted) await _voices.load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _voices.settings;
    final enabled = _voices.fresh && !_voices.loading;
    final rows = [..._voices.choices];
    for (final id in {settings?.voice, _voices.selected}) {
      if (id != null && id.isNotEmpty && !rows.any((v) => v.id == id)) {
        rows.insert(0, ProfileVoiceChoice(id, id));
      }
    }
    final filtered = rows.where((v) => v.matches(_search)).toList();
    final selectedName = rows
        .where((v) => v.id == _voices.selected)
        .firstOrNull
        ?.name;
    final playing = _player.owner != null;
    return AdminPage(
      title: 'Profile voice',
      scope: _profile.label,
      actions: [
        IconButton(
          tooltip: 'Refresh voices',
          onPressed: _voices.loading || _voices.saving ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        children: [
          if (_voices.loading || _voices.saving)
            const LinearProgressIndicator(),
          Expanded(
            child: RadioGroup<String>(
              groupValue: _voices.selected,
              onChanged: _select,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_voices.error != null)
                          AdminNotice.error(_voices.error!, retry: _refresh),
                        if (settings != null) ...[
                          Text(switch (settings.provider) {
                            'edge' => 'Edge',
                            'elevenlabs' => 'ElevenLabs',
                            _ => settings.provider,
                          }, style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedName ?? 'Current voice',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _voices.saving
                                        ? 'Saving…'
                                        : !_voices.fresh
                                        ? 'Refresh required'
                                        : 'Saved',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(voiceSampleText),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed:
                                        playing || (enabled && !_voices.saving)
                                        ? _play
                                        : null,
                                    icon: Icon(
                                      playing ? Icons.stop : Icons.play_arrow,
                                    ),
                                    label: Text(playing ? 'Stop' : 'Play'),
                                  ),
                                  if (_player.preparing)
                                    const Text('Preparing audio…'),
                                ],
                              ),
                            ),
                          ),
                          if (_player.error != null)
                            AdminNotice.error(_player.error!),
                          if (_voices.catalogueError != null)
                            AdminNotice.error(
                              _voices.catalogueError!,
                              retry: _refresh,
                            ),
                          const SizedBox(height: 20),
                          if (settings.key == null)
                            const AdminNotice(
                              'Voice selection is unavailable for this provider.',
                            )
                          else ...[
                            Text(
                              settings.provider == 'edge'
                                  ? 'Suggested voices'
                                  : 'Voices',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'Search voices',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (value) =>
                                  setState(() => _search = value),
                            ),
                            const SizedBox(height: 12),
                            if (filtered.isEmpty)
                              const AdminNotice('No matching voices.'),
                          ],
                        ],
                      ],
                    );
                  }
                  if (index == filtered.length + 1) {
                    if (settings?.key == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Advanced'),
                        children: [
                          Focus(
                            onFocusChange: (focused) {
                              if (!focused) _customVoice();
                            },
                            child: TextField(
                              controller: _custom,
                              enabled: enabled,
                              maxLength: 256,
                              decoration: const InputDecoration(
                                labelText: 'Voice ID',
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _customVoice(),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final voice = filtered[index - 1];
                  return StudioRadioTile<String>(
                    value: voice.id,
                    enabled: enabled && settings?.key != null,
                    title: Text(voice.name),
                    subtitle: voice.detail.isEmpty ? null : Text(voice.detail),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
