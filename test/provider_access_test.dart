import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/provider_access.dart';

void main() {
  final now = DateTime.utc(2026, 9, 14);
  ProviderAccess access(Map<String, dynamic> status, {bool external = false}) =>
      ProviderAccess({
        'status': status,
        'flow': external ? 'external' : 'device_code',
      }, now: now);

  test(
    'expiry overrides a positive login snapshot without claiming renewal failed',
    () {
      final value = access({
        'logged_in': true,
        'expires_at': '2026-09-13T00:00:00Z',
        'has_refresh_token': true,
      });
      expect(value.state, ProviderAccessState.expired);
      expect(value.detail, contains('has not been checked'));
      expect(value.signInLabel, 'Sign in again');
      expect(value.needsAttention, isTrue);
    },
  );

  test(
    'seconds, milliseconds and zoned ISO timestamps describe the same expiry',
    () {
      final milliseconds = now.millisecondsSinceEpoch;
      for (final value in [
        milliseconds,
        milliseconds / 1000,
        '$milliseconds',
        '2026-09-14T08:00:00+08:00',
      ]) {
        expect(providerStatusDate(value), now);
        expect(
          access({'logged_in': true, 'expires_at': value}).state,
          ProviderAccessState.expired,
        );
      }
      for (final value in [
        null,
        '',
        'invalid',
        '2026-09-14T00:00:00',
        double.infinity,
        -1,
        1e30,
      ]) {
        expect(providerStatusDate(value), isNull);
      }
    },
  );

  test(
    'missing metadata and external credentials never become a false signed-out state',
    () {
      expect(access({}).state, ProviderAccessState.unknown);
      expect(
        access({'logged_in': false, 'error': 'failed'}).state,
        ProviderAccessState.unknown,
      );
      expect(
        access({'logged_in': false}, external: true).state,
        ProviderAccessState.external,
      );
      expect(access({'logged_in': false}).state, ProviderAccessState.signedOut);
      final connected = access({'logged_in': true, 'expires_at': null});
      expect(connected.state, ProviderAccessState.connected);
      expect(connected.expiresAt, isNull);
    },
  );
}
