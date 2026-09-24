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
    String? example,
  }) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (largeText) ...[
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
          ],
          Semantics(
            label: largeText ? label : null,
            child: TextField(
              key: ValueKey('mcp-field-$label'),
              controller: controller,
              enabled: !_busy && !_uncertain,
              obscureText: secret,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: secret
                  ? const [AutofillHints.password]
                  : const <String>[],
              maxLines: lines,
              decoration: InputDecoration(
                labelText: largeText ? null : label,
                hintText: example,
              ),
            ),
          ),
          if (hint != null) _help(hint),
        ],
      ),
    );
  }

  Widget _help(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  String get _authenticationHelp => switch (_auth) {
    McpAuthentication.browser =>
      'For services that support browser sign-in (OAuth). After adding, sign in '
          'to your account and approve access. No API key to paste here.',
    McpAuthentication.bearer =>
      'For services that ask for a bearer token. Hermes sends your key in the '
          'Authorization header with the Bearer prefix.',
    McpAuthentication.none =>
      'For services that explicitly allow access without signing in or supplying '
          'a key. Hermes sends no authentication credentials.',
    McpAuthentication.headers =>
      'Headers are extra details sent with each request. Choose this when the '
          'service asks for a specific header, such as X-API-Key, or several '
          'headers. Copy the names and values from its setup instructions.',
  };

  String get _clientAuthenticationHelp => switch (_clientAuth) {
    'none' =>
      'Public client: identifies the app using its client ID, without a client secret.',
    'client_secret_post' =>
      'Secret in request: sends the client ID and secret in the token request body.',
    'client_secret_basic' =>
      'HTTP Basic: sends the client ID and secret in the token request’s Authorization header.',
    _ =>
      'Automatic: Hermes chooses the method. Change this only if the service specifies how to send a client secret.',
  };

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
            'Give this profile tools from another service using MCP. '
            'Credentials are saved on your Hermes server.',
          ),
          _field(
            _name,
            'Connector name',
            example: 'work-docs',
            hint:
                'A unique name in this profile, such as work-docs. '
                'Use 1–64 letters, numbers, dashes or underscores; start with a letter or number.',
          ),
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
          _help(
            _subprocess
                ? 'Runs an MCP program installed on your Hermes server, not on your phone.'
                : 'Connects Hermes to a service over the internet or your network using an MCP address.',
          ),
          const SizedBox(height: 16),
          _field(
            _address,
            _subprocess ? 'Command' : 'MCP address',
            example: _subprocess ? 'npx' : 'https://service.example/mcp',
            hint: _subprocess
                ? 'The executable name or full path on Hermes. Put its arguments in the next field.'
                : 'Paste the full MCP URL from the service’s setup instructions, '
                      'including https://. This is usually different from its website address.',
          ),
          if (_subprocess) ...[
            const AdminNotice(
              'Adding saves the settings. Test connection starts the program on Hermes.',
            ),
            _field(
              _args,
              'Arguments',
              lines: 3,
              hint:
                  'Optional startup options. Put each argument on its own line, '
                  'without shell quotes. For npx, -y and the package name go on separate lines.',
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
            _help(_authenticationHelp),
            const SizedBox(height: 16),
            if (_auth == McpAuthentication.bearer)
              _field(
                _token,
                'API key or bearer token',
                secret: true,
                hint:
                    'Paste only the key or token, without “Bearer ”. '
                    'If the service asks for a header such as X-API-Key, choose Custom headers.',
              ),
          ],
          if (_subprocess || _auth == McpAuthentication.headers) ...[
            if (_subprocess)
              const AdminNotice(
                'Environment variables give the program API keys or settings. '
                'Add them only if its setup instructions require them.',
              ),
            for (final (index, row) in _credentials.indexed) ...[
              _field(
                row.name,
                _subprocess
                    ? 'Environment variable ${index + 1}'
                    : 'Header name ${index + 1}',
                hint: _subprocess
                    ? 'The exact variable name requested by the program, such as SERVICE_API_KEY.'
                    : 'The exact header name requested by the service, such as X-API-Key.',
              ),
              _field(
                row.value,
                'Value ${index + 1}',
                secret: true,
                hint: _subprocess
                    ? 'The key or setting for this variable. Passed to the program when it starts.'
                    : 'Sent exactly as entered. Include any required prefix, such as Bearer, '
                          'if the service’s instructions show one.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy || _uncertain
                      ? null
                      : () => setState(() {
                          _credentials.remove(row);
                          row.dispose();
                        }),
                  child: Text(
                    _subprocess
                        ? 'Remove variable ${index + 1}'
                        : 'Remove header ${index + 1}',
                  ),
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
              subtitle: Text(
                _auth == McpAuthentication.browser
                    ? 'Optional OAuth and certificate settings'
                    : 'Optional certificate settings',
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: [
                if (_auth == McpAuthentication.browser) ...[
                  const AdminNotice(
                    'Leave these blank unless the service requires specific OAuth settings. '
                    'Hermes attempts automatic registration when supported.',
                  ),
                  _field(
                    _clientId,
                    'Client ID',
                    hint:
                        'Identifies an app registered with the service. '
                        'Use the ID from its developer settings if registration is required.',
                  ),
                  _field(
                    _clientSecret,
                    'Client secret',
                    secret: true,
                    hint:
                        'The secret paired with that client ID. Leave blank for a public client; '
                        'this is not your account password.',
                  ),
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
                  _help(_clientAuthenticationHelp),
                  const SizedBox(height: 16),
                  _field(
                    _scope,
                    'Scopes',
                    hint:
                        'Permissions to request, such as read or write. '
                        'Use the service’s exact scope names, separated by spaces. '
                        'Leave blank to use its defaults.',
                  ),
                  _field(
                    _redirect,
                    'Registered callback address',
                    hint:
                        'Where the browser returns after sign-in. Leave blank for Wing’s '
                        'automatic return address, or enter the exact URL registered with the service.',
                  ),
                ],
                const AdminNotice(
                  'Only needed if the service requires client certificates or a private '
                  'certificate authority. Files must already exist on Hermes, not on your phone.',
                ),
                _field(
                  _cert,
                  'Client certificate path',
                  hint:
                      'Path to a PEM certificate that identifies Hermes to the service.',
                ),
                _field(
                  _key,
                  'Private key path',
                  hint:
                      'Path to the certificate’s private key. Leave blank if the key '
                      'is included in the certificate file.',
                ),
                _field(
                  _ca,
                  'Custom CA path',
                  hint:
                      'Path to a PEM certificate authority (CA) bundle used to verify '
                      'the service. Leave blank to use the server’s trusted authorities.',
                ),
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
