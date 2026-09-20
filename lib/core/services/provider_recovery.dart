import '../models/provider_access.dart';
import '../models/provider_recovery.dart';
import 'administration_repository.dart';
import 'connection_manager.dart';

class ProviderRecovery {
  ProviderRecovery(this.profile);
  final ProfileAdministration profile;

  Future<ProviderAccess> observe(String id) async {
    final data = await profile.read('providers/oauth');
    final rows = administrationRows(
      data['providers'],
    ).where((row) => row['id'] == id).toList();
    if (rows.length != 1) {
      throw const ProviderRecoveryFailure(
        'This provider is no longer available.',
      );
    }
    return ProviderAccess(rows.single);
  }

  Future<String> _command(String command, {bool confirm = false}) async {
    await profile.requireProfile();
    final run = profile.server.providerCommand;
    if (run == null) {
      throw const ProviderRecoveryFailure(
        'Credential renewal is unavailable on this connection.',
      );
    }
    return run(profile.name, command, confirm: confirm);
  }

  Future<List<ProviderCredential>> candidates(ProviderAccess access) async {
    final renewal = ProviderRenewal.forAccess(access);
    if (renewal == null) {
      throw const ProviderRecoveryFailure(
        'This credential does not support renewal here. Use sign-in options.',
      );
    }
    final output = await _command('auth list ${renewal.pool}');
    final entries = ProviderCredential.parseList(renewal.pool, output);
    final candidates = entries.where(renewal.accepts).toList();
    // The CLI also accepts labels/indices: don't submit an ID that could
    // become another target if its original entry disappears between calls.
    return candidates
        .where(
          (e) =>
              !entries.any(
                (other) =>
                    other.id != e.id && other.label.toLowerCase() == e.id,
              ) &&
              !(int.tryParse(e.id) != null &&
                  int.parse(e.id) <= entries.length),
        )
        .toList();
  }

  Future<ProviderAccess> renew(
    ProviderAccess before,
    ProviderCredential selected,
  ) async {
    final latest = await observe(before.id);
    final renewal = ProviderRenewal.forAccess(latest);
    if (renewal == null || !sameSource(before, latest)) {
      throw const ProviderRecoveryFailure(
        'The credential source changed. Check status before renewing.',
      );
    }
    final entries = await candidates(latest);
    if (!entries.any((entry) => entry.sameIdentity(selected))) {
      throw const ProviderRecoveryFailure(
        'The selected credential changed. Check status before renewing.',
      );
    }
    await _command(
      'auth refresh ${renewal.pool} ${selected.id}',
      confirm: true,
    );
    try {
      return await observe(before.id);
    } catch (_) {
      throw const ProviderRecoveryFailure(
        'Hermes completed the renewal command, but status could not be checked. Check status before retrying.',
      );
    }
  }

  Future<ProviderAccess> remove(ProviderAccess before) async {
    final latest = await observe(before.id);
    if (!sameSource(before, latest) ||
        !latest.hasCredential ||
        latest.state == ProviderAccessState.unknown ||
        latest.row['disconnectable'] != true) {
      throw const ProviderRecoveryFailure(
        'The credential source changed. Check status before removing it.',
      );
    }
    final result = await profile.write(
      'DELETE',
      'providers/oauth/${Uri.encodeComponent(before.id)}',
    );
    if (result['ok'] != true) {
      throw const ProviderRecoveryFailure(
        'Credential removal was not confirmed. Check status before retrying.',
      );
    }
    try {
      return await observe(before.id);
    } catch (_) {
      throw const ProviderRecoveryFailure(
        'Saved credentials were removed, but status could not be checked.',
      );
    }
  }

  Future<ProviderCredentialFile> inspectFile(String path) async {
    final directory = ProviderCredentialFile.directory(path.trim());
    try {
      final listing = await profile.server.read('files', {'path': directory});
      return ProviderCredentialFile.fromListing(listing);
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 403) {
        throw const ProviderRecoveryFailure(
          'Hermes does not allow access to this location. Remove the credentials using Claude Code on the server.',
        );
      }
      if (error.statusCode == 404) {
        throw const ProviderRecoveryFailure(
          'The credential location was not found on the server.',
        );
      }
      rethrow;
    }
  }

  Future<ProviderAccess> deleteFile(
    ProviderAccess before,
    ProviderCredentialFile file,
  ) async {
    final latest = await observe(before.id);
    if (!ProviderCredentialFile.supports(latest) ||
        !sameSource(before, latest)) {
      throw const ProviderRecoveryFailure(
        'The sign-in changed. Check status and review the file again.',
      );
    }
    final current = await inspectFile(file.path);
    if (!file.sameFile(current)) {
      throw const ProviderRecoveryFailure(
        'The credential file changed. Review it again before deleting.',
      );
    }
    try {
      final result = await profile.server.write('DELETE', 'files', {
        'path': file.path,
        'recursive': false,
      });
      if (result['ok'] != true) {
        throw const ProviderRecoveryFailure(
          'File deletion was not confirmed. Check status before retrying.',
        );
      }
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 403) {
        throw const ProviderRecoveryFailure(
          'Hermes does not allow deletion at this location. Remove the credentials on the server.',
        );
      }
      rethrow;
    }
    try {
      return await observe(before.id);
    } catch (_) {
      throw const ProviderRecoveryFailure(
        'The credential file was deleted, but status could not be checked.',
      );
    }
  }

  static bool sameSource(ProviderAccess a, ProviderAccess b) =>
      a.id == b.id &&
      a.status['source'] == b.status['source'] &&
      a.status['source_label'] == b.status['source_label'] &&
      a.status['token_preview'] == b.status['token_preview'] &&
      a.status['expires_at'] == b.status['expires_at'];
}

String providerRecoveryError(Object error) => error is ProviderRecoveryFailure
    ? error.message
    : administrationError(error, writing: true);
