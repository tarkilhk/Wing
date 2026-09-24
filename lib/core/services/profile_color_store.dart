import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/profile_colors.dart';

/// Device-only profile colors, scoped to the exact saved connection identity.
class ProfileColorStore {
  ProfileColorStore(this.preferences, this.connectionIdentity);

  final SharedPreferences preferences;
  final String connectionIdentity;

  String get _prefix =>
      'profile_color_v1_${sha256.convert(utf8.encode(connectionIdentity))}_';

  int? read(String profileName) {
    final index = preferences.get('$_prefix$profileName');
    if (index is! int || index < 0 || index >= desktopProfileSwatches.length) {
      return null;
    }
    return index;
  }

  Future<bool> write(String profileName, int? index) {
    if (index != null &&
        (index < 0 || index >= desktopProfileSwatches.length)) {
      throw RangeError.index(index, desktopProfileSwatches);
    }
    final key = '$_prefix$profileName';
    return index == null
        ? preferences.remove(key)
        : preferences.setInt(key, index);
  }
}
