import 'package:flutter/foundation.dart';

import 'administration_repository.dart';

/// Independent observations for one captured profile. A failed refresh retains
/// its previous observation, never an invented empty/default configuration.
class AdministrationObservation {
  Map<String, dynamic>? data;
  DateTime? checkedAt;
  String? error;
  bool loading = false;
}

class AdministrationOverview extends ChangeNotifier {
  AdministrationOverview(this.profile);
  final ProfileAdministration profile;
  final observations = <String, AdministrationObservation>{};
  bool _disposed = false;
  int _generation = 0;
  static const endpoints = {
    'config': 'config',
    'model': 'model/info',
    'skills': 'skills',
    'tools': 'tools/toolsets',
    'access': 'providers/oauth',
    'connectors': 'mcp/servers',
  };

  Future<void> refresh() async {
    final generation = ++_generation;
    await Future.wait([
      for (final entry in endpoints.entries)
        _read(entry.key, entry.value, generation),
    ]);
  }

  Future<void> _read(String key, String endpoint, int generation) async {
    final observation = observations.putIfAbsent(
      key,
      AdministrationObservation.new,
    );
    observation.loading = true;
    observation.error = null;
    if (!_disposed) notifyListeners();
    try {
      final data = await profile.read(endpoint);
      // Validate collection shape before replacing the last good observation.
      final collection = switch (key) {
        'skills' || 'tools' => 'data',
        'access' => 'providers',
        'connectors' => 'servers',
        _ => null,
      };
      if (collection != null) administrationRows(data[collection]);
      if (_disposed || generation != _generation) return;
      observation.data = data;
      observation.checkedAt = DateTime.now();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      observation.error = administrationError(error);
    } finally {
      if (!_disposed && generation == _generation) {
        observation.loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
