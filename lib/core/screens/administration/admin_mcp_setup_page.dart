import 'package:flutter/material.dart';

import '../../services/administration_repository.dart';
import '../../services/mcp_setup.dart';
import '../../widgets/studio_action_label.dart';
import '../../widgets/studio_select.dart';
import 'admin_widgets.dart';

class AdminMcpSetupPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminMcpSetupPage({super.key, required this.profile});

  @override
  State<AdminMcpSetupPage> createState() => _AdminMcpSetupPageState();
}

class _CredentialFields {
  final name = TextEditingController();
  final value = TextEditingController();
  void dispose() {
    name.dispose();
    value.dispose();
  }
}

class _AdminMcpSetupPageState extends State<AdminMcpSetupPage> {
  late final _profile = widget.profile;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _args = TextEditingController();
  final _token = TextEditingController();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _scope = TextEditingController();
  final _redirect = TextEditingController();
  final _cert = TextEditingController();
  final _key = TextEditingController();
  final _ca = TextEditingController();
  final _credentials = <_CredentialFields>[];
  bool _subprocess = false;
  bool _busy = false;
  bool _uncertain = false;
  McpAuthentication _auth = McpAuthentication.browser;
  String? _error;
  String _clientAuth = '';

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _args,
      _token,
      _clientId,
      _clientSecret,
      _scope,
      _redirect,
      _cert,
      _key,
      _ca,
    ]) {
      controller.dispose();
    }
    for (final row in _credentials) {
      row.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      enabled: !_busy && !_uncertain,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 6,
      ),
    ),
  );

  void _useAspire() {
    setState(() {
      for (final controller in [
        _token,
        _clientId,
        _clientSecret,
        _scope,
        _redirect,
        _cert,
        _key,
        _ca,
      ]) {
        controller.clear();
      }
      _clientAuth = '';
      _subprocess = false;
      _auth = McpAuthentication.browser;
      _name.text = 'aspire';
      _address.text = 'https://aspire-mcp.aspireapp.com/mcp';
    });
  }

  Future<void> _save() async {
    final activeCredentials = _subprocess || _auth == McpAuthentication.headers;
    final credentials = <String, String>{};
    for (final row
        in activeCredentials ? _credentials : <_CredentialFields>[]) {
      final name = row.name.text.trim();
      if (credentials.containsKey(name) ||
          (!_subprocess &&
              credentials.keys.any(
                (key) => key.toLowerCase() == name.toLowerCase(),
              ))) {
        setState(() => _error = 'Each credential needs a different name.');
        return;
      }
      credentials[name] = row.value.text;
    }
    final setup = McpSetup(
      name: _name.text.trim(),
      address: _address.text.trim(),
      subprocess: _subprocess,
      arguments: _args.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      authentication: _auth,
      token: _token.text.trim(),
      credentials: credentials,
      clientId: _clientId.text.trim(),
      clientSecret: _clientSecret.text,
      tokenEndpointAuthMethod: _clientAuth,
      scope: _scope.text.trim(),
      redirect: _redirect.text.trim(),
      clientCert: _cert.text.trim(),
      clientKey: _key.text.trim(),
      caPath: _ca.text.trim(),
    );
    try {
      setup.validate();
    } catch (error) {
      setState(
        () =>
            _error = mcpOperationError(error, 'Check the connector settings.'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await setup.save(_profile);
      if (mounted) Navigator.pop(context, row);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = mcpOperationError(
            error,
            'Connector setup did not complete.',
          );
          // A lost acknowledgement may have persisted credentials/config. Do not
          // blindly replay a multi-operation creation with the same name.
          _uncertain = error is McpSetupUnconfirmed;
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
      title: 'Add MCP connector',
      scope: _profile.label,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AdminNotice(
            'Connect a service to this profile. Credentials are saved on Hermes.',
          ),
          if (!_subprocess)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy || _uncertain ? null : _useAspire,
                child: const Text('Use Aspire settings'),
              ),
            ),
          _field(_name, 'Connector name'),
          StudioSelect<bool>(
            key: ValueKey('transport-$_subprocess'),
            label: 'Connection',
            value: _subprocess,
            options: const [
              (value: false, label: 'Remote service'),
              (value: true, label: 'Program on Hermes'),
            ],
            onChanged: _busy || _uncertain
                ? null
                : (value) => setState(() {
                    _subprocess = value ?? false;
                    _address.clear();
                  }),
          ),
          const SizedBox(height: 16),
          _field(_address, _subprocess ? 'Command' : 'MCP address'),
          if (_subprocess) ...[
            const AdminNotice(
              'The program must be installed on your Hermes server. Adding it does not run it; testing starts the program.',
            ),
            _field(
              _args,
              'Arguments',
              lines: 3,
              hint: 'One argument per line; no shell quoting.',
            ),
          ] else ...[
            StudioSelect<McpAuthentication>(
              key: ValueKey('auth-$_auth'),
              label: 'Authentication',
              value: _auth,
              options: const [
                (value: McpAuthentication.browser, label: 'Browser sign-in'),
                (
                  value: McpAuthentication.bearer,
                  label: 'API key / bearer token',
                ),
                (value: McpAuthentication.none, label: 'No authentication'),
                (value: McpAuthentication.headers, label: 'Custom headers'),
              ],
              onChanged: _busy || _uncertain
                  ? null
                  : (value) => setState(() => _auth = value!),
            ),
            const SizedBox(height: 16),
            if (_auth == McpAuthentication.browser)
              const AdminNotice(
                'Sign in through your browser after adding the connector. Your Hermes server can stay private.',
              ),
            if (_auth == McpAuthentication.bearer)
              _field(_token, 'API key or bearer token', secret: true),
          ],
          if (_subprocess || _auth == McpAuthentication.headers) ...[
            for (final (index, row) in _credentials.indexed) ...[
              _field(
                row.name,
                _subprocess
                    ? 'Environment variable ${index + 1}'
                    : 'Header name ${index + 1}',
              ),
              _field(row.value, 'Value ${index + 1}', secret: true),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy || _uncertain
                      ? null
                      : () => setState(() {
                          _credentials.remove(row);
                          row.dispose();
                        }),
                  child: Text('Remove credential ${index + 1}'),
                ),
              ),
            ],
            OutlinedButton(
              onPressed: _busy || _uncertain
                  ? null
                  : () => setState(() => _credentials.add(_CredentialFields())),
              child: Text(
                _subprocess ? 'Add environment variable' : 'Add header',
              ),
            ),
          ],
          if (!_subprocess)
            ExpansionTile(
              title: const Text('Advanced'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: [
                if (_auth == McpAuthentication.browser) ...[
                  const AdminNotice(
                    'Only fill these when the provider requires a registered OAuth client. Otherwise Hermes handles registration.',
                  ),
                  _field(_clientId, 'Client ID'),
                  _field(_clientSecret, 'Client secret', secret: true),
                  StudioSelect<String>(
                    key: ValueKey(_clientAuth),
                    label: 'Client authentication',
                    value: _clientAuth,
                    options: const [
                      (value: '', label: 'Automatic'),
                      (value: 'none', label: 'Public client'),
                      (value: 'client_secret_post', label: 'Secret in request'),
                      (value: 'client_secret_basic', label: 'HTTP Basic'),
                    ],
                    onChanged: _busy || _uncertain
                        ? null
                        : (value) => setState(() => _clientAuth = value!),
                  ),
                  const SizedBox(height: 16),
                  _field(_scope, 'Scopes'),
                  _field(
                    _redirect,
                    'Registered callback address',
                    hint:
                        'Optional. Must match the address approved by the provider.',
                  ),
                ],
                const AdminNotice(
                  'Certificate files must already exist on Hermes.',
                ),
                _field(_cert, 'Client certificate path'),
                _field(_key, 'Private key path'),
                _field(_ca, 'Custom CA path'),
              ],
            ),
          if (_error != null) AdminNotice.error(_error!),
          if (_uncertain) ...[
            const AdminNotice(
              'Some settings may have been saved. Return to the connector list and refresh before trying again.',
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Return to connectors'),
            ),
          ] else
            FilledButton(
              onPressed: _busy ? null : _save,
              child: StudioActionLabel(
                !_subprocess && _auth == McpAuthentication.browser
                    ? 'Add and sign in'
                    : 'Add connector',
                busy: _busy,
              ),
            ),
        ],
      ),
    ),
  );
}
