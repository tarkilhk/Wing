import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../services/android_voice.dart';
import '../../services/profile_capabilities_session.dart';
import '../../services/profile_identity_edit_session.dart';
import '../../services/profile_plugins_session.dart';
import '../../services/profile_skills_session.dart';
import '../../services/profile_tool_setup_session.dart';
import '../../widgets/server_connection_label.dart';
import '../../widgets/wing_app_bar.dart';
import '../profile_capabilities_screen.dart';
import '../administration/admin_defaults_page.dart';
import '../administration/admin_identity_page.dart';
import '../administration/admin_plugins_page.dart';
import '../administration/admin_provider_credentials.dart';
import '../administration/admin_providers_page.dart';
import '../administration/admin_skills_page.dart';
import '../administration/admin_tool_setup_page.dart';
import '../administration/admin_voice_routes.dart';

/// Settings handoff to Wing's established captured-profile editors. No copied
/// account/model/settings form and no mutation of the selected chat's profile.
class BotSettingsScreen extends StatelessWidget {
  const BotSettingsScreen({super.key, required this.profile});
  final ProfileAdministration profile;
  Widget _scoped(Widget child) {
    final status = profile.gateway.connectionStatus;
    return status == null
        ? child
        : ServerConnectionScope(status: status, child: child);
  }

  Future<void> _push(BuildContext context, Widget child) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _scoped(child)),
    );
  }

  Widget _capabilities(BuildContext context) => ProfileCapabilitiesScreen(
    createSession: () => ProfileCapabilitiesSession(profile.gateway),
    connectionLabel: profile.server.connectionLabel,
    onToolSetup: (name) => _push(
      context,
      name == 'tts'
          ? profileSpeechSynthesisPage(profile, device: AndroidVoice.instance)
          : AdminToolSetupPage(
              createSession: () => ProfileToolSetupSession(profile, tool: name),
              onCredential: (context, field) => _push(
                context,
                AdminSecretPage(
                  profile: profile,
                  name: field.key,
                  isSet: field.isSet,
                ),
              ),
            ),
    ),
    onLibrary: () => _push(
      context,
      AdminSkillLibraryPage(
        createSession: () => ProfileSkillsSession.library(profile),
      ),
    ),
    onHub: () => _push(
      context,
      AdminSkillHubPage(createSession: () => ProfileSkillsSession.hub(profile)),
    ),
    onPlugins: () => _push(
      context,
      AdminPluginsPage(createSession: () => ProfilePluginsSession(profile)),
    ),
  );
  @override
  Widget build(BuildContext context) => _scoped(
    Scaffold(
      appBar: WingAppBar(
        context: context,
        title: const Text('Profile settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(profile.label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          for (final (title, subtitle, icon, page)
              in <(String, String, IconData, Widget Function())>[
                (
                  'Role & instructions',
                  'Description and SOUL.md',
                  Icons.badge_outlined,
                  () => AdminIdentityPage(
                    createSession: () => ProfileIdentityEditSession(profile),
                  ),
                ),
                (
                  'Model & defaults',
                  'Main model and helper models',
                  Icons.tune_outlined,
                  () => AdminDefaultsPage(profile: profile),
                ),
                (
                  'Accounts & credentials',
                  'Provider access for this bot',
                  Icons.key_outlined,
                  () => AdminProvidersPage(profile: profile),
                ),
                (
                  'Skills & tools',
                  'Capabilities, library, hub and plugins',
                  Icons.extension_outlined,
                  () => _capabilities(context),
                ),
              ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, page()),
            ),
        ],
      ),
    ),
  );
}
