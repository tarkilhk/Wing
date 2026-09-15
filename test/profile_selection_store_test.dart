import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_selection_store.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProfileDiscovery discovery({
    String? current = 'client-work',
    String? active = 'default',
  }) => ProfileDiscovery(
    profiles: const [
      HermesProfile(name: 'default'),
      HermesProfile(name: 'client-work'),
      HermesProfile(name: 'android-qa'),
    ],
    currentName: current,
    activeName: active,
  );

  test('isolates selections by saved connection', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = ProfileSelectionStore(preferences);

    await store.write('prestige-lan', 'client-work');
    await store.write('remote-host', 'android-qa');

    expect(store.read('prestige-lan'), 'client-work');
    expect(store.read('remote-host'), 'android-qa');
  });

  test('uses restored, current, active, then first precedence', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = ProfileSelectionStore(preferences);

    await store.write('conn', 'android-qa');
    expect(store.resolveInitial('conn', discovery()).name, 'android-qa');

    await store.write('conn', 'profile-that-no-longer-exists');
    expect(store.resolveInitial('conn', discovery()).name, 'client-work');

    expect(
      store
          .resolveInitial(
            'other',
            discovery(current: 'missing', active: 'default'),
          )
          .name,
      'default',
    );
    expect(
      store
          .resolveInitial(
            'other',
            discovery(current: 'missing', active: 'also-missing'),
          )
          .name,
      'default',
    );
  });

  test('rejects invalid canonical values instead of persisting them', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = ProfileSelectionStore(preferences);

    expect(() => store.write('conn', '../default'), throwsArgumentError);
    expect(store.read('conn'), isNull);
  });
}
