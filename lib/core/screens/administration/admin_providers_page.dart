import '../../widgets/studio_action_label.dart';
import '../../widgets/studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/provider_access.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';
import 'admin_provider_detail.dart';
export 'admin_provider_detail.dart' show AdminProviderDetail;

class AdminProvidersPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminProvidersPage({super.key, required this.profile});
  @override
  State<AdminProvidersPage> createState() => _AdminProvidersPageState();
}

class _AdminProvidersPageState extends State<AdminProvidersPage> {
  late final _profile = widget.profile;
  String _query = '';
  String _filter = 'All';
  final bool _busy = false;

  Future<Map<String, dynamic>> _profileSelections() async {
    try {
      return await _profile.server.read('profiles');
    } catch (_) {
      return {'unavailable': true};
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Profile access',
    scope: _profile.label,
    child: AdminLoad(
      load: () async {
        final results = await Future.wait([
          _profile.read('providers/oauth'),
          _profile.read('env'),
          _profileSelections(),
        ]);
        return {
          'providers': results[0]['providers'],
          'env': results[1],
          'selections': results[2],
          'checkedAt': DateTime.now(),
        };
      },
      builder: (context, data, refresh) {
        final providers =
            administrationRows(
              data['providers'],
            ).map((row) => ProviderAccess(row)).toList()..sort((a, b) {
              final order = a.sortOrder.compareTo(b.sortOrder);
              return order != 0 ? order : a.name.compareTo(b.name);
            });
        final selections = data['selections'] as Map;

        final connected = providers
            .where((p) => p.state == ProviderAccessState.connected)
            .length;
        final attention = providers.where((p) => p.needsAttention).length;
        final visible = providers
            .where(
              (p) =>
                  '${p.name} ${p.id} ${p.status['source_label'] ?? ''}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()) &&
                  (_filter == 'All' ||
                      (_filter == 'Stored' &&
                          p.state == ProviderAccessState.connected) ||
                      (_filter == 'Needs attention' && p.needsAttention)),
            )
            .toList();
        final env = data['env'] as Map;
        final keys = env.entries.where(
          (e) =>
              e.value is Map &&
              (e.value as Map)['channel_managed'] != true &&
              (e.value as Map)['category'] != 'custom' &&
              (_query.isNotEmpty || (e.value as Map)['is_set'] == true) &&
              '${e.key} ${(e.value as Map)['provider_label'] ?? ''}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Credentials for this profile · Availability is not a model test.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search providers and keys',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (label, count) in [
                  ('All', providers.length),
                  ('Stored', connected),
                  ('Needs attention', attention),
                ])
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text('$label ($count)'),
                    selected: _filter == label,
                    onSelected: (_) => setState(() => _filter = label),
                  ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check status'),
                ),
                Text(
                  'Checked ${TimeOfDay.fromDateTime(data['checkedAt'] as DateTime).format(context)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (selections['profiles'] is! List)
              const AdminNotice(
                'Profile selections could not be loaded. Refresh to retry.',
              ),
            if (visible.isEmpty)
              const AdminNotice('No providers match this view.'),
            AdminGroup(
              children: [
                for (final access in visible)
                  ListTile(
                    key: ValueKey('provider-${access.id}'),
                    title: Text(
                      access.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${providerInventoryStatus(access)} · ${access.external ? 'Managed externally' : access.status['source_label'] ?? 'Source not reported'}${access.hasCredential ? '\n${providerExpiryLabel(context, access)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (access.state == ProviderAccessState.expired &&
                            access.row['flow'] == 'device_code')
                          IconButton(
                            tooltip: 'Sign in to ${access.name} again',
                            icon: const Icon(Icons.login),
                            onPressed: () async {
                              await adminPushProfile(
                                context,
                                _profile,
                                (context, profile) => AdminProviderSignIn(
                                  profile: profile,
                                  provider: access.row,
                                ),
                              );
                              refresh();
                            },
                          ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () async {
                      await adminPushProfile(
                        context,
                        _profile,
                        (context, profile) => AdminProviderDetail(
                          profile: profile,
                          providerId: access.id,
                        ),
                      );
                      refresh();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Service keys',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await adminPushProfile(
                    context,
                    _profile,
                    (context, profile) =>
                        AdminServiceKeyCatalog(profile: profile),
                  );
                  refresh();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add service key'),
              ),
            ),
            for (final entry in keys)
              ListTile(
                title: Text(entry.key.toString()),
                subtitle: Text(
                  (entry.value as Map)['is_set'] == true
                      ? 'Stored for this owner'
                      : 'Not stored here',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () async {
                        await adminPushProfile(
                          context,
                          _profile,
                          (context, profile) => AdminSecretPage(
                            profile: profile,
                            name: entry.key.toString(),

                            isSet: (entry.value as Map)['is_set'] == true,
                          ),
                        );
                        refresh();
                      },
              ),
          ],
        );
      },
    ),
  );
}

String providerExpiryLabel(BuildContext context, ProviderAccess access) {
  final expiry = access.expiresAt?.toLocal();
  if (expiry == null) return 'Expiry not reported';
  final date = MaterialLocalizations.of(context).formatMediumDate(expiry);
  final time = TimeOfDay.fromDateTime(expiry).format(context);
  return '${access.state == ProviderAccessState.expired ? 'Expired' : 'Expires'} $date · $time';
}

String providerInventoryStatus(ProviderAccess access) => switch (access.state) {
  ProviderAccessState.connected => 'Credentials detected',
  ProviderAccessState.expired => 'Access token expired',
  ProviderAccessState.signedOut => 'No sign-in stored',
  ProviderAccessState.external => 'Check external sign-in',
  ProviderAccessState.unknown => 'Status unavailable',
};

class AdminServiceKeyCatalog extends StatefulWidget {
  const AdminServiceKeyCatalog({super.key, required this.profile});
  final ProfileAdministration profile;
  @override
  State<AdminServiceKeyCatalog> createState() => _AdminServiceKeyCatalogState();
}

class _AdminServiceKeyCatalogState extends State<AdminServiceKeyCatalog> {
  String query = '';
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Add service key',
    scope: widget.profile.label,
    child: AdminLoad(
      load: () => widget.profile.read('env'),
      builder: (context, data, refresh) {
        final entries = data.entries
            .where(
              (entry) =>
                  entry.value is Map &&
                  (entry.value as Map)['channel_managed'] != true &&
                  (entry.value as Map)['category'] != 'custom' &&
                  '${entry.key} ${(entry.value as Map)['provider_label'] ?? ''}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Find a service',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const AdminNotice('No services match this search.'),
            AdminGroup(
              children: [
                for (final entry in entries)
                  ListTile(
                    title: Text(
                      '${(entry.value as Map)['provider_label'] ?? entry.key}',
                    ),
                    subtitle: Text(
                      '${entry.key}${(entry.value as Map)['is_set'] == true ? ' · Key stored' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await adminPushProfile(
                        context,
                        widget.profile,
                        (context, profile) => AdminSecretPage(
                          profile: profile,
                          name: entry.key,

                          isSet: (entry.value as Map)['is_set'] == true,
                        ),
                      );
                      refresh();
                    },
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class AdminSecretPage extends StatefulWidget {
  final ProfileAdministration profile;
  final String name;
  final bool isSet;
  const AdminSecretPage({
    super.key,
    required this.profile,
    required this.name,
    required this.isSet,
  });
  @override
  State<AdminSecretPage> createState() => _AdminSecretPageState();
}

class _AdminSecretPageState extends State<AdminSecretPage> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _leave = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_input.text.isNotEmpty &&
        !await adminConfirm(
          context,
          'Discard key?',
          'The new credential has not been confirmed as saved.',
          action: 'Discard',
        )) {
      return;
    }
    if (mounted) {
      setState(() => _leave = true);
      Navigator.pop(context);
    }
  }

  Future<void> _save({bool remove = false}) async {
    if (_busy || (!remove && _input.text.trim().isEmpty)) return;
    if (remove &&
        !await adminConfirm(
          context,
          'Remove saved key?',
          'This removes the saved key from ${widget.profile.name}. Other credential sources may still be available. The key is not revoked at its provider.',
          action: remove ? 'Remove' : 'Save',
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.profile.write(remove ? 'DELETE' : 'PUT', 'env', {
        'key': widget.name,
        if (!remove) 'value': _input.text.trim(),
      });
      final env = await widget.profile.read('env');
      final isSet = (env[widget.name] as Map?)?['is_set'] == true;
      if (isSet == remove) {
        throw const AdministrationFailure(
          'Credential state could not be confirmed.',
        );
      }
      _input.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _leave = true;
        });
        adminMessage(
          context,
          remove
              ? 'Credential removed from this owner.'
              : 'Credential saved. Refresh provider readiness to check access.',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = administrationError(e, writing: true);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leave || (!_busy && _input.text.isEmpty),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: AdminPage(
      title: widget.name,
      scope: widget.profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AdminNotice(
            'Enter a new credential. Existing secret values are never loaded into this form.',
          ),
          if (_error != null) AdminNotice.error(_error!),
          TextField(
            controller: _input,
            obscureText: true,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'New credential'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _input.text.trim().isEmpty
                ? null
                : () => _save(),
            child: StudioActionLabel('Save credential', busy: _busy),
          ),
          if (widget.isSet)
            TextButton(
              onPressed: _busy ? null : () => _save(remove: true),
              child: const Text('Remove stored credential'),
            ),
        ],
      ),
    ),
  );
}

class AdminProviderSignIn extends StatefulWidget {
  final ProfileAdministration profile;
  final Map<String, dynamic> provider;
  const AdminProviderSignIn({
    super.key,
    required this.profile,
    required this.provider,
  });
  @override
  State<AdminProviderSignIn> createState() => _AdminProviderSignInState();
}

class _AdminProviderSignInState extends State<AdminProviderSignIn> {
  late final _profile = widget.profile;
  Map<String, dynamic>? _session;
  String? _error;
  String _status = '';
  bool _busy = false;
  Timer? _timer;
  bool _leave = false;
  String get _id => Uri.encodeComponent(widget.provider['id'] as String);
  bool get _pending =>
      _session != null && (_status == 'pending' || _status.isEmpty);
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _pending) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await _profile.write(
        'POST',
        'providers/oauth/$_id/start',
      );
      if (session['session_id'] is! String ||
          session['flow'] != 'device_code') {
        throw const AdministrationFailure(
          'The server did not return a supported sign-in session.',
        );
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _status = 'pending';
      });
      _schedule();
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  void _schedule() {
    _timer?.cancel();
    final interval = (_session?['poll_interval'] as num? ?? 5).toInt().clamp(
      3,
      60,
    );
    _timer = Timer(Duration(seconds: interval), _poll);
  }

  Future<void> _poll() async {
    if (!_pending || _busy) return;
    setState(() => _busy = true);
    try {
      final response = await _profile.read(
        'providers/oauth/$_id/poll/${Uri.encodeComponent(_session!['session_id'] as String)}',
      );
      if (!mounted) return;
      setState(() {
        _status = response['status'] as String? ?? 'unknown';
        _error = null;
      });
      if (_pending) _schedule();
    } catch (e) {
      if (mounted) setState(() => _error = administrationError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_pending) {
      _timer?.cancel();
      setState(() => _busy = true);
      try {
        await _profile.write(
          'DELETE',
          'providers/oauth/sessions/${Uri.encodeComponent(_session!['session_id'] as String)}',
        );
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error =
                'Cancellation could not be confirmed. Retry before closing.';
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _leave = true;
      });
      Navigator.pop(context);
    }
  }

  Future<void> _openBrowser() async {
    final url = Uri.tryParse('${_session?['verification_url'] ?? ''}');
    try {
      if (url == null ||
          !{'https', 'http'}.contains(url.scheme) ||
          !await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Browser unavailable');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the browser. Try opening the sign-in address below.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leave || (!_pending && !_busy),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: AdminPage(
      title: 'Sign in to ${widget.provider['name']}',
      scope: _profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminNotice(
            'Save this sign-in for ${_profile.name} on ${_profile.server.connectionLabel}.',
          ),
          if (_error != null) AdminNotice.error(_error!),
          if (_session == null ||
              (!_pending && _status != 'approved' && _status != 'unknown'))
            FilledButton(
              onPressed: _busy ? null : _start,
              child: StudioActionLabel(
                _session == null ? 'Start sign-in' : 'Start again',
                busy: _busy,
              ),
            ),
          if (_session != null) ...[
            if (const {
              'error',
              'failed',
              'denied',
              'expired',
            }.contains(_status))
              StudioError('Status: $_status')
            else
              Text(
                _status == 'approved'
                    ? 'Sign-in saved. Return to check credential status.'
                    : 'Status: $_status',
              ),
            if (_pending) ...[
              const SizedBox(height: 16),
              SelectableText(
                '${_session!['user_code'] ?? ''}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '${_session!['user_code'] ?? ''}'),
                  );
                  if (context.mounted) adminMessage(context, 'Code copied.');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy code'),
              ),
              if (_error != null)
                SelectableText('${_session!['verification_url'] ?? ''}'),
              FilledButton(
                onPressed: _openBrowser,
                child: const Text('Open sign-in page'),
              ),
              TextButton(
                onPressed: _busy ? null : _poll,
                child: const Text('Check status'),
              ),
            ],
          ],
          TextButton(
            onPressed: _busy ? null : _close,
            child: Text(_pending ? 'Cancel sign-in' : 'Close'),
          ),
        ],
      ),
    ),
  );
}
