import 'dart:ui' as ui;

import '../../models/profile_session_key.dart';

/// Disposable viewport pixels for one Recents visit, without transcript owners.
/// Reads never capture, decode, load history or acquire execution authority.
final class ConversationCardSnapshots {
  ConversationCardSnapshots({this.byteLimit = 12 * 1024 * 1024});

  final int byteLimit;
  final _images = <ProfileSessionKey, ({ui.Image image, bool live})>{};
  int _bytes = 0;

  ui.Image? imageFor(ProfileSessionKey key) => _images[key]?.image;
  bool isLive(ProfileSessionKey key) => _images[key]?.live ?? false;

  /// Takes ownership, including disposal when the image exceeds the budget.
  void record(ProfileSessionKey key, ui.Image image, {required bool live}) {
    final bytes = image.width * image.height * 4;
    if (bytes > byteLimit) {
      image.dispose();
      return;
    }
    _remove(key);
    while (_bytes + bytes > byteLimit && _images.isNotEmpty) {
      _remove(_images.keys.first);
    }
    _images[key] = (image: image, live: live);
    _bytes += bytes;
  }

  void retain(Set<ProfileSessionKey> keys) {
    for (final key in _images.keys.toList()) {
      if (!keys.contains(key)) _remove(key);
    }
  }

  void _remove(ProfileSessionKey key) {
    final entry = _images.remove(key);
    if (entry == null) return;
    _bytes -= entry.image.width * entry.image.height * 4;
    entry.image.dispose();
  }

  void clear() {
    for (final key in _images.keys.toList()) {
      _remove(key);
    }
  }
}
