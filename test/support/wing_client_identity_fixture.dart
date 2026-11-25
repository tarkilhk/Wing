import 'dart:io';

import 'package:wing/core/models/wing_client_identity.dart';

final testWingClientIdentity = WingClientIdentity(version: '1.2.3');

Future<WingClientIdentity> loadTestWingClientIdentity() async =>
    testWingClientIdentity;

/// Live host probes represent the candidate build without a platform plugin.
Future<WingClientIdentity> loadCandidateWingClientIdentity() async {
  final pubspec = await File('pubspec.yaml').readAsString();
  final version = RegExp(
    r'^version: ([^+\s]+)',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (version == null) throw StateError('Candidate version is missing');
  return WingClientIdentity(version: version);
}
