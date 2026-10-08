/// Only the current stock configuration statuses, not runtime handler liveness.
enum ProfilePluginStatus {
  enabled('enabled'),
  disabled('disabled'),
  notEnabled('not enabled');

  const ProfilePluginStatus(this.label);
  final String label;
}

final class ProfilePlugin {
  const ProfilePlugin({
    required this.key,
    required this.name,
    required this.source,
    required this.description,
    required this.status,
  });
  final String key, name, source, description;
  final ProfilePluginStatus status;
  bool get enabled => status == ProfilePluginStatus.enabled;
  bool sameIdentity(ProfilePlugin other) =>
      key == other.key && name == other.name && source == other.source;
  static ProfilePlugin decode(Object? value) {
    if (value is! Map ||
        value['key'] is! String ||
        (value['key'] as String).isEmpty ||
        value['name'] is! String ||
        (value['name'] as String).isEmpty ||
        value['source'] is! String ||
        value['description'] is! String) {
      throw const FormatException('Invalid plugin inventory');
    }
    final status = ProfilePluginStatus.values
        .where((status) => status.label == value['status'])
        .firstOrNull;
    if (status == null) {
      throw const FormatException('Invalid plugin status');
    }
    return ProfilePlugin(
      key: value['key'] as String,
      name: value['name'] as String,
      source: value['source'] as String,
      description: value['description'] as String,
      status: status,
    );
  }

  static List<ProfilePlugin> inventory(Map<String, dynamic> response) {
    final values = response['plugins'];
    if (values is! List) {
      throw const FormatException('Invalid plugin inventory');
    }
    final rows = values.map(decode).toList();
    if (rows.map((row) => row.key).toSet().length != rows.length) {
      throw const FormatException('Duplicate plugin identity');
    }
    return List.unmodifiable(rows);
  }
}

final class ProfilePluginAcknowledgement {
  const ProfilePluginAcknowledgement({
    required this.key,
    required this.enabled,
    required this.restartRequired,
  });
  final String key;
  final bool enabled, restartRequired;
  static ProfilePluginAcknowledgement decode(
    Map<String, dynamic> response,
    String key,
    bool enabled,
  ) {
    if (response['ok'] != true ||
        response['name'] != key ||
        response['unchanged'] is! bool ||
        response['restart_required'] is! bool ||
        response['gateway_reloaded'] is! bool) {
      throw const FormatException('Plugin change was not acknowledged');
    }
    return ProfilePluginAcknowledgement(
      key: key,
      enabled: enabled,
      restartRequired: response['restart_required'] as bool,
    );
  }
}

enum ProfilePluginsPhase { idle, loading, saving }

final class ProfilePluginsState {
  ProfilePluginsState({
    required Iterable<ProfilePlugin> rows,
    required this.phase,
    required this.verified,
    required this.error,
    required this.retryable,
    required this.acknowledgement,
  }) : rows = List.unmodifiable(rows);
  final List<ProfilePlugin> rows;
  final ProfilePluginsPhase phase;
  final bool verified, retryable;
  final String? error;
  final ProfilePluginAcknowledgement? acknowledgement;
  bool get busy => phase != ProfilePluginsPhase.idle;
  bool get canToggle => verified && !busy;
  bool get canRefresh => !busy;
}
