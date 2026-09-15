import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profiles_repository.dart';

void main() {
  Map<String, dynamic> profilesPayload() => {
    'profiles': [
      {
        'name': 'default',
        'display_name': '',
        'is_default': true,
        'provider': 'openai-codex',
        'model': 'gpt-5.6-luna',
      },
      {
        'name': 'client-work',
        'display_name': 'Client Work',
        'is_default': false,
      },
    ],
  };

  test(
    'discovers profiles and honors the running server profile first',
    () async {
      final requested = <String>[];
      final repository = ProfilesRepository((endpoint) async {
        requested.add(endpoint);
        if (endpoint == 'profiles') return profilesPayload();
        return {'current': 'client-work', 'active': 'default'};
      });

      final result = await repository.probe();

      expect(result.capability, ProfilesCapability.supported);
      expect(requested, ['profiles', 'profiles/active']);
      expect(result.discovery!.serverPreferred.name, 'client-work');
      expect(result.discovery!.profiles.last.label, 'Client Work');
    },
  );

  test('classifies authentication failures without falling back', () async {
    final repository = ProfilesRepository((_) async {
      throw const DashboardHttpException(401, 'profiles');
    });

    final result = await repository.probe();

    expect(result.capability, ProfilesCapability.authenticationRequired);
    expect(result.discovery, isNull);
  });

  test('classifies an absent modern endpoint as unsupported', () async {
    final repository = ProfilesRepository((_) async {
      throw const DashboardHttpException(404, 'profiles');
    });

    final result = await repository.probe();

    expect(result.capability, ProfilesCapability.unsupported);
    expect(result.message, contains('modern profile API'));
  });

  test('fails closed on duplicate or malformed profile identities', () async {
    final payload = profilesPayload();
    (payload['profiles'] as List).add({
      'name': 'default',
      'display_name': 'Duplicate',
    });
    final repository = ProfilesRepository((endpoint) async {
      if (endpoint == 'profiles') return payload;
      return {'current': 'default', 'active': 'default'};
    });

    final result = await repository.probe();

    expect(result.capability, ProfilesCapability.malformed);
    expect(result.discovery, isNull);
  });
}
