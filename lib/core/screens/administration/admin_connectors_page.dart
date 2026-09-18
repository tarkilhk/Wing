import '../../widgets/studio_action_label.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/compact_switch.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/administration_repository.dart';
import '../../services/mcp_error.dart';
import '../../services/mcp_oauth.dart';
import '../../services/ws_client.dart';
import '../../theme/wing_theme.dart';
import 'admin_widgets.dart';
import 'admin_mcp_setup_page.dart';

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
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final row = await Navigator.of(context)
                          .push<Map<String, dynamic>>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AdminMcpSetupPage(profile: _profile),
                            ),
                          );
                      refresh();
                      if (context.mounted && row != null) {
                        await adminPush(
                          context,
                          AdminConnectorDetail(
                            profile: _profile,
                            row: row,
                            signInOnOpen: row['auth'] == 'oauth',
                          ),
                        );
                        refresh();
                      }
                    },
              icon: const Icon(Icons.add),
              label: const Text('Add connector'),
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
  final bool signInOnOpen;
  const AdminConnectorDetail({
    super.key,
    required this.profile,
    required this.row,
    this.signInOnOpen = false,
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
  String? _testFailure;
  bool _testing = false;
  @override
  void initState() {
    super.initState();
    if (widget.signInOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _signIn(autoStart: true);
      });
    }
  }

  Future<void> _signIn({bool autoStart = false}) async {
    await adminPush(
      context,
      AdminMcpSignIn(profile: _profile, name: _name, autoStart: autoStart),
    );
    if (mounted) {
      setState(() {
        _error = null;
        _probe = null;
        _testFailure = null;
      });
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
      _testing = true;
      _testFailure = null;
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
          () => _testFailure = mcpErrorMessage(
            e is AdministrationFailure ? e.serverError : null,
            summary: 'Connection test failed.',
          ),
        );
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _testing = false;
      });
    }
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
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<WingTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? WingTokens.dark()
            : WingTokens.light());
    final tools = _probe == null
        ? <Map<String, dynamic>>[]
        : administrationRows(_probe!['tools']);
    final status = _testing
        ? 'Testing connection…'
        : _testFailure != null
        ? 'Test failed'
        : _probe != null
        ? 'Test passed'
        : 'Not tested';
    final color = _testFailure != null
        ? tokens.danger
        : _probe != null
        ? tokens.success
        : tokens.muted;
    return AdminPage(
      title: _name,
      scope: _profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  if (_testing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _testFailure != null
                          ? Icons.close
                          : _probe != null
                          ? Icons.check
                          : Icons.horizontal_rule,
                      size: 20,
                      color: color,
                    ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(status)),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _test,
                child: const Text('Test connection'),
              ),
              if (widget.row['auth'] == 'oauth')
                OutlinedButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('Sign in'),
                ),
            ],
          ),
          if (_testFailure != null)
            ExpansionTile(
              key: ValueKey(_testFailure),
              tilePadding: EdgeInsets.zero,
              title: const Text('Failure details'),
              children: [AdminNotice.error(_testFailure!)],
            ),
          if (_probe != null)
            ExpansionTile(
              key: ObjectKey(_probe),
              tilePadding: EdgeInsets.zero,
              title: Text('Available tools (${tools.length})'),
              children: [
                if (tools.isEmpty)
                  const AdminNotice('This connection returned no tools.'),
                for (final tool in tools)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${tool['name']}'),
                    subtitle: '${tool['description'] ?? ''}'.isEmpty
                        ? null
                        : Text('${tool['description']}'),
                  ),
              ],
            ),
          if (_error != null) AdminNotice.error(_error!),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _busy ? null : _remove,
            child: const Text('Remove connector'),
          ),
        ],
      ),
    );
  }
}

class AdminMcpSignIn extends StatefulWidget {
  final ProfileAdministration profile;
  final String name;
  final McpLoopbackFactory bindLoopback;
  final bool autoStart;
  final Future<bool> Function(Uri) openBrowser;
  const AdminMcpSignIn({
    super.key,
    required this.profile,
    required this.name,
    this.bindLoopback = McpLoopback.bind,
    this.autoStart = false,
    this.openBrowser = _launchMcpBrowser,
  });
  @override
  State<AdminMcpSignIn> createState() => _AdminMcpSignInState();
}

class _AdminMcpSignInState extends State<AdminMcpSignIn> {
  late final _flow = McpOAuth(
    profile: widget.profile,
    name: widget.name,
    bindLoopback: widget.bindLoopback,
  );
  final _callback = TextEditingController();
  bool _leave = false;
  String? _browserError;

  @override
  void initState() {
    super.initState();
    _flow.addListener(_changed);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  Future<void> _start() async {
    setState(() => _browserError = null);
    await _flow.start();
    if (mounted && _flow.authUrl != null && _flow.pending) await _openBrowser();
  }

  void _changed() {
    if (!mounted) return;
    if (_flow.callbackAccepted || !_flow.pending) _callback.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _flow.removeListener(_changed);
    _flow.dispose();
    _callback.dispose();
    super.dispose();
  }

  Future<void> _openBrowser() async {
    final url = _flow.authUrl;
    if (url == null) return;
    setState(() => _browserError = null);
    try {
      if (await widget.openBrowser(url)) return;
    } catch (_) {
      // Never include the authorization URL in diagnostics.
    }
    if (mounted) {
      setState(
        () => _browserError = 'Could not open the sign-in page. Try again.',
      );
    }
  }

  Future<void> _submit() async {
    final callback = _callback.text;
    _callback.clear();
    FocusScope.of(context).unfocus();
    await _flow.submitCallback(callback);
  }

  Future<void> _close() async {
    if (_flow.busy) return;
    if (!await _flow.cancel() || !mounted) return;
    setState(() => _leave = true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leave || (!_flow.pending && !_flow.busy),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: AdminPage(
      title: 'Sign in to ${_flow.name}',
      scope: _flow.profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_flow.pending && _flow.status != 'approved') ...[
            const AdminNotice(
              'Sign in through your browser. Your account access is saved on Hermes for this profile.',
            ),
            FilledButton(
              onPressed: _flow.busy ? null : _start,
              child: StudioActionLabel('Start sign-in', busy: _flow.busy),
            ),
          ],
          if (_flow.error != null) AdminNotice.error(_flow.error!),
          if (_browserError != null) AdminNotice.error(_browserError!),
          if (_flow.status == 'approved')
            const AdminNotice(
              'Signed in. Close this page and test the connector. Reload server connectors to update existing sessions.',
            ),
          if (_flow.pending) ...[
            if (_flow.authUrl != null && !_flow.callbackAccepted) ...[
              FilledButton(
                onPressed: _flow.busy ? null : _openBrowser,
                child: const Text('Open sign-in page'),
              ),
              AdminNotice(
                _flow.manualOnly
                    ? 'This connector uses its registered callback address. After approving access, copy the full address from your browser and paste it below, even if the page does not load.'
                    : 'Return to Wing after approval. If your browser stops at a localhost page, paste its full address below.',
              ),
              TextField(
                controller: _callback,
                enabled: !_flow.busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Callback URL'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _flow.busy ? null : _submit,
                child: StudioActionLabel('Complete sign-in', busy: _flow.busy),
              ),
            ],
            if (_flow.callbackAccepted)
              const AdminNotice(
                'Authorization received. Waiting for Hermes to finish sign-in.',
              ),
            TextButton(
              onPressed: _flow.busy ? null : _flow.poll,
              child: const Text('Check status'),
            ),
          ],
          if (!_flow.pending && _flow.status != 'approved')
            ExpansionTile(
              initiallyExpanded: _flow.terminalRequired,
              key: ValueKey(_flow.terminalRequired),
              tilePadding: EdgeInsets.zero,
              title: const Text('Other sign-in methods'),
              children: [
                const AdminNotice(
                  'Device-code sign-in and providers requiring a client metadata document need a terminal on your Hermes server. Run the command for this profile, then return here to test the connector.',
                ),
                SelectableText(
                  'hermes --profile ${_shellQuote(_flow.profile.name)} mcp login ${_shellQuote(_flow.name)}',
                ),
                const SizedBox(height: 12),
                const AdminNotice(
                  'For device-code sign-in, add --flow device. The provider must support it.',
                ),
              ],
            ),
          TextButton(
            onPressed: _flow.busy ? null : _close,
            child: Text(_flow.pending ? 'Cancel sign-in' : 'Close'),
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

// Profile and connector names are data even in a copyable terminal command.
String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

Future<bool> _launchMcpBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
