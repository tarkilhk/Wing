import 'package:flutter/foundation.dart';

import 'administration_repository.dart';
import 'health_snapshot.dart';

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

  /// Last probe results for this profile's enabled connectors. Null means the
  /// request did not establish a result; false means Hermes reported failure.
  Map<String, bool?> connectorChecks = const {};
  bool _disposed = false;
  final _generations = <String, int>{};
  static const endpoints = {
    'config': 'config',
    'model': 'model/info',
    'skills': 'skills',
    'tools': 'tools/toolsets',
    'access': 'providers/oauth',
    'connectors': 'mcp/servers',
  };

  /// Persist only health metadata, never connector commands, environment
  /// variables, provider secrets or the full configuration response.
  Map<String, dynamic> healthSnapshot() => {
    'observations': {
      for (final entry in observations.entries)
        if ({'model', 'access', 'tools', 'connectors'}.contains(entry.key))
          entry.key: {
            ...healthObservationSnapshot(entry.value),
            'data': entry.value.data == null
                ? null
                : _healthData(entry.key, entry.value.data!),
          },
    },
    'connectorChecks': connectorChecks,
  };

  void restoreHealth(Map snapshot) {
    for (final entry in (snapshot['observations'] as Map).entries) {
      final observation = AdministrationObservation();
      restoreHealthObservation(observation, entry.value as Map);
      observations[entry.key as String] = observation;
    }
    connectorChecks = Map<String, bool?>.from(
      snapshot['connectorChecks'] as Map,
    );
  }

  Map<String, dynamic> _healthData(String key, Map<String, dynamic> data) {
    if (key == 'model') {
      return {'model': data['model'], 'provider': data['provider']};
    }
    final collection = switch (key) {
      'access' => 'providers',
      'tools' => 'data',
      _ => 'servers',
    };
    return {
      collection: [
        for (final row in administrationRows(data[collection]))
          {
            for (final field in [
              'id',
              'name',
              'label',
              'display_name',
              'flow',
              'enabled',
              'configured',
            ])
              if (row.containsKey(field)) field: row[field],
            if (key == 'access' && row['status'] is Map)
              'status': {
                for (final field in ['logged_in', 'expires_at'])
                  field: row['status'][field],
                if (row['status']['error'] != null) 'error': true,
              },
          },
      ],
    };
  }

  Future<void> refresh({Set<String>? keys, bool testConnectors = false}) async {
    await Future.wait([
      for (final entry in endpoints.entries)
        if (keys == null || keys.contains(entry.key))
          _read(
            entry.key,
            entry.value,
            _generations.update(entry.key, (n) => n + 1, ifAbsent: () => 1),
            testConnectors: testConnectors && entry.key == 'connectors',
          ),
    ]);
  }

  Future<void> _read(
    String key,
    String endpoint,
    int generation, {
    required bool testConnectors,
  }) async {
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
      if (_disposed || generation != _generations[key]) return;
      if (key == 'connectors') {
        final results = <String, bool?>{};
        if (testConnectors) {
          for (final row in administrationRows(data['servers'])) {
            if (_disposed || generation != _generations[key]) return;
            final name = row['name'];
            if (row['enabled'] != true || name is! String || name.isEmpty) {
              continue;
            }
            try {
              // Stock Hermes 783f854b0fb2bb224cedf972b40adfc77e9c818f:
              // connect, inspect capabilities and disconnect in this profile.
              final result = await profile.testConnector(name);
              results[name] = result['ok'] is bool
                  ? result['ok'] as bool
                  : null;
            } catch (_) {
              results[name] = null;
            }
          }
        }
        if (_disposed || generation != _generations[key]) return;
        connectorChecks = Map.unmodifiable(results);
      }
      observation.data = data;
      observation.checkedAt = DateTime.now();
    } catch (error) {
      if (_disposed || generation != _generations[key]) return;
      observation.error = administrationError(error);
    } finally {
      if (!_disposed && generation == _generations[key]) {
        observation.loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
