import 'package:flutter/foundation.dart';

/// Frozen stock member destination. Connection labels never identify a peer.
@immutable
final class BotGroupTarget {
  const BotGroupTarget.local(this.profile)
    : installationId = null,
      peerId = null,
      capabilityDigest = null;
  const BotGroupTarget.peer({
    required this.profile,
    required this.installationId,
    required this.peerId,
    required this.capabilityDigest,
  });
  final String profile;
  final String? installationId, peerId, capabilityDigest;
  bool get isPeer => installationId != null;
  factory BotGroupTarget.fromJson(Map<String, dynamic> value) {
    final profile = peerText(value['profile']);
    if (value['kind'] == 'local' && value.length == 2) {
      return BotGroupTarget.local(profile);
    }
    if (value['kind'] != 'peer' || value.length != 5) {
      throw const FormatException('Invalid group target');
    }
    final digest = peerText(value['capability_digest']);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid peer catalog digest');
    }
    return BotGroupTarget.peer(
      profile: profile,
      installationId: peerText(value['installation_id']),
      peerId: peerText(value['peer_id']),
      capabilityDigest: digest,
    );
  }
  Map<String, dynamic> toJson() => {
    'kind': isPeer ? 'peer' : 'local',
    'profile': profile,
    if (isPeer) ...{
      'installation_id': installationId,
      'peer_id': peerId,
      'capability_digest': capabilityDigest,
    },
  };
  @override
  bool operator ==(Object other) =>
      other is BotGroupTarget &&
      profile == other.profile &&
      installationId == other.installationId &&
      peerId == other.peerId &&
      capabilityDigest == other.capabilityDigest;
  @override
  int get hashCode =>
      Object.hash(profile, installationId, peerId, capabilityDigest);
}

/// One profile's current stock capabilities, including caller-specific seating.
@immutable
final class BotGroupCapabilities {
  BotGroupCapabilities.fromJson(Map<String, dynamic> value, this.profile)
    : gateway = peerText(value['authority_gateway_id']),
      methods = _strings(value['methods']),
      features = _strings(value['features']),
      seatableProfiles = _strings(value['seatable_profiles']),
      driver = _boolean(value['driver']),
      persistent = _boolean(value['persistent_process']),
      roomLink = _freezeMap(value['room_link']);
  final String profile, gateway;
  final Set<String> methods, features, seatableProfiles;
  final bool driver, persistent;
  final Map<String, dynamic> roomLink;
  bool get canCreate =>
      driver && persistent && methods.contains('groups.create');
  bool get canRegister => canCreate && methods.contains('groups.peer.register');
  bool get renewal => features.contains('peer_renewal_horizon');
  BotGroupTarget? get peerTarget => peerProblem == null
      ? BotGroupTarget.peer(
          profile: profile,
          installationId: gateway,
          peerId: gateway,
          capabilityDigest: peerText(
            (roomLink['catalog'] as Map)['catalog_digest'],
          ),
        )
      : null;
  String? get peerProblem {
    if (!methods.contains('groups.peer.invite')) {
      return 'peer_invite_unsupported';
    }
    if (roomLink['enabled'] != true) {
      return roomLink['reason'] is String
          ? roomLink['reason'] as String
          : 'room_link_unavailable';
    }
    final catalog = roomLink['catalog'];
    if (catalog is! Map ||
        catalog['installation_id'] != gateway ||
        catalog['catalog_digest'] is! String ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(catalog['catalog_digest'] as String)) {
      return 'peer_target_mismatch';
    }
    if (catalog['protocol_versions'] is! List ||
        !(catalog['protocol_versions'] as List).contains(2) ||
        catalog['link_modes'] is! List ||
        !(catalog['link_modes'] as List).contains('direct')) {
      return 'peer_target_unsupported';
    }
    if (catalog['persistent_process'] != true) {
      return 'persistent_process_required';
    }
    if (catalog['text'] != true || catalog['attachments'] != false) {
      return 'text_only_required';
    }
    final policy = catalog['execution_policy'];
    if (policy is! Map || policy['target_profile'] != profile) {
      return 'peer_target_mismatch';
    }
    final endpoint = catalog['endpoint'];
    if (endpoint is! Map ||
        endpoint['available'] != true ||
        endpoint['url'] is! String ||
        (endpoint['url'] as String).trim().isEmpty) {
      return 'endpoint_required';
    }
    return null;
  }
}

/// Transient invitation, confined to one operation; never persisted or logged.
final class BotGroupPeerInvitation {
  BotGroupPeerInvitation.fromJson(Map<String, dynamic> value)
    : grant = peerText(value['grant']),
      profile = peerText(value['target_profile']),
      catalog = _freezeMap(value['catalog']),
      endpoint = _freezeMap(value['endpoint']);
  final String grant, profile;
  final Map<String, dynamic> catalog, endpoint;
  String get url => peerText(endpoint['url']);
  bool matches(BotGroupTarget target) =>
      target.isPeer &&
      profile == target.profile &&
      catalog['installation_id'] == target.installationId &&
      catalog['catalog_digest'] == target.capabilityDigest &&
      catalog['endpoint'] is Map &&
      (catalog['endpoint'] as Map)['url'] == endpoint['url'] &&
      catalog['execution_policy'] is Map &&
      (catalog['execution_policy'] as Map)['target_profile'] == target.profile;
}

final class BotGroupPeerFailure implements Exception {
  const BotGroupPeerFailure(this.reason);
  final String reason;
  String get message => switch (reason) {
    'peer_connection_missing' =>
      'Connect to this bot’s saved instance, then retry.',
    'peer_gateway_changed' || 'peer_target_mismatch' =>
      'This bot’s instance or setup changed. Its saved group target cannot be replaced.',
    'registration_unconfirmed' =>
      'Joining could not be confirmed. Retry to check this member.',
    'room_ended' => 'This group ended or changed owner. Reopen Groups.',
    'api_server_required' => 'Enable the API server on this bot’s instance.',
    'durable_run_storage_required' =>
      'Enable durable run storage on this bot’s instance.',
    'gateway_roomlink_secret_unavailable' =>
      'Configure RoomLink on this bot’s instance.',
    'execution_policy_unsupported' =>
      'Enable approval prompts on this bot’s instance.',
    'endpoint_required' =>
      'Configure an available RoomLink address on this bot’s instance.',
    'persistent_process_required' => 'Run this bot’s gateway persistently.',
    _ =>
      'This bot could not join. Check its instance’s RoomLink setup and retry.',
  };
  @override
  String toString() => message;
}

String peerText(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Missing peer identity');
  }
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Invalid group capability');
  return value;
}

Set<String> _strings(Object? value) {
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    throw const FormatException('Invalid group capability list');
  }
  return Set.unmodifiable(value.cast<String>());
}

Map<String, dynamic> _freezeMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid peer object');
  }
  Object? freeze(Object? item) => switch (item) {
    Map() => _freezeMap(item),
    List() => List.unmodifiable(item.map(freeze)),
    null || String() || bool() || num() => item,
    _ => throw const FormatException('Invalid peer value'),
  };
  return Map.unmodifiable(
    value.map((key, item) => MapEntry(key as String, freeze(item))),
  );
}
