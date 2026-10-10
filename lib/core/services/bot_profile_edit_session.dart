import 'dart:async';
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
  int _assetVersion = 0;
  Timer? _autosave;
  Completer<bool>? _pending;
  bool get saving => _pending != null;
  bool _reviewRequired = false;
  bool get needsReview => _reviewRequired;
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
    if (shape != null) {
      if (image != null) {
        _image = null;
        _assetDirty = true;
        _imageMetadataPending = true;
        _assetVersion++;
      }
    }
    _trackEdits();
    if (!_conflicted) {
      _error = null;
      _reviewRequired = false;
    }
    _scheduleSave();
    notifyListeners();
  }

  void _trackEdits() {
    _edited
      ..clear()
      ..addAll([
        if (_title.trim() != _bot.title) 'title',
        if (_shape != _bot.shape) 'shape',
        if (_color != _bot.color) 'color',
      ]);
  }

  void _scheduleSave() {
    _autosave?.cancel();
    if (_closed ||
        busy ||
        saving ||
        conflicted ||
        _error != null ||
        needsReview ||
        !dirty ||
        title.trim().isEmpty) {
      return;
    }
    _autosave = Timer(const Duration(milliseconds: 450), () {
      unawaited(flush());
    });
  }

  void removeImage() {
    if (_closed || busy) return;
    _assetDirty = true;
    _imageMetadataPending = true;
    _image = null;
    _assetVersion++;
    if (!_conflicted) {
      _error = null;
      _reviewRequired = false;
    }
    _scheduleSave();
    notifyListeners();
  }

  Future<void> pickImage() async => _imageAction(() => _avatarIo.pick());
  Future<void> generate(String prompt) async => _imageAction(
    () => repository.generateAvatar(_bot, prompt.trim(), () => !_closed, () {}),
  );
  Future<void> _imageAction(Future<Uint8List?> Function() action) async {
    if (_closed || busy || saving) return;
    _autosave?.cancel();
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
        _assetVersion++;
        _reviewRequired = false;
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
        _scheduleSave();
        notifyListeners();
      }
    }
  }

  /// Flush debounced edits on Back or retry; concurrent callers share one drain.
  Future<bool> flush() {
    _autosave?.cancel();
    if (_pending case final pending?) return pending.future;
    if (_closed || busy || conflicted) return Future.value(false);
    if (!dirty) return Future.value(true);
    final pending = _pending = Completer<bool>();
    _error = null;
    _reviewRequired = false;
    repository.retain();
    notifyListeners();
    unawaited(_persist(pending));
    return pending.future;
  }

  Future<void> _persist(Completer<bool> pending) async {
    var saved = false;
    try {
      while (!_closed && dirty) {
        if (title.trim().isEmpty) {
          _error = 'Give your bot a name.';
          return;
        }
        final assetVersion = _assetVersion;
        final assetDirty = _assetDirty;
        final image = _image;
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
                'imageKind': image == null ? 'shape' : 'photo',
            },
            () => !_closed,
            () {},
          );
          if (_closed) return;
          _trackEdits();
          if (_assetVersion == assetVersion) _imageMetadataPending = false;
        }
        if (assetDirty) {
          await repository.avatar(_bot, image, () => !_closed, () {});
          if (_closed) return;
          _bot = _bot.withAvatar(image);
          if (_assetVersion == assetVersion) _assetDirty = false;
        }
      }
      saved = !_closed;
    } catch (error) {
      if (!_closed) {
        _conflicted = error is BotMetadataConflict;
        _error = _conflicted
            ? error.toString()
            : 'Some changes could not be confirmed. Your draft is kept. Reload to check the saved appearance.';
      }
    } finally {
      _pending = null;
      pending.complete(saved);
      repository.release();
      if (!_closed) {
        notifyListeners();
      }
    }
  }

  /// Adopt a new CAS baseline without discarding the user's draft.
  Future<void> reload() async {
    if (_closed || busy || saving) return;
    _autosave?.cancel();
    final needsReview = _error != null || conflicted || _reviewRequired;
    _busy = true;
    repository.retain();
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
      _trackEdits();
      _conflicted = false;
      _error = null;
      _reviewRequired = needsReview && dirty;
    } catch (_) {
      if (!_closed) _error = 'Saved appearance could not be reloaded.';
    } finally {
      repository.release();
      if (!_closed) {
        _busy = false;
        _scheduleSave();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _autosave?.cancel();
    repository.release();
    super.dispose();
  }
}
