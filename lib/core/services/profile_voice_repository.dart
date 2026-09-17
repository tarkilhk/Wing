import 'administration_repository.dart';
import 'hermes_voice.dart';

/// Stock Hermes exposes the engine in tts_provider, but persists managed
/// subscription selections as "nous". Engine identity is not route identity.
String? speechProviderRoute(Map<String, dynamic> row) =>
    row['requires_nous_auth'] == true ? 'nous' : row['tts_provider'] as String?;

class ProfileVoiceChoice {
  final String id;
  final String name;
  final String detail;
  const ProfileVoiceChoice(this.id, this.name, [this.detail = '']);
  bool matches(String query) =>
      '$id $name $detail'.toLowerCase().contains(query.trim().toLowerCase());
}

// Suggestions from vanilla Hermes Desktop's settings/constants.ts, not a live
// Edge catalogue. Unknown/current IDs remain visible and can be entered below.
const edgeVoiceSuggestions = [
  ProfileVoiceChoice('en-US-AriaNeural', 'Aria', 'English · United States'),
  ProfileVoiceChoice('en-US-JennyNeural', 'Jenny', 'English · United States'),
  ProfileVoiceChoice('en-US-AndrewNeural', 'Andrew', 'English · United States'),
  ProfileVoiceChoice('en-US-BrianNeural', 'Brian', 'English · United States'),
  ProfileVoiceChoice('en-US-GuyNeural', 'Guy', 'English · United States'),
  ProfileVoiceChoice('en-GB-SoniaNeural', 'Sonia', 'English · United Kingdom'),
];

class ProfileVoiceSettings {
  final String provider;
  final String? key;
  final String? voice;
  const ProfileVoiceSettings(this.provider, this.key, this.voice);
}

/// Uses only stock config, ElevenLabs catalogue and audio/speak APIs.
class ProfileVoiceRepository {
  final ProfileAdministration profile;
  ProfileVoiceRepository(this.profile);

  Future<ProfileVoiceSettings> load() async {
    final config = await profile.config();
    final schema = (await profile.read('config/schema'))['fields'];
    final provider = setting(config, 'tts.provider');
    if (provider is! String || provider.isEmpty || schema is! Map) {
      throw const FormatException('Missing speech settings');
    }
    // Nous uses OpenAI's voice configuration while retaining its managed route.
    final voiceProvider = provider == 'nous' ? 'openai' : provider;
    for (final suffix in ['voice', 'voice_id']) {
      final key = 'tts.$voiceProvider.$suffix';
      if (schema.containsKey(key)) {
        final value = setting(config, key);
        if (value != null && value is! String) {
          throw const FormatException('Invalid saved voice');
        }
        return ProfileVoiceSettings(provider, key, value as String?);
      }
    }
    return ProfileVoiceSettings(provider, null, null);
  }

  Future<List<ProfileVoiceChoice>> choices(String provider) async {
    if (provider == 'edge') return edgeVoiceSuggestions;
    if (provider != 'elevenlabs') return const [];
    final data = await profile.read('audio/elevenlabs/voices');
    if (data['available'] != true) {
      throw const AdministrationFailure(
        'ElevenLabs voices are unavailable. Check the provider settings.',
      );
    }
    final seen = <String>{};
    return administrationRows(data['voices']).map((row) {
      final id = row['voice_id'];
      final name = row['name'];
      final label = row['label'];
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          label is! String ||
          !seen.add(id)) {
        throw const FormatException('Invalid voice list');
      }
      return ProfileVoiceChoice(id, name, label == name ? '' : label);
    }).toList();
  }

  Future<void> verify(ProfileVoiceSettings expected) async {
    final config = await profile.config();
    if (setting(config, 'tts.provider') != expected.provider ||
        (expected.key != null &&
            setting(config, expected.key!) != expected.voice)) {
      throw const AdministrationFailure(
        'Voice settings changed elsewhere. Refresh to continue.',
      );
    }
  }

  Future<ProfileVoiceSettings> save(
    ProfileVoiceSettings expected,
    String voice,
  ) async {
    final key = expected.key;
    if (key == null || voice.trim().isEmpty || voice.length > 256) {
      throw const AdministrationFailure('Enter a valid voice ID.');
    }
    await verify(expected);
    await profile.saveSettings({key: voice});
    final saved = ProfileVoiceSettings(expected.provider, key, voice);
    await verify(saved);
    return saved;
  }

  HermesVoice speech(ProfileVoiceSettings expected) {
    var closed = false;
    return HermesVoice(
      profile: profile.name,
      closeClient: () => closed = true,
      request: (endpoint, body) async {
        profile.server.retain();
        try {
          if (closed) throw StateError('Playback stopped.');
          await verify(expected);
          if (closed) throw StateError('Playback stopped.');
          final result = await profile.server.request(
            'POST',
            Uri.parse(endpoint).path,
            {'profile': profile.name},
            body,
          );
          if (closed) throw StateError('Playback stopped.');
          // A concurrent settings edit must not play a result labelled as the
          // previous selection. The stock speech response has no voice ID.
          await verify(expected);
          return result;
        } on AdministrationFailure catch (failure) {
          // The shared player presents StateError messages as actionable text.
          throw StateError(failure.message);
        } finally {
          profile.server.release();
        }
      },
    );
  }
}
