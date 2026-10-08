import 'package:flutter/material.dart';
import '../../controllers/profile_voice_controller.dart';
import '../../services/administration_repository.dart';
import '../../services/android_voice.dart';
import '../../services/profile_voice_repository.dart';
import '../../services/profile_tool_setup_session.dart';
import '../../services/provider_inventory_session.dart';
import 'admin_voice_page.dart';
import 'admin_speech_synthesis_page.dart';
import 'admin_provider_credentials.dart';
import 'admin_operations_page.dart';
import 'admin_tool_setup_page.dart';
import 'admin_settings_page.dart';
import 'admin_widgets.dart';

/// Actual route composition. Every picker replacement gets the selected profile;
/// typed Voice views never receive a raw transport or an earlier profile's fields.
AdminSpeechSynthesisPage profileSpeechSynthesisPage(
  ProfileAdministration profile, {
  required VoiceDevice device,
}) => AdminSpeechSynthesisPage(
  createSession: () =>
      ProfileVoiceController(ProfileVoiceRepository(profile), device: device),
  onCredential: (context, field) async {
    await adminPushProfile(
      context,
      profile,
      (context, selected) =>
          _ProfileVoiceCredential(profile: selected, name: field.key),
    );
  },
  onResult: (context, operation) async {
    await adminPush(
      context,
      (_) => AdminActionPage(
        operation: operation,
        title: 'Speech setup',
        scope: profile.label,
      ),
    );
  },
);

AdminVoicePage profileVoicePage(
  ProfileAdministration profile, {
  required VoiceDevice device,
}) => AdminVoicePage(
  createSession: () =>
      ProfileVoiceController(ProfileVoiceRepository(profile), device: device),
  onRecognition: (context) async {
    await adminPushProfile(
      context,
      profile,
      (context, selected) => AdminToolSetupPage(
        createSession: () => ProfileToolSetupSession(selected, tool: 'stt'),
        onCredential: (context, field) async {
          await adminPushProfile(
            context,
            selected,
            (context, target) =>
                _ProfileVoiceCredential(profile: target, name: field.key),
          );
        },
      ),
    );
  },
  onSynthesis: (context) async {
    await adminPushProfile(
      context,
      profile,
      (context, selected) =>
          profileSpeechSynthesisPage(selected, device: device),
    );
  },
  onDefaults: (context) async {
    await adminPushProfile(
      context,
      profile,
      (context, selected) =>
          _ProfileSpeechDefaults(profile: selected, device: device),
    );
  },
);

/// Provides this route's current field catalog to the existing settings editor.
/// The editor remains the sole settings-draft/write owner.
class _ProfileSpeechDefaults extends StatefulWidget {
  const _ProfileSpeechDefaults({required this.profile, required this.device});
  final ProfileAdministration profile;
  final VoiceDevice device;
  @override
  State<_ProfileSpeechDefaults> createState() => _ProfileSpeechDefaultsState();
}

class _ProfileSpeechDefaultsState extends State<_ProfileSpeechDefaults> {
  late final _session = ProfileVoiceController(
    ProfileVoiceRepository(widget.profile),
    device: widget.device,
  );
  @override
  void initState() {
    super.initState();
    _session.loadDefaults();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      final state = _session.state;
      if (!state.fresh) {
        return AdminPage(
          title: 'Speech defaults',
          scope: _session.scopeLabel,
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : AdminNotice.error(
                  state.error ?? 'Speech settings are unavailable.',
                  retry: _session.loadDefaults,
                ),
        );
      }
      return AdminSettingsPage(
        profile: widget.profile,
        title: 'Speech defaults',
        fields: state.defaults,
      );
    },
  );
}

/// Reuses the existing metadata owner so a picker replacement never borrows
/// another profile's credential baseline. The existing editor owns the draft.
class _ProfileVoiceCredential extends StatefulWidget {
  const _ProfileVoiceCredential({required this.profile, required this.name});
  final ProfileAdministration profile;
  final String name;
  @override
  State<_ProfileVoiceCredential> createState() =>
      _ProfileVoiceCredentialState();
}

class _ProfileVoiceCredentialState extends State<_ProfileVoiceCredential> {
  late final _inventory = ProviderInventorySession(
    widget.profile,
    scope: ProviderInventoryScope.catalog,
  );
  @override
  void initState() {
    super.initState();
    _inventory.refresh();
  }

  @override
  void dispose() {
    _inventory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _inventory,
    builder: (context, _) {
      final field = _inventory.observation?.keys
          .where((field) => field.key == widget.name)
          .firstOrNull;
      if (_inventory.loading ||
          _inventory.error != null ||
          field == null ||
          !field.editable) {
        return AdminPage(
          title: widget.name,
          scope: widget.profile.label,
          child: _inventory.loading
              ? const Center(child: CircularProgressIndicator())
              : AdminNotice.error(
                  _inventory.error ?? 'This credential is unavailable.',
                  retry: _inventory.refresh,
                ),
        );
      }
      return AdminSecretPage(
        profile: widget.profile,
        name: field.key,
        isSet: field.isSet,
      );
    },
  );
}
