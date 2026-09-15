import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/connection_setup_probe.dart';
import 'package:wing/core/services/profiles_repository.dart';

import 'support/connection_probe_fixture.dart';

void main() {
  final candidate = SavedConnection(
    id: 'test',
    label: 'Home',
    host: 'hermes.home',
    port: 9119,
    apiKey: '',
  );

  test(
    'verifies each real capability and closes the provisional resources',
    () async {
      final fixture = ConnectionProbeFixture();
      final probe = ConnectionSetupProbe(createProbe: (_) => fixture);
      addTearDown(probe.dispose);
      await probe.check(candidate);
      expect(probe.verified, isTrue);
      expect(fixture.calls, ConnectionCheck.values);
      expect(fixture.connectedProfile?.name, 'work');
      expect(fixture.closed, isTrue);
    },
  );

  for (final stage in ConnectionCheck.values) {
    test(
      'failure at ${stage.name} preserves prior success and redacts exceptions',
      () async {
        final fixture = ConnectionProbeFixture()..failAt = stage;
        final probe = ConnectionSetupProbe(createProbe: (_) => fixture);
        addTearDown(probe.dispose);
        await probe.check(candidate);
        expect(probe.verified, isFalse);
        expect(probe.failedStage, stage);
        expect(probe.error, isNot(contains('private-server-detail')));
        expect(fixture.calls.length, stage.index + 1);
        for (final prior in ConnectionCheck.values.take(stage.index)) {
          expect(probe.statuses[prior], ConnectionCheckStatus.available);
        }
        expect(fixture.closed, isTrue);
      },
    );
  }

  test(
    'a cancelled discovery cannot advance after a replacement check',
    () async {
      final first = ConnectionProbeFixture()
        ..discoveryGate = Completer<ProfileDiscovery>();
      final second = ConnectionProbeFixture();
      var calls = 0;
      final probe = ConnectionSetupProbe(
        createProbe: (_) => calls++ == 0 ? first : second,
      );
      addTearDown(probe.dispose);
      final old = probe.check(candidate);
      probe.cancel();
      expect(first.closed, isTrue);
      await probe.check(candidate);
      first.discoveryGate!.complete(connectionDiscovery);
      await old;
      expect(first.calls, [ConnectionCheck.profiles]);
      expect(probe.verified, isTrue);
      expect(second.calls, ConnectionCheck.values);
    },
  );

  test(
    'cancel while opening chat prevents history and late verification',
    () async {
      final fixture = ConnectionProbeFixture()..chatGate = Completer<void>();
      final probe = ConnectionSetupProbe(createProbe: (_) => fixture);
      addTearDown(probe.dispose);
      final checking = probe.check(candidate);
      await Future<void>.delayed(Duration.zero);
      probe.cancel();
      fixture.chatGate!.complete();
      await checking;
      expect(fixture.closed, isTrue);
      expect(fixture.calls, [ConnectionCheck.profiles, ConnectionCheck.chat]);
      expect(probe.verified, isFalse);
    },
  );

  test('a stage deadline closes resources and ignores a late result', () async {
    final fixture = ConnectionProbeFixture()
      ..discoveryGate = Completer<ProfileDiscovery>();
    final probe = ConnectionSetupProbe(
      createProbe: (_) => fixture,
      deadline: Duration.zero,
    );
    addTearDown(probe.dispose);
    await probe.check(candidate);
    expect(probe.error, contains('timed out'));
    expect(fixture.closed, isTrue);
    fixture.discoveryGate!.complete(connectionDiscovery);
    await Future<void>.delayed(Duration.zero);
    expect(probe.verified, isFalse);
  });

  test('typed sign-in and redirect errors have targeted recovery', () async {
    for (final (code, endpoint, message) in [
      (401, 'auth/password-login', 'rejected this username or password'),
      (403, 'profiles', 'Access was denied'),
      (302, 'profiles', 'redirects'),
      (404, 'profiles', 'profile access Wing needs'),
    ]) {
      final fixture = ConnectionProbeFixture()
        ..failAt = ConnectionCheck.profiles
        ..failure = DashboardHttpException(code, endpoint);
      final probe = ConnectionSetupProbe(createProbe: (_) => fixture);
      await probe.check(candidate);
      expect(probe.httpStatus, code);
      expect(probe.error, contains(message));
      probe.dispose();
    }
  });
}
