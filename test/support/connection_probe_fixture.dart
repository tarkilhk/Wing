import 'dart:async';

import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_setup_probe.dart';
import 'package:wing/core/services/profiles_repository.dart';

const connectionDiscovery = ProfileDiscovery(
  profiles: [HermesProfile(name: 'work', displayName: 'My agent')],
  currentName: 'work',
  activeName: 'work',
);

class ConnectionProbeFixture implements ConnectionProbe {
  Completer<ProfileDiscovery>? discoveryGate;
  Completer<void>? chatGate;
  Object? failure;
  ConnectionCheck? failAt;
  final calls = <ConnectionCheck>[];
  bool closed = false;
  HermesProfile? connectedProfile;

  void _call(ConnectionCheck stage) {
    calls.add(stage);
    if (stage == failAt) throw failure ?? StateError('private-server-detail');
  }

  @override
  Future<ProfileDiscovery> discover() async {
    _call(ConnectionCheck.profiles);
    return discoveryGate?.future ?? connectionDiscovery;
  }

  @override
  Future<void> connect(HermesProfile profile) async {
    _call(ConnectionCheck.chat);
    connectedProfile = profile;
    await chatGate?.future;
  }

  @override
  Future<void> history() async => _call(ConnectionCheck.history);

  @override
  void close() => closed = true;
}
