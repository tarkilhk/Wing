// ignore_for_file: prefer_initializing_formals

import 'package:shared_preferences/shared_preferences.dart';

import '../models/composer_action.dart';
import '../models/session_visibility.dart';
import '../theme/profile_workspace_theme.dart';
import 'device_preference.dart';
import 'text_size_preference.dart';
import 'turn_notification_service.dart';
import 'config_backup.dart';
import 'connection_manager.dart';
import 'voice_preferences.dart';

/// How an imported backup is applied to the connections already on the device.
enum ConfigImportMode {
  /// Connections present in the backup are added or updated by id; anything
  /// else already on the device is kept.
  merge,

  /// The device ends up with exactly the connections in the backup.
  replace,
}

class ConfigImportResult {
  final int connectionsAdded;
  final int connectionsUpdated;
  final int connectionsRemoved;
  final int preferencesApplied;
  final int preferencesSkipped;

  const ConfigImportResult({
    required this.connectionsAdded,
    required this.connectionsUpdated,
    required this.connectionsRemoved,
    required this.preferencesApplied,
    required this.preferencesSkipped,
  });

  String get summary {
    final parts = <String>[];
    if (connectionsAdded > 0) parts.add('$connectionsAdded added');
    if (connectionsUpdated > 0) parts.add('$connectionsUpdated updated');
    if (connectionsRemoved > 0) parts.add('$connectionsRemoved removed');
    final connections = parts.isEmpty
        ? 'No connection changes'
        : 'Connections: ${parts.join(', ')}';
    return '$connections · $preferencesApplied settings restored'
        '${preferencesSkipped > 0 ? ' · $preferencesSkipped settings skipped' : ''}';
  }
}

/// Builds and applies configuration backups.
///
/// Only keys this app actually owns are exported and imported. Everything else
/// in `SharedPreferences` — plugin caches, the turn journal, the raw connection
/// list, transient UI state — is deliberately excluded, so an imported file can
/// never overwrite storage the backup format does not understand.
class ConfigBackupService {
  /// Exact preference keys that are safe to carry between devices.
  static const Set<String> exactPreferenceKeys = <String>{
    'theme_mode',
    'verbose_mode',
    ...VoicePreferences.keys,
    'app_text_size_preference',
    WorkspaceAccent.preferenceKey,
    ComposerAction.preferenceKey,
    completionNotificationsKey,
    attentionNotificationsKey,
    notificationPreviewsKey,
  };

  /// Portable backup ownership uses logical connection IDs, never device HMACs.
  static const visibilityBackupPrefix = 'connection_visibility.';

  final ConnectionManager _connectionManager;
  final SharedPreferences _preferences;

  ConfigBackupService({
    required ConnectionManager connectionManager,
    required SharedPreferences preferences,
  }) : _connectionManager = connectionManager,
       _preferences = preferences;

  static bool isBackedUpKey(String key) {
    if (exactPreferenceKeys.contains(key)) return true;
    return key.startsWith(visibilityBackupPrefix) &&
        key.length > visibilityBackupPrefix.length;
  }

  static bool _accepts(String key, Object value) {
    if (VoicePreferences.keys.contains(key)) {
      return VoicePreferences.accepts(key, value);
    }
    return switch (key) {
      'theme_mode' => {'system', 'light', 'dark'}.contains(value),
      'verbose_mode' ||
      completionNotificationsKey ||
      attentionNotificationsKey ||
      notificationPreviewsKey => value is bool,
      TextSizePreference.preferenceKey => TextSizePreference.values.any(
        (size) => size.storageValue == value,
      ),
      WorkspaceAccent.preferenceKey => WorkspaceAccent.values.any(
        (accent) => accent.name == value,
      ),
      ComposerAction.preferenceKey => ComposerAction.runningDefaults.any(
        (action) => action.name == value,
      ),
      _ =>
        key.startsWith(visibilityBackupPrefix) &&
            SessionVisibility.values.any(
              (visibility) => visibility.name == value,
            ),
    };
  }

  Future<ConfigBackup> export({required String appVersion}) async {
    final connections = await _connectionManager.loadConnectionsWithSecrets();

    final preferences = <String, Object>{};
    for (final key in _preferences.getKeys()) {
      if (!exactPreferenceKeys.contains(key)) continue;
      final value = _preferences.get(key);
      if (value != null && _accepts(key, value)) {
        preferences[key] = value;
      }
    }
    for (final connection in connections) {
      final value = _preferences.get(
        SessionVisibility.preferenceKey(connection.id),
      );
      final key = '$visibilityBackupPrefix${connection.id}';
      if (value != null && _accepts(key, value)) preferences[key] = value;
    }

    return ConfigBackup(
      createdAt: DateTime.now().toUtc(),
      appVersion: appVersion,
      connections: connections,
      preferences: preferences,
    );
  }

  Future<ConfigImportResult> import(
    ConfigBackup backup, {
    required ConfigImportMode mode,
  }) async {
    // Validate and detach caller-owned data before any storage mutation.
    backup = ConfigBackup.fromJson(backup.toJson());
    final connectionIds = backup.connections.map((c) => c.id).toSet();
    final accepted = <String, Object>{};
    var skipped = 0;
    for (final entry in backup.preferences.entries) {
      if (!isBackedUpKey(entry.key) || !_accepts(entry.key, entry.value)) {
        skipped++;
        continue;
      }
      if (entry.key.startsWith(visibilityBackupPrefix)) {
        final id = entry.key.substring(visibilityBackupPrefix.length);
        if (!connectionIds.contains(id)) {
          skipped++;
          continue;
        }
        accepted[SessionVisibility.preferenceKey(id)] = entry.value;
      } else {
        accepted[entry.key] = entry.value;
      }
    }
    final existingIds = _connectionManager
        .getConnections()
        .map((connection) => connection.id)
        .toSet();

    var added = 0;
    var updated = 0;
    for (final connection in backup.connections) {
      if (existingIds.contains(connection.id)) {
        updated++;
      } else {
        added++;
      }
    }
    final removed = mode == ConfigImportMode.replace
        ? existingIds
              .difference(
                backup.connections.map((connection) => connection.id).toSet(),
              )
              .length
        : 0;

    try {
      await _connectionManager.importConnections(
        backup.connections,
        replaceExisting: mode == ConfigImportMode.replace,
      );
    } on CredentialStorageException catch (error) {
      throw ConfigBackupException(error.message);
    }

    var applied = 0;
    for (final entry in accepted.entries) {
      try {
        await saveDevicePreference(_preferences, entry.key, entry.value);
      } catch (_) {
        throw const ConfigBackupException(
          'A restored setting could not be saved.',
        );
      }
      applied++;
    }

    return ConfigImportResult(
      connectionsAdded: added,
      connectionsUpdated: updated,
      connectionsRemoved: removed,
      preferencesApplied: applied,
      preferencesSkipped: skipped,
    );
  }
}
