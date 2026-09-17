import 'package:flutter/foundation.dart';
import '../services/administration_repository.dart';
import '../services/profile_voice_repository.dart';

/// Serializes autosaves and coalesces rapid taps to the latest requested voice.
class ProfileVoiceController extends ChangeNotifier {
  final ProfileVoiceRepository repository;
  ProfileVoiceSettings? settings;
  List<ProfileVoiceChoice> choices = const [];
  String? selected;
  String? error;
  String? catalogueError;
  bool loading = false;
  bool saving = false;
  bool fresh = false;
  bool _disposed = false;
  Future<void>? _pendingSave;
  ProfileVoiceController(this.repository);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (loading || saving || _disposed) return;
    loading = true;
    fresh = false;
    error = null;
    catalogueError = null;
    _notify();
    repository.profile.server.retain();
    try {
      settings = await repository.load();
      selected = settings!.voice;
      choices = const [];
      fresh = true;
      try {
        choices = await repository.choices(settings!.provider);
      } catch (e) {
        catalogueError = administrationError(e);
      }
    } catch (e) {
      error = administrationError(e);
    } finally {
      loading = false;
      repository.profile.server.release();
      _notify();
    }
  }

  Future<void> select(String voice) {
    voice = voice.trim();
    if (_disposed || loading || !fresh || settings?.key == null) {
      return Future.value();
    }
    if (voice.isEmpty || voice.length > 256) {
      error = 'Enter a voice ID of 1–256 characters.';
      _notify();
      return Future.value();
    }
    selected = voice;
    error = null;
    _notify();
    if (!saving && voice == settings!.voice) return Future.value();
    return _pendingSave ??= _saveLatest();
  }

  Future<void> _saveLatest() async {
    saving = true;
    repository.profile.server.retain();
    _notify();
    try {
      while (selected != settings!.voice) {
        final target = selected!;
        settings = await repository.save(settings!, target);
        _notify();
      }
    } catch (e) {
      selected = settings!.voice;
      fresh = false;
      error = 'Save not confirmed. Refresh before trying again.';
      if (e is AdministrationFailure &&
          e.message.contains('changed elsewhere')) {
        error = e.message;
      }
    } finally {
      saving = false;
      _pendingSave = null;
      repository.profile.server.release();
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
