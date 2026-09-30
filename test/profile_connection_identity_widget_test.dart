import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/profile_connection_identity.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;

void main() {
  // The production resolver is a singleton. These successive widget tests
  // exercise its key cache across two independently created FakeAsync zones.
  late String originalIdentity;

  testWidgets('singleton identity loads in the first widget lifecycle', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    originalIdentity = await ProfileConnectionIdentity().resolve(
      identityTestConnection(),
    );
    expect(originalIdentity, matches(RegExp(r'^[a-f0-9]{64}$')));
  });

  testWidgets('singleton identity resolves in a later widget lifecycle', (
    tester,
  ) async {
    expect(
      await ProfileConnectionIdentity().resolve(identityTestConnection()),
      originalIdentity,
    );
  });
}
