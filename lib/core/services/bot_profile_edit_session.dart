import 'package:flutter/foundation.dart';
import '../models/bots.dart';
import 'bot_avatar_io.dart';
import 'bots_repository.dart';

/// A captured profile appearance editor. Metadata CAS and asset writes are
/// separate commits; acknowledged sections are never resent after partial save.
class BotProfileEditSession extends ChangeNotifier {
  BotProfileEditSession(this.repository, BotRecord bot, {BotAvatarIo? avatarIo})
    : _bot = bot,
      _avatarIo = avatarIo ?? BotAvatarIo(),
      _title = bot.title,
      _shape = bot.shape,
      _color = bot.color {
    repository.retain();
  }
  final BotsRepository repository;
  final BotAvatarIo _avatarIo;
  BotRecord _bot;
  BotRecord get bot => _bot;
  String _title, _shape, _color;
  String get title => _title;
  String get shape => _shape;
  String get color => _color;
  Uint8List? _image;
  Uint8List? get image => _assetDirty ? _image : _bot.avatar;
  bool _closed = false,
      _busy = false,
      _assetDirty = false,
      _imageMetadataPending = false;
  final _edited = <String>{};
  bool get busy => _busy;
  bool get dirty => _assetDirty || _edited.isNotEmpty || _imageMetadataPending;
  String? _error;
  String? get error => _error;
  bool _conflicted = false;
  bool get conflicted => _conflicted;
  void change({String? title, String? shape, String? color}) {
    if (_closed || busy) return;
    _title = title ?? _title;
    _shape = shape ?? _shape;
    _color = color ?? _color;
    void track(String key, bool changed) {
      if (changed) {
        _edited.add(key);
      } else {
        _edited.remove(key);
      }
    }

    if (title != null) track('title', title.trim() != _bot.title);
    if (shape != null) {
      track('shape', shape != _bot.shape);
      if (image != null) {
        _image = null;
        _assetDirty = true;
        _imageMetadataPending = true;
      }
    }
    if (color != null) track('color', color != _bot.color);
    notifyListeners();
  }

  void removeImage() {
    if (_closed || busy) return;
    _assetDirty = true;
    _imageMetadataPending = true;
    _image = null;
    notifyListeners();
  }

  Future<void> pickImage() async => _imageAction(() => _avatarIo.pick());
  Future<void> generate(String prompt) async => _imageAction(
    () => repository.generateAvatar(_bot, prompt.trim(), () => !_closed, () {}),
  );
  Future<void> _imageAction(Future<Uint8List?> Function() action) async {
    if (_closed || busy) return;
    _busy = true;
    _error = null;
    repository.retain();
    notifyListeners();
    try {
      final image = await action();
      if (!_closed && image != null) {
        _image = image.asUnmodifiableView();
        _assetDirty = true;
        _imageMetadataPending = true;
      }
    } catch (_) {
      if (!_closed) {
        _error =
            'Image could not be prepared. Use a PNG, JPEG or WebP smaller than 2 MB; generation needs a configured image provider.';
      }
    } finally {
      repository.release();
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save() async {
    if (_closed || busy || conflicted) return false;
    if (!dirty) return true;
    if (title.trim().isEmpty) {
      _error = 'Give your bot a name.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    repository.retain();
    notifyListeners();
    try {
      if (_edited.isNotEmpty || _imageMetadataPending) {
        _bot = await repository.metadata(
          _bot,
          {
            if (_edited.contains('title')) 'title': title.trim(),
            if (_edited.contains('shape')) 'shape': shape,
            if (_edited.contains('color')) 'color': color,
            if (_edited.contains('shape') ||
                _edited.contains('color') ||
                _imageMetadataPending)
              'custom': true,
            if (_imageMetadataPending)
              'imageKind': _image == null ? 'shape' : 'photo',
          },
          () => !_closed,
          () {},
        );
        _edited.clear();
        _imageMetadataPending = false;
      }
      if (_assetDirty) {
        await repository.avatar(_bot, _image, () => !_closed, () {});
        _assetDirty = false;
      }
      return !_closed;
    } catch (error) {
      if (!_closed) {
        _conflicted = error is BotMetadataConflict;
        _error = _conflicted
            ? error.toString()
            : 'Some changes could not be confirmed. Your draft is kept. Reload to check the saved appearance.';
      }
      return false;
    } finally {
      repository.release();
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Adopt a new CAS baseline without discarding the user's draft.
  Future<void> reload() async {
    if (_closed || busy) return;
    _busy = true;
    notifyListeners();
    try {
      final fresh = (await repository.bots())
          .where((b) => b.profile.name == _bot.profile.name)
          .firstOrNull;
      if (fresh == null) throw StateError('Profile no longer exists');
      if (_closed) return;
      _bot = await repository.enrich(fresh);
      if (_closed) return;
      if (!_edited.contains('title')) _title = _bot.title;
      if (!_edited.contains('shape')) _shape = _bot.shape;
      if (!_edited.contains('color')) _color = _bot.color;
      _conflicted = false;
      _error = 'Saved appearance reloaded. Review your draft before saving.';
    } catch (_) {
      if (!_closed) _error = 'Saved appearance could not be reloaded.';
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    repository.release();
    super.dispose();
  }
}
