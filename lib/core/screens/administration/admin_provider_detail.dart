import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/provider_access.dart';
import '../../models/provider_recovery.dart';
import '../../services/administration_repository.dart';
import '../../services/provider_recovery.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/compact_switch.dart';
import '../../widgets/studio_action_label.dart';
import 'admin_providers_page.dart';
import 'admin_widgets.dart';

class AdminProviderDetail extends StatefulWidget {
  const AdminProviderDetail({
    super.key,
    required this.profile,
    required this.providerId,
  });
  final ProfileAdministration profile;
  final String providerId;
  @override
  State<AdminProviderDetail> createState() => _AdminProviderDetailState();
}

class _AdminProviderDetailState extends State<AdminProviderDetail> {
  late final _profile = widget.profile;
  late final _id = widget.providerId;
  late final _recovery = ProviderRecovery(_profile);
  ProviderAccess? _access;
  String? _error;
  String? _message;
  bool _busy = false;
  bool _renewing = false;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final access = await _recovery.observe(_id);
      if (mounted) {
        setState(() {
          _access = access;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Status could not be checked. ${_access == null ? 'Try again.' : 'The last observation is shown.'}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renew() async {
    _renewing = true;
    final access = _access!;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final entries = await _recovery.candidates(access);
      if (!mounted) return;
      if (entries.isEmpty) {
        throw const ProviderRecoveryFailure(
          'No matching renewable credential was found for this profile. Use sign-in options instead.',
        );
      }
      setState(() => _renewing = false);
      ProviderCredential? selected;
      if (entries.length == 1) {
        selected = entries.single;
      } else {
        selected = await showDialog<ProviderCredential>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Choose a saved sign-in'),
            children: [
              for (final entry in entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, entry),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${entry.label}\n${entry.source} · ${entry.id}',
                    ),
                  ),
                ),
            ],
          ),
        );
      }
      if (selected == null || !mounted) return;
      if (ProviderRenewal.forAccess(access)!.shared &&
          !await adminConfirm(
            context,
            'Renew shared sign-in?',
            'This renews the Claude Code sign-in on ${_profile.server.connectionLabel}. Other profiles and Claude Code using this sign-in also receive the renewed credentials.',
            action: 'Renew access',
          )) {
        return;
      }
      if (!mounted) return;
      setState(() => _renewing = true);
      final after = await _recovery.renew(access, selected);
      if (mounted) {
        setState(() {
          _access = after;
          _message = after.state == ProviderAccessState.connected
              ? 'Renewal completed. Credentials are detected; model access has not been tested.'
              : 'Renewal finished, but access is not confirmed. ${after.state == ProviderAccessState.expired ? 'The token is still expired. Sign in again.' : 'Check status or use sign-in options.'}';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = providerRecoveryError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _renewing = false;
        });
      }
    }
  }

  Future<void> _remove() async {
    final access = _access!;
    if (!await adminConfirm(
      context,
      'Remove saved sign-in?',
      'Remove the Hermes-managed ${access.name} credentials from ${_profile.name} on ${_profile.server.connectionLabel}? This clears this provider’s saved sign-ins for the profile and may stop chats using them. Your provider account is not deleted.',
      action: 'Remove sign-in',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final after = await _recovery.remove(access);
      if (mounted) {
        setState(() {
          _access = after;
          _message = after.hasCredential
              ? 'Saved sign-in removed. Another credential source is still detected.'
              : 'Saved sign-in removed.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = providerRecoveryError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final access = _access!;
    if (access.row['flow'] == 'device_code') {
      await adminPushProfile(
        context,
        _profile,
        (context, profile) =>
            AdminProviderSignIn(profile: profile, provider: access.row),
      );
    } else {
      await adminPush(
        context,
        (context) =>
            AdminProviderInstructions(profile: _profile, access: access),
      );
    }
    if (mounted) await _check();
  }

  Future<void> _fileRemoval() async {
    await adminPush(
      context,
      (context) =>
          AdminProviderFileRemoval(profile: _profile, access: _access!),
    );
    if (mounted) await _check();
  }

  Future<void> _keys() async {
    await adminPushProfile(
      context,
      _profile,
      (context, profile) => AdminServiceKeyCatalog(profile: profile),
    );
    if (mounted) await _check();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final tokens = WingTokens.of(context);
    final renewal = access == null ? null : ProviderRenewal.forAccess(access);
    final key = access?.status['source'] == 'env_var';
    final expired = access?.state == ProviderAccessState.expired;
    return PopScope(
      canPop: !_busy,
      child: AdminPage(
        title: access?.name ?? 'Provider account',
        scope: _profile.label,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) AdminNotice.error(_error!),
            if (_message != null)
              Semantics(liveRegion: true, child: AdminNotice(_message!)),
            if (access == null && _busy)
              const Center(child: CircularProgressIndicator()),
            if (access != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    expired
                        ? Icons.schedule
                        : access.hasCredential
                        ? Icons.key
                        : Icons.info_outline,
                    size: 20,
                    color: expired ? tokens.warning : tokens.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      providerInventoryStatus(access),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: expired ? tokens.warning : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (access.expiresAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    providerExpiryLabel(context, access),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              Text(access.detail, style: TextStyle(color: tokens.muted)),
              const SizedBox(height: 24),
              if (renewal != null) ...[
                FilledButton(
                  onPressed: _busy ? null : _renew,
                  child: StudioActionLabel('Renew access', busy: _renewing),
                ),
                const SizedBox(height: 8),
              ],
              if (key)
                FilledButton(
                  onPressed: _busy ? null : _keys,
                  child: const Text('Manage API keys'),
                )
              else if (renewal == null)
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: Text(
                    access.row['flow'] == 'device_code'
                        ? access.signInLabel
                        : 'Sign-in options',
                  ),
                )
              else
                OutlinedButton(
                  onPressed: _busy ? null : _signIn,
                  child: Text(
                    access.row['flow'] == 'device_code'
                        ? access.signInLabel
                        : 'Sign-in options',
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _check,
                child: const Text('Check status'),
              ),
              const SizedBox(height: 16),
              const Divider(),
              if (access.row['disconnectable'] == true &&
                  access.hasCredential &&
                  access.state != ProviderAccessState.unknown)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Remove saved sign-in',
                    style: TextStyle(color: tokens.danger),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _remove,
                )
              else if (ProviderCredentialFile.supports(access))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Delete saved credentials'),
                  subtitle: const Text('Shared file on the server'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _fileRemoval,
                )
              else if (access.external && !key)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Removal options'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy
                      ? null
                      : () => adminPush(
                          context,
                          (context) => AdminProviderInstructions(
                            profile: _profile,
                            access: access,
                            removal: true,
                          ),
                        ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Credential details'),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Source: ${access.status['source_label'] ?? 'Not reported'}',
                  ),
                  if (access.external)
                    const Text(
                      'External credentials may be used by other profiles or tools.',
                    ),
                  if (access.canRefresh)
                    const Text(
                      'A refresh token is stored. Renewal may still require signing in again.',
                    ),
                  Text(
                    'Checked ${TimeOfDay.fromDateTime(access.checkedAt).format(context)}',
                  ),
                  if (access.row['name'] != access.name)
                    Text('${access.row['name']}'),
                  const SizedBox(height: 12),
                ],
              ),
            ] else if (!_busy)
              TextButton(onPressed: _check, child: const Text('Check status')),
          ],
        ),
      ),
    );
  }
}

class AdminProviderInstructions extends StatelessWidget {
  const AdminProviderInstructions({
    super.key,
    required this.profile,
    required this.access,
    this.removal = false,
  });
  final ProfileAdministration profile;
  final ProviderAccess access;
  final bool removal;
  @override
  Widget build(BuildContext context) {
    final claude = access.id == 'claude-code';
    final command = removal
        ? access.row['disconnect_command']
        : access.row['cli_command'];
    return AdminPage(
      title: removal ? 'Removal options' : 'Sign-in options',
      scope: profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(access.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            removal
                ? 'These credentials are managed outside Hermes. Remove the sign-in using the provider’s tool on ${profile.server.connectionLabel}.'
                : claude
                ? 'Open Claude Code on ${profile.server.connectionLabel} and use /login. Then return to Wing and check status.'
                : 'Complete sign-in using the provider’s tool on ${profile.server.connectionLabel}, then return to Wing and check status.',
          ),
          if (removal)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Removing an external sign-in can affect other profiles and tools using it.',
              ),
            ),
          if (command is String && command.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Instructions supplied by Hermes'),
            const SizedBox(height: 8),
            SelectableText(
              command,
              style: WingTokens.of(context).typography.mono,
            ),
            if (claude && !removal)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'setup-token prints a token; it does not update the credential file shown in Wing. Use /login to replace the stored Claude Code sign-in.',
                ),
              ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: command));
                if (context.mounted) {
                  adminMessage(
                    context,
                    'Command copied. Run it on the server.',
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy command'),
            ),
          ],
          if (removal && access.row['disconnect_hint'] is String)
            Text(access.row['disconnect_hint'] as String),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Return to check status'),
          ),
        ],
      ),
    );
  }
}

class AdminProviderFileRemoval extends StatefulWidget {
  const AdminProviderFileRemoval({
    super.key,
    required this.profile,
    required this.access,
  });
  final ProfileAdministration profile;
  final ProviderAccess access;
  @override
  State<AdminProviderFileRemoval> createState() =>
      _AdminProviderFileRemovalState();
}

class _AdminProviderFileRemovalState extends State<AdminProviderFileRemoval> {
  late final _profile = widget.profile;
  late final _before = widget.access;
  late final _recovery = ProviderRecovery(_profile);
  final _path = TextEditingController(text: '~/.claude/.credentials.json');
  ProviderCredentialFile? _file;
  bool _confirmedLocation = false;
  bool _busy = false;
  bool _deleted = false;
  String? _error;
  String? _result;
  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _inspect() async {
    setState(() {
      _busy = true;
      _error = null;
      _file = null;
    });
    try {
      final file = await _recovery.inspectFile(_path.text);
      if (mounted) setState(() => _file = file);
    } catch (error) {
      if (mounted) setState(() => _error = providerRecoveryError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final file = _file!;
    if (!await adminConfirm(
      context,
      'Delete saved Claude Code credentials?',
      'Delete ${file.path} on ${_profile.server.connectionLabel}? Other profiles and Claude Code using this file will lose the saved sign-in. This does not revoke the account or copies already in use.',
      action: 'Delete credentials',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final after = await _recovery.deleteFile(_before, file);
      if (mounted) {
        setState(() {
          _deleted = true;
          _result = after.hasCredential
              ? 'The file was deleted. Another credential source is still detected.'
              : 'The file was deleted. No Claude Code credentials are detected.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = providerRecoveryError(error);
          _file = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AdminPage(
      title: 'Delete saved credentials',
      scope: '${_profile.server.connectionLabel} / Shared credential file',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) AdminNotice.error(_error!),
          if (_result != null) AdminNotice(_result!),
          if (!_deleted) ...[
            const Text(
              'Confirm where Claude Code stores this sign-in. Hermes reports a default path even when a custom location or system keychain is used.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _path,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Credential file on server',
              ),
              onChanged: (_) => setState(() {
                _file = null;
                _confirmedLocation = false;
              }),
            ),
            const SizedBox(height: 12),
            CompactSwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmedLocation,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _confirmedLocation = value),
              title: const Text(
                'This is the file used by this Claude Code sign-in',
              ),
            ),
            const Text(
              'If the sign-in uses a system keychain, remove it using Claude Code on the server instead.',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy || !_confirmedLocation ? null : _inspect,
              child: StudioActionLabel('Check file', busy: _busy),
            ),
            if (_file != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                _file!.path,
                style: WingTokens.of(context).typography.mono,
              ),
              const SizedBox(height: 8),
              const Text(
                'File found. Deletion affects every profile and tool using this file.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || !_confirmedLocation ? null : _delete,
                child: const Text('Delete credentials'),
              ),
            ],
          ],
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(_deleted ? 'Done' : 'Cancel'),
          ),
        ],
      ),
    ),
  );
}
