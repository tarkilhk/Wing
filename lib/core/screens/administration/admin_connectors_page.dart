import '../../widgets/studio_action_label.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/compact_switch.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/administration_repository.dart';
import '../../services/mcp_error.dart';
import '../../services/ws_client.dart';
import 'admin_widgets.dart';

class AdminConnectorsPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminConnectorsPage({super.key, required this.profile});
  @override
  State<AdminConnectorsPage> createState() => _AdminConnectorsPageState();
}

class _AdminConnectorsPageState extends State<AdminConnectorsPage> {
  late final _profile = widget.profile;
  bool _busy = false;
  Future<void> _toggle(
    Map<String, dynamic> row,
    bool value,
    VoidCallback refresh,
  ) async {
    setState(() => _busy = true);
    try {
      final name = row['name'] as String;
      await _profile.write(
        'PUT',
        'mcp/servers/${Uri.encodeComponent(name)}/enabled',
        {'enabled': value},
      );
      final rows = administrationRows(
        (await _profile.read('mcp/servers'))['servers'],
      );
      if (rows.where((r) => r['name'] == name).firstOrNull?['enabled'] !=
          value) {
        throw const AdministrationFailure(
          'Connector setting could not be confirmed.',
        );
      }
      refresh();
      if (mounted) {
        adminMessage(
          context,
          'Saved for new sessions. Reload server connectors to apply to existing sessions.',
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
    title: 'MCP connectors',
    scope: _profile.label,
    child: AdminLoad(
      load: () => _profile.read('mcp/servers'),
      builder: (context, data, refresh) {
        final rows = administrationRows(data['servers']);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AdminNotice(
              'Connector settings belong to this profile. Connection status may be unavailable until a session connects.',
            ),
            TextButton(
              onPressed: _busy ? null : refresh,
              child: const Text('Refresh'),
            ),
            if (rows.isEmpty)
              const AdminNotice(
                'No MCP connectors configured for this profile.',
              ),
            AdminReloadConnectorsButton(server: _profile.server),
            AdminGroup(
              children: [
                for (final row in rows)
                  ListTile(
                    minTileHeight: 56,
                    minVerticalPadding: 4,
                    horizontalTitleGap: 12,
                    title: Text('${row['name']}'),
                    subtitle: Text(
                      '${row['transport'] ?? 'Configured connector'}',
                    ),
                    trailing: CompactSwitch(
                      semanticLabel: 'Enable ${row['name']}',
                      value: row['enabled'] != false,
                      onChanged: _busy ? null : (v) => _toggle(row, v, refresh),
                    ),
                    onTap: () async {
                      await adminPush(
                        context,
                        AdminConnectorDetail(profile: _profile, row: row),
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

class AdminConnectorDetail extends StatefulWidget {
  final ProfileAdministration profile;
  final Map<String, dynamic> row;
  const AdminConnectorDetail({
    super.key,
    required this.profile,
    required this.row,
  });
  @override
  State<AdminConnectorDetail> createState() => _AdminConnectorDetailState();
}

class _AdminConnectorDetailState extends State<AdminConnectorDetail> {
  late final _profile = widget.profile;
  late final _name = widget.row['name'] as String;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _probe;
  String _status = 'No runtime status available';
  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final result = await _profile.rpc('mcp.servers.status');
      final row = administrationRows(
        result['servers'],
      ).where((r) => r['name'] == _name).firstOrNull;
      if (mounted && row?['status'] is String) {
        setState(() => _status = row!['status'] as String);
      }
    } catch (_) {
      /* Configuration remains readable without the RPC sidecar. */
    }
  }

  Future<void> _test() async {
    if (!await adminConfirm(
      context,
      'Test $_name?',
      'This connects to the configured service or starts its server process to inspect capabilities.',
      action: 'Test',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _probe = null;
    });
    try {
      final result = await _profile.write(
        'POST',
        'mcp/servers/${Uri.encodeComponent(_name)}/test',
      );
      if (result['ok'] != true) {
        throw const AdministrationFailure('Connector test failed.');
      }
      if (mounted) setState(() => _probe = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = mcpErrorMessage(
            e is AdministrationFailure ? e.serverError : null,
            summary: 'Connection test failed.',
          ),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove() async {
    if (!await adminConfirm(
      context,
      'Remove $_name?',
      'Remove this connector configuration from ${_profile.name}. Existing sessions may retain their loaded tools.',
      action: 'Remove',
    )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _profile.write(
        'DELETE',
        'mcp/servers/${Uri.encodeComponent(_name)}',
      );
      final rows = administrationRows(
        (await _profile.read('mcp/servers'))['servers'],
      );
      if (rows.any((r) => r['name'] == _name)) {
        throw const AdministrationFailure('Removal could not be confirmed.');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: _name,
    scope: _profile.label,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_status),
        const AdminNotice(
          'Cached observation. Test performs a new connection.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) AdminNotice.error(_error!),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _test,
              child: const Text('Test connection'),
            ),
            if (widget.row['auth'] == 'oauth')
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => adminPush(
                        context,
                        AdminMcpSignIn(profile: _profile, name: _name),
                      ),
                child: const Text('Sign in'),
              ),
          ],
        ),
        if (_probe != null) ...[
          AdminNotice(
            'Test succeeded · ${_probe!['prompts'] ?? 0} prompts · ${_probe!['resources'] ?? 0} resources',
          ),
          for (final tool in administrationRows(_probe!['tools']))
            ListTile(
              title: Text('${tool['name']}'),
              subtitle: Text('${tool['description'] ?? ''}'),
            ),
        ],
        const AdminNotice(
          'Per-tool access changes are read only until the server supports safe concurrent updates.',
        ),
        TextButton(
          onPressed: _busy ? null : _remove,
          child: const Text('Remove connector'),
        ),
      ],
    ),
  );
}

class AdminMcpSignIn extends StatefulWidget {
  final ProfileAdministration profile;
  final String name;
  const AdminMcpSignIn({super.key, required this.profile, required this.name});
  @override
  State<AdminMcpSignIn> createState() => _AdminMcpSignInState();
}

class _AdminMcpSignInState extends State<AdminMcpSignIn> {
  Map<String, dynamic>? _flow;
  String? _error;
  bool _busy = false;
  bool _leave = false;
  Timer? _timer;
  bool get _pending =>
      _flow != null &&
      !{'approved', 'error', 'expired'}.contains(_flow!['status']);
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.profile.write(
        'POST',
        'mcp/servers/${Uri.encodeComponent(widget.name)}/auth',
      );
      if (result['flow_id'] is! String) {
        throw const AdministrationFailure(
          'Sign-in start could not be confirmed.',
        );
      }
      if (!mounted) return;
      setState(() => _flow = result);
      if (_pending) _timer = Timer(const Duration(seconds: 3), _poll);
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _poll() async {
    if (!_pending || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.profile.server.read(
        'mcp/oauth/flows/${Uri.encodeComponent(_flow!['flow_id'] as String)}',
      );
      if (!mounted) return;
      setState(() {
        _flow = result;
        _error = null;
      });
      if (_pending) _timer = Timer(const Duration(seconds: 3), _poll);
    } catch (e) {
      if (mounted) setState(() => _error = administrationError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _close() async {
    if (_busy) return;
    _timer?.cancel();
    if (_pending) {
      setState(() => _busy = true);
      try {
        await widget.profile.server.write(
          'DELETE',
          'mcp/oauth/flows/${Uri.encodeComponent(_flow!['flow_id'] as String)}',
        );
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'Cancellation was not confirmed. Retry before closing.';
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leave || (!_pending && !_busy),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: AdminPage(
      title: 'Sign in to ${widget.name}',
      scope: widget.profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AdminNotice(
            'Sign-in opens in your browser and returns to the configured server callback. That address must be reachable from your phone.',
          ),
          if (_error != null) AdminNotice.error(_error!),
          if (_flow == null)
            FilledButton(
              onPressed: _busy ? null : _start,
              child: const Text('Start sign-in'),
            ),
          if (_flow != null) ...[
            Text('Status: ${_flow!['status']}'),
            if (_flow!['status'] == 'error')
              AdminNotice.error(
                mcpErrorMessage(
                  _flow!['error'],
                  summary: 'Sign-in did not complete.',
                ),
              ),
            if (_pending) ...[
              FilledButton(
                onPressed: () async {
                  final url = Uri.tryParse(
                    '${_flow!['authorization_url'] ?? ''}',
                  );
                  if (url != null && {'http', 'https'}.contains(url.scheme)) {
                    final opened = await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && mounted) {
                      setState(
                        () => _error = 'Could not open the sign-in page.',
                      );
                    }
                  }
                },
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

class AdminPluginsPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminPluginsPage({super.key, required this.profile});
  @override
  State<AdminPluginsPage> createState() => _AdminPluginsPageState();
}

class _AdminPluginsPageState extends State<AdminPluginsPage> {
  bool _busy = false;
  Future<void> _toggle(
    Map<String, dynamic> row,
    bool enabled,
    VoidCallback refresh,
  ) async {
    setState(() => _busy = true);
    try {
      await widget.profile.rpc('plugins.manage', {
        'action': 'toggle',
        'key': row['key'],
        'enable': enabled,
      }, true);
      final rows = administrationRows(
        (await widget.profile.rpc('plugins.manage', {
          'action': 'list',
        }))['plugins'],
      );
      final after = rows.where((r) => r['key'] == row['key']).firstOrNull;
      if (after == null || (after['status'] == 'enabled') != enabled) {
        throw const AdministrationFailure(
          'Plugin setting could not be confirmed.',
        );
      }
      refresh();
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
    title: 'Agent plugins',
    scope: widget.profile.label,
    child: AdminLoad(
      load: () => widget.profile.rpc('plugins.manage', {'action': 'list'}),
      builder: (context, data, refresh) {
        final rows = administrationRows(data['plugins']);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AdminNotice(
              'Backend capabilities for this profile. Desktop plugin screens are not Android screens.',
            ),
            if (rows.isEmpty) const AdminNotice('No agent plugins reported.'),
            AdminGroup(
              children: [
                for (final row in rows)
                  CompactSwitchListTile(
                    title: Text('${row['name']}'),
                    subtitle: Text(
                      '${row['source']} · ${row['status']}\n${row['description'] ?? ''}',
                    ),
                    value: row['status'] == 'enabled',
                    onChanged: _busy ? null : (v) => _toggle(row, v, refresh),
                  ),
              ],
            ),
            TextButton(
              onPressed: _busy ? null : refresh,
              child: const Text('Refresh'),
            ),
          ],
        );
      },
    ),
  );
}

class AdminReloadConnectorsButton extends StatefulWidget {
  final AdministrationRepository server;
  const AdminReloadConnectorsButton({super.key, required this.server});
  @override
  State<AdminReloadConnectorsButton> createState() =>
      _AdminReloadConnectorsButtonState();
}

class _AdminReloadConnectorsButtonState
    extends State<AdminReloadConnectorsButton> {
  bool _busy = false;
  Future<void> _reload() async {
    if (!await adminConfirm(
      context,
      'Reload server connectors?',
      'Reconnect MCP tools for all profiles on this server. Existing sessions reload their tools; their next message may resend the full conversation to the model.',
      action: 'Reload',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      // This RPC is process-wide; default here owns transport, not the operation.
      final gateway = widget.server.gateway('default');
      await gateway.connect();
      var result = await gateway.reloadMcp();
      if (result['status'] == 'confirm_required') {
        if (!mounted ||
            !await adminConfirm(
              context,
              'Confirm connector reload',
              '${result['message'] ?? 'The next message may resend full input tokens.'}',
              action: 'Reload',
            )) {
          return;
        }
        result = await gateway.reloadMcp(confirm: true);
      }
      if (result['status'] != 'reloaded') {
        throw const AdministrationFailure(
          'Connector reload could not be confirmed.',
        );
      }
      if (mounted) adminMessage(context, 'Server connectors reloaded.');
    } catch (e) {
      if (mounted) {
        final message = switch (e) {
          JsonRpcError(reason: 'request_timeout') || TimeoutException() =>
            'Connector reload timed out. It may still be running on the server. Check connector status before retrying.',
          JsonRpcError(reason: 'connection_closed') =>
            'The connection closed before reload could be confirmed. Reconnect and check connector status before retrying.',
          JsonRpcError() => mcpErrorMessage(
            e.message,
            summary: 'Connector reload failed.',
          ),
          AdministrationFailure() => e.message,
          _ =>
            'Connector reload could not be confirmed. Check the server connection before retrying.',
        };
        adminMessage(context, message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: _busy ? null : _reload,
    child: StudioActionLabel('Reload server connectors', busy: _busy),
  );
}
