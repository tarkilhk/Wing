import '../models/hermes_profile.dart';
import 'connection_manager.dart';

typedef ProfileApiGet = Future<Map<String, dynamic>> Function(String endpoint);

enum ProfilesCapability {
  supported,
  authenticationRequired,
  unsupported,
  unavailable,
  malformed,
}

class ProfileDiscovery {
  final List<HermesProfile> profiles;
  final String? currentName;
  final String? activeName;

  const ProfileDiscovery({
    required this.profiles,
    required this.currentName,
    required this.activeName,
  });

  HermesProfile? named(String? name) {
    if (name == null) return null;
    for (final profile in profiles) {
      if (profile.name == name) return profile;
    }
    return null;
  }

  HermesProfile get serverPreferred =>
      named(currentName) ?? named(activeName) ?? profiles.first;
}

class ProfilesProbeResult {
  final ProfilesCapability capability;
  final ProfileDiscovery? discovery;
  final String? message;

  const ProfilesProbeResult._(this.capability, {this.discovery, this.message});

  const ProfilesProbeResult.supported(ProfileDiscovery discovery)
    : this._(ProfilesCapability.supported, discovery: discovery);

  const ProfilesProbeResult.failure(
    ProfilesCapability capability,
    String message,
  ) : this._(capability, message: message);
}

/// Discovers profiles through the authenticated modern dashboard contract.
///
/// There is deliberately no legacy fallback here. An absent or unhealthy
/// profile endpoint is an explicit capability state, never permission to send
/// an unscoped request to the server's default profile.
class ProfilesRepository {
  final ProfileApiGet _get;
  final DashboardClient? _ownedClient;

  ProfilesRepository(ProfileApiGet get) : _get = get, _ownedClient = null;

  ProfilesRepository._owned(DashboardClient client)
    : _get = client.apiGet,
      _ownedClient = client;

  factory ProfilesRepository.forConnection(SavedConnection connection) {
    return ProfilesRepository._owned(
      DashboardClient(
        host: connection.host,
        port: connection.dashboardPort,
        useHttps: connection.useHttps,
        pathPrefix: connection.dashboardPrefix ?? '',
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
        dashboardOAuth: connection.dashboardOAuth,
        requiresOAuth: connection.isCloud,
        gatewayHeaders: connection.gatewayHeaders,
      ),
    );
  }

  Future<ProfileDiscovery> discover() async {
    final profilesPayload = await _get('profiles');
    final activePayload = await _get('profiles/active');
    final rawProfiles = profilesPayload['profiles'];
    if (rawProfiles is! List || rawProfiles.isEmpty) {
      throw const FormatException(
        'The server returned no valid Hermes profiles.',
      );
    }

    final profiles = <HermesProfile>[];
    final names = <String>{};
    for (final raw in rawProfiles) {
      if (raw is! Map) {
        throw const FormatException('The server returned an invalid profile.');
      }
      final profile = HermesProfile.fromJson(Map<String, dynamic>.from(raw));
      if (!names.add(profile.name)) {
        throw FormatException(
          'The server returned duplicate profile ${profile.name}.',
        );
      }
      profiles.add(profile);
    }

    String? optionalCanonicalName(String key) {
      final value = activePayload[key];
      if (value == null) return null;
      if (value is! String || !HermesProfile.isCanonicalName(value)) {
        throw FormatException('The server returned an invalid $key profile.');
      }
      return value;
    }

    return ProfileDiscovery(
      profiles: List.unmodifiable(profiles),
      currentName: optionalCanonicalName('current'),
      activeName: optionalCanonicalName('active'),
    );
  }

  Future<ProfilesProbeResult> probe() async {
    try {
      return ProfilesProbeResult.supported(await discover());
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return const ProfilesProbeResult.failure(
          ProfilesCapability.authenticationRequired,
          'Profile discovery needs dashboard authentication.',
        );
      }
      if (error.statusCode == 404 || error.statusCode == 405) {
        return const ProfilesProbeResult.failure(
          ProfilesCapability.unsupported,
          'This server does not expose the modern profile API.',
        );
      }
      return ProfilesProbeResult.failure(
        ProfilesCapability.unavailable,
        'Profile discovery failed with HTTP ${error.statusCode}.',
      );
    } on FormatException catch (error) {
      return ProfilesProbeResult.failure(
        ProfilesCapability.malformed,
        error.message,
      );
    } catch (_) {
      return const ProfilesProbeResult.failure(
        ProfilesCapability.unavailable,
        'Could not reach the profile API.',
      );
    }
  }

  void close() => _ownedClient?.close();
}

Future<ProfilesProbeResult> probeProfilesForConnection(
  SavedConnection connection,
) async {
  final repository = ProfilesRepository.forConnection(connection);
  try {
    return await repository.probe();
  } finally {
    repository.close();
  }
}
