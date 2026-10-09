import 'package:flutter/foundation.dart';
import '../models/health_alert.dart';
import 'health_alert_settings_store.dart';

/// Sole confirmed settings owner. Editors hold drafts; failed writes leave the
/// published policy unchanged. Saves cannot overlap.
class HealthAlertSettingsSession extends ChangeNotifier {
  HealthAlertSettingsSession(this._store) {
    try {
      _settings = _store.read();
    } catch (_) {
      _settings = HealthAlertSettings(enabled: false);
      _error = 'Saved alert settings could not be read. Review and save them.';
    }
  }
  final HealthAlertSettingsStore _store;
  late HealthAlertSettings _settings;
  HealthAlertSettings get settings => _settings;
  String? _error;
  String? get error => _error;
  bool _saving = false, _closed = false;
  bool get saving => _saving;
  Future<bool> save(
    HealthAlertSettings draft, {
    required HealthAlertSettings expected,
  }) async {
    if (_saving || _closed) return false;
    if (!identical(expected, _settings)) {
      _error =
          'Alert settings changed in another window. Reset the draft before editing again.';
      notifyListeners();
      return false;
    }
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _store.write(draft);
      if (_closed) return false;
      _settings = draft;
      return true;
    } catch (_) {
      if (!_closed) _error = 'Could not save alert settings. Retry Save.';
      return false;
    } finally {
      _saving = false;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
