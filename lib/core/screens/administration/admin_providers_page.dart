import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';

class AdminProvidersPage extends StatefulWidget {
  final ProfileAdministration profile;
  final bool shared;
  const AdminProvidersPage({
    super.key,
    required this.profile,
    required this.shared,
  });
  @override
  State<AdminProvidersPage> createState() => _AdminProvidersPageState();
}

class _AdminProvidersPageState extends State<AdminProvidersPage> {
  late final _profile = widget.profile;
  String _query = '';
  bool _busy = false;

  Future<void> _disconnect(
    Map<String, dynamic> row,
    VoidCallback refresh,
  ) async {
    if (!await adminConfirm(
      context,
      widget.shared ? 'Disconnect shared account?' : 'Remove profile account?',
      widget.shared
          ? 'Profiles using this shared account may lose access. Other credential sources may still be available.'
          : 'This removes the profile account. Shared access may become available again.',
      action: 'Disconnect',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _profile.write(
        'DELETE',
        'providers/oauth/${Uri.encodeComponent(row['id'] as String)}',
      );
      if (result['ok'] != true) {
        throw const AdministrationFailure(
          'No account removal was confirmed. Refresh effective access.',
        );
      }
      await _profile.read('providers/oauth');
      refresh();
      if (mounted) {
        adminMessage(
          context,
          'Removal requested. Check the refreshed access status for remaining sources.',
        );
      }
    } catch (e) {
      if (mounted) adminMessage(context, administrationError(e, writing: true));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: widget.shared ? 'Shared providers' : 'Profile access',
    scope: widget.shared
        ? '${_profile.server.connectionLabel} / Shared accounts'
        : _profile.label,
    child: AdminLoad(
      load: () async {
        final results = await Future.wait([
          _profile.read('providers/oauth'),
          _profile.read('env'),
        ]);
        return {'providers': results[0]['providers'], 'env': results[1]};
      },
      builder: (context, data, refresh) {
        final providers = administrationRows(data['providers']);
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
            AdminNotice(
              widget.shared
                  ? 'Manage shared access for profiles that inherit these accounts.'
                  : 'Access available to this profile may come from shared accounts or external tools. Adding a credential here creates an explicit profile override.',
            ),
            if (!widget.shared)
              TextButton(
                onPressed: () async {
                  try {
                    final shared = await _profile.server.sharedProviders();
                    if (context.mounted) {
                      await adminPush(
                        context,
                        AdminProvidersPage(profile: shared, shared: true),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      adminMessage(context, administrationError(e));
                    }
                  }
                },
                child: const Text('Manage shared providers'),
              ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search providers and keys',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            TextButton(
              onPressed: _busy ? null : refresh,
              child: const Text('Refresh access'),
            ),
            const AdminNotice(
              'Per-account pool details are unavailable for an independently selected owner on this server. Status below describes effective provider access.',
            ),
            for (final row in providers.where(
              (r) =>
                  '${r['name']}'.toLowerCase().contains(_query.toLowerCase()),
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AdminGroup(
                  children: [
                    ListTile(
                      title: Text('${row['name']}'),
                      subtitle: Text(
                        '${(row['status'] as Map?)?['logged_in'] == true ? 'Account available' : 'Sign-in may be needed'}${(row['status'] as Map?)?['source_label'] is String ? ' · ${(row['status'] as Map)['source_label']}' : ''}',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (row['flow'] == 'device_code')
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await adminPush(
                                        context,
                                        AdminProviderSignIn(
                                          profile: _profile,
                                          provider: row,
                                          shared: widget.shared,
                                        ),
                                      );
                                      refresh();
                                    },
                              child: Text(
                                widget.shared
                                    ? 'Sign in / reconnect'
                                    : 'Add profile sign-in',
                              ),
                            ),
                          if (row['flow'] == 'external')
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Sign-in is managed by an external tool on the server.',
                              ),
                            ),
                          if (row['disconnectable'] == true)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _disconnect(row, refresh),
                              child: Text(
                                widget.shared
                                    ? 'Disconnect'
                                    : 'Remove profile account',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (row['disconnect_hint'] is String)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(row['disconnect_hint'] as String),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Service keys',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_query.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Stored keys appear here. Search to add another service key.',
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
                        await adminPush(
                          context,
                          AdminSecretPage(
                            profile: _profile,
                            name: entry.key.toString(),
                            shared: widget.shared,
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

class AdminSecretPage extends StatefulWidget {
  final ProfileAdministration profile;
  final String name;
  final bool shared;
  final bool isSet;
  const AdminSecretPage({
    super.key,
    required this.profile,
    required this.name,
    required this.shared,
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
    if ((remove || widget.shared) &&
        !await adminConfirm(
          context,
          remove ? 'Remove credential?' : 'Update shared credential?',
          widget.shared
              ? 'This changes shared access for profiles using this credential.'
              : 'Removing this override may reveal shared access again.',
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
      scope: widget.shared
          ? '${widget.profile.server.connectionLabel} / Shared accounts'
          : widget.profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AdminNotice(
            'Enter a new credential. Existing secret values are never loaded into this form.',
          ),
          if (_error != null) AdminNotice(_error!),
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
            child: Text(_busy ? 'Saving…' : 'Save credential'),
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
  final bool shared;
  const AdminProviderSignIn({
    super.key,
    required this.profile,
    required this.provider,
    required this.shared,
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
    if (url == null || !{'https', 'http'}.contains(url.scheme)) return;
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _error = 'Could not open the browser.');
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
      scope: widget.shared
          ? '${_profile.server.connectionLabel} / Shared accounts'
          : _profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminNotice(
            widget.shared
                ? 'This sign-in supplies shared access to inheriting profiles.'
                : 'This creates a sign-in override for this profile.',
          ),
          if (_error != null) AdminNotice(_error!),
          if (_session == null)
            FilledButton(
              onPressed: _busy ? null : _start,
              child: Text(_busy ? 'Starting…' : 'Start sign-in'),
            ),
          if (_session != null) ...[
            Text(
              _status == 'approved'
                  ? 'Sign-in approved. Refresh access to confirm readiness.'
                  : 'Status: $_status',
            ),
            if (_pending) ...[
              const SizedBox(height: 16),
              SelectableText(
                '${_session!['user_code'] ?? ''}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
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
