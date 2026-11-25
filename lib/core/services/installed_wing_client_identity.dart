import 'package:package_info_plus/package_info_plus.dart';

import '../models/wing_client_identity.dart';

typedef WingClientIdentityLoader = Future<WingClientIdentity> Function();

/// Production identity comes from this installation, with no guessed version.
Future<WingClientIdentity> loadInstalledWingClientIdentity() async =>
    WingClientIdentity(version: (await PackageInfo.fromPlatform()).version);
