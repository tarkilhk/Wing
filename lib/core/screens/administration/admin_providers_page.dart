import '../../theme/wing_theme.dart';
import '../../widgets/studio_action_label.dart';
import '../../widgets/studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/provider_access.dart';
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
    title: widget.shared ? 'Shared providers' : 'Profile access',
    scope: widget.shared
        ? '${_profile.server.connectionLabel} / Shared accounts'
        : _profile.label,
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
              widget.shared
                  ? 'Shared sign-ins for profiles on this server.'
                  : 'Shared or profile credentials · Availability is not a model test.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!widget.shared)
              TextButton(
                onPressed: () async {
                  try {
                    final shared = await _profile.server.sharedProviders();
                    if (context.mounted) {
                      await adminPush(
                        context,
                        (context) =>
                            AdminProvidersPage(profile: shared, shared: true),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      adminMessage(
                        context,
                        administrationError(e),
                        isError: true,
                      );
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
                  label: const Text('Refresh access'),
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
                            tooltip: 'Renew ${access.name} sign-in',
                            icon: const Icon(Icons.login),
                            onPressed: () async {
                              await adminPushProfile(
                                context,
                                _profile,
                                (context, profile) => AdminProviderSignIn(
                                  profile: profile,
                                  provider: access.row,
                                  shared: widget.shared,
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
                          shared: widget.shared,
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
                    (context, profile) => AdminServiceKeyCatalog(
                      profile: profile,
                      shared: widget.shared,
                    ),
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

String providerExpiryLabel(BuildContext context, ProviderAccess access) {
  final expiry = access.expiresAt?.toLocal();
  if (expiry == null) return 'Expiry not reported';
  final date = MaterialLocalizations.of(context).formatMediumDate(expiry);
  final time = TimeOfDay.fromDateTime(expiry).format(context);
  return '${access.state == ProviderAccessState.expired ? 'Expired' : 'Expires'} $date · $time';
}

String providerInventoryStatus(ProviderAccess access) => switch (access.state) {
  ProviderAccessState.connected => 'Sign-in stored',
  ProviderAccessState.expired => 'Sign-in expired',
  ProviderAccessState.signedOut => 'No sign-in stored',
  ProviderAccessState.external => 'Check external sign-in',
  ProviderAccessState.unknown => 'Status unavailable',
};

class AdminProviderDetail extends StatefulWidget {
  const AdminProviderDetail({
    super.key,
    required this.profile,
    required this.shared,
    required this.providerId,
  });
  final ProfileAdministration profile;
  final bool shared;
  final String providerId;
  @override
  State<AdminProviderDetail> createState() => _AdminProviderDetailState();
}

class _AdminProviderDetailState extends State<AdminProviderDetail> {
  late final _profile = widget.profile;
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
      if (mounted) {
        adminMessage(
          context,
          administrationError(e, writing: true),
          isError: true,
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Provider account',
    scope: widget.shared
        ? '${_profile.server.connectionLabel} / Shared accounts'
        : _profile.label,
    child: AdminLoad(
      load: () async {
        final providers = await _profile.read('providers/oauth');
        Map<String, dynamic> profiles;
        try {
          profiles = await _profile.server.read('profiles');
        } catch (_) {
          profiles = {};
        }
        return {...providers, 'profiles': profiles['profiles']};
      },
      builder: (context, data, refresh) {
        final row = administrationRows(
          data['providers'],
        ).where((row) => row['id'] == widget.providerId).firstOrNull;
        if (row == null) {
          return AdminNotice(
            'This provider is no longer available.',
            retry: refresh,
          );
        }
        final access = ProviderAccess(row);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.shared ? 'Shared account' : 'Profile access',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              widget.shared
                  ? 'Managed on ${_profile.server.connectionLabel}. Profiles may use these credentials unless they have their own access.'
                  : 'Access observed for ${_profile.name}. Credential source: ${access.status['source_label'] ?? 'unavailable'}. Individual account ownership is not reported.',
            ),
            if (!widget.shared)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          final shared = await _profile.server
                              .sharedProviders();
                          if (context.mounted) {
                            await adminPush(
                              context,
                              (context) => AdminProviderDetail(
                                profile: shared,
                                shared: true,
                                providerId: widget.providerId,
                              ),
                            );
                          }
                          refresh();
                        } catch (error) {
                          if (context.mounted) {
                            adminMessage(
                              context,
                              administrationError(error),
                              isError: true,
                            );
                          }
                        }
                      },
                child: const Text('Manage shared account'),
              ),
            _ProviderCard(
              access: access,
              selectedBy: data['profiles'] is List
                  ? [
                      for (final selected in administrationRows(
                        data['profiles'],
                      ))
                        if (selected['provider'] == widget.providerId &&
                            (widget.shared ||
                                selected['name'] == _profile.name))
                          '${selected['display_name'] is String && (selected['display_name'] as String).isNotEmpty ? selected['display_name'] : selected['name']}',
                    ]
                  : const [],
              shared: widget.shared,
              busy: _busy,
              disconnect: () => _disconnect(row, refresh),
              signIn: () async {
                await adminPushProfile(
                  context,
                  _profile,
                  (context, profile) => AdminProviderSignIn(
                    profile: profile,
                    provider: row,
                    shared: widget.shared,
                  ),
                );
                refresh();
              },
            ),
            TextButton(
              onPressed: _busy ? null : refresh,
              child: const Text('Refresh access'),
            ),
          ],
        );
      },
    ),
  );
}

class AdminServiceKeyCatalog extends StatefulWidget {
  const AdminServiceKeyCatalog({
    super.key,
    required this.profile,
    required this.shared,
  });
  final ProfileAdministration profile;
  final bool shared;
  @override
  State<AdminServiceKeyCatalog> createState() => _AdminServiceKeyCatalogState();
}

class _AdminServiceKeyCatalogState extends State<AdminServiceKeyCatalog> {
  String query = '';
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Add service key',
    scope: widget.shared
        ? '${widget.profile.server.connectionLabel} / Shared accounts'
        : widget.profile.label,
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
                          shared: widget.shared,
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

class _ProviderCard extends StatelessWidget {
  final ProviderAccess access;
  final List<String> selectedBy;
  final bool shared;
  final bool busy;
  final VoidCallback signIn;
  final VoidCallback disconnect;
  const _ProviderCard({
    required this.access,
    required this.selectedBy,
    required this.shared,
    required this.busy,
    required this.signIn,
    required this.disconnect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = access.needsAttention
        ? colors.error
        : access.state == ProviderAccessState.connected
        ? colors.primary
        : colors.onSurfaceVariant;
    final icon = switch (access.state) {
      ProviderAccessState.connected => Icons.link,
      ProviderAccessState.expired => Icons.schedule,
      ProviderAccessState.signedOut => Icons.link_off,
      ProviderAccessState.external => Icons.open_in_new,
      ProviderAccessState.unknown => Icons.help_outline,
    };
    String date(DateTime value) {
      final local = value.toLocal();
      return '${MaterialLocalizations.of(context).formatMediumDate(local)}, ${TimeOfDay.fromDateTime(local).format(context)}';
    }

    return Card(
      key: ValueKey('provider-${access.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(access.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      providerInventoryStatus(access),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(access.detail),
            if (selectedBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Default provider for: ${selectedBy.join(', ')}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (shared)
                const Text('These profiles may have their own credentials.'),
            ],
            if (access.hasCredential)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  access.expiresAt == null
                      ? 'Token expiry not reported'
                      : '${access.state == ProviderAccessState.expired ? 'Expired' : 'Expires'} ${date(access.expiresAt!)}',
                ),
              ),
            if (access.row['flow'] == 'device_code' ||
                (access.row['disconnectable'] == true && access.hasCredential))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (access.row['flow'] == 'device_code')
                      TextButton.icon(
                        onPressed: busy ? null : signIn,
                        icon: Icon(
                          access.hasCredential ? Icons.refresh : Icons.login,
                          size: 18,
                        ),
                        label: Text(
                          shared ? access.signInLabel : 'Add profile sign-in',
                        ),
                      ),
                    if (access.row['disconnectable'] == true &&
                        access.hasCredential)
                      TextButton(
                        onPressed: busy ? null : disconnect,
                        child: Text(
                          shared ? 'Disconnect' : 'Remove profile account',
                        ),
                      ),
                  ],
                ),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(
                access.external
                    ? 'Source and sign-in help'
                    : 'Connection details',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              children: [
                if (access.status['source_label'] is String)
                  Text('Source: ${access.status['source_label']}'),
                if (access.lastRefresh != null)
                  Text('Last token refresh: ${date(access.lastRefresh!)}'),
                if (access.canRefresh && access.hasCredential)
                  const Text(
                    'Refresh token stored. Renewal has not been verified.',
                  ),
                if (access.external) ...[
                  const Text(
                    'Manage sign-in with the provider\'s tool on the server.',
                  ),
                  if (access.row['cli_command'] is String)
                    SelectableText(
                      access.row['cli_command'] as String,
                      style: WingTokens.of(context).typography.mono,
                    ),
                ],
                if (access.row['disconnect_hint'] is String)
                  Text(access.row['disconnect_hint'] as String),
                const Text(
                  'Individual accounts and live usage are unavailable from this server view.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
          if (_error != null) AdminNotice.error(_error!),
          if (_session == null)
            FilledButton(
              onPressed: _busy ? null : _start,
              child: StudioActionLabel('Start sign-in', busy: _busy),
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
