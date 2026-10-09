import 'dart:ui' as ui;

import '../../models/profile_session_key.dart';

/// Disposable viewport pixels for one Recents visit, without transcript owners.
/// Reads never capture, decode, load history or acquire execution authority.
final class ConversationCardSnapshots {
  ConversationCardSnapshots({this.byteLimit = 32 * 1024 * 1024});

  final int byteLimit;
  final _images =
      <ProfileSessionKey, ({ui.Image image, bool live, Object revision})>{};
  int _bytes = 0;
  int _reserved = 0;
  Set<ProfileSessionKey> _neighborhood = {};

  ui.Image? imageFor(ProfileSessionKey key) => _images[key]?.image;
  bool isLive(ProfileSessionKey key) => _images[key]?.live ?? false;
  Object? revisionFor(ProfileSessionKey key) => _images[key]?.revision;

  /// Includes readback in flight in the same memory budget as retained pixels.
  void reserve(int bytes) {
    _reserved += bytes;
    _evictToFit(0);
  }

  void release(int bytes) => _reserved -= bytes;
  void invalidate(ProfileSessionKey key) => _remove(key);

  void _evictToFit(int bytes) {
    while (_bytes + _reserved + bytes > byteLimit && _images.isNotEmpty) {
      final victim = _images.keys.firstWhere(
        (key) => !_neighborhood.contains(key),
        orElse: () => _images.keys.first,
      );
      _remove(victim);
    }
  }

  /// Takes ownership, including disposal when the image exceeds the budget.
  void record(
    ProfileSessionKey key,
    ui.Image image, {
    required bool live,
    required Object revision,
  }) {
    final bytes = image.width * image.height * 4;
    if (bytes + _reserved > byteLimit) {
      image.dispose();
      return;
    }
    _remove(key);
    _evictToFit(bytes);
    _images[key] = (image: image, live: live, revision: revision);
    _bytes += bytes;
  }

  void retain(Set<ProfileSessionKey> keys) {
    _neighborhood = Set.of(keys);
    // Both genuine and prepared images survive neighborhood changes. Byte
    // eviction favors the visible cards without undoing outward preparation.
    for (final key in keys) {
      final entry = _images.remove(key);
      if (entry != null) _images[key] = entry;
    }
  }

  void _remove(ProfileSessionKey key) {
    final entry = _images.remove(key);
    if (entry == null) return;
    _bytes -= entry.image.width * entry.image.height * 4;
    entry.image.dispose();
  }

  void clear() {
    _neighborhood = {};
    for (final key in _images.keys.toList()) {
      _remove(key);
    }
  }
}
