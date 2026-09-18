import 'dart:math';
import 'administration_repository.dart';
import 'mcp_error.dart';
import 'ws_client.dart';

enum McpAuthentication { browser, bearer, none, headers }

class McpSetupUnconfirmed extends AdministrationFailure {
  const McpSetupUnconfirmed(super.message);
}

String mcpOperationError(Object error, String summary) =>
    mcpErrorMessage(switch (error) {
      AdministrationFailure(:final serverError, :final message) =>
        serverError ?? message,
      JsonRpcError(:final message) => message,
      _ => null,
    }, summary: summary);

/// New-connector provisioning only. Editing an existing auth mode would need
/// deletion semantics that stock deep-merge configuration writes do not offer.
class McpSetup {
  final String name;
  final String address;
  final bool subprocess;
  final List<String> arguments;
  final McpAuthentication authentication;
  final String token;
  final Map<String, String> credentials;
  final String clientId;
  final String clientSecret;
  final String tokenEndpointAuthMethod;
  final String scope;
  final String redirect;
  final String clientCert;
  final String clientKey;
  final String caPath;

  const McpSetup({
    required this.name,
    required this.address,
    this.subprocess = false,
    this.arguments = const [],
    this.authentication = McpAuthentication.browser,
    this.token = '',
    this.credentials = const {},
    this.clientId = '',
    this.clientSecret = '',
    this.tokenEndpointAuthMethod = '',
    this.scope = '',
    this.redirect = '',
    this.clientCert = '',
    this.clientKey = '',
    this.caPath = '',
  });

  void validate() {
    void require(bool valid, String reason) {
      if (!valid) throw AdministrationFailure(reason);
    }

    require(
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(name),
      'Use a connector name with letters, numbers, dashes or underscores.',
    );
    require(
      address.trim().isNotEmpty,
      subprocess ? 'Enter a command.' : 'Enter the MCP address.',
    );
    if (!subprocess) {
      final uri = Uri.tryParse(address);
      require(
        uri != null &&
            {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasFragment,
        'Enter an HTTP or HTTPS address without embedded credentials.',
      );
      if (authentication == McpAuthentication.bearer) {
        require(token.trim().isNotEmpty, 'Enter the API key or bearer token.');
      }
      if (authentication == McpAuthentication.headers) {
        require(
          credentials.isNotEmpty,
          'Add at least one authentication header.',
        );
      }
      require(
        {
          '',
          'none',
          'client_secret_post',
          'client_secret_basic',
        }.contains(tokenEndpointAuthMethod),
        'Choose a supported client authentication method.',
      );
      require(
        authentication != McpAuthentication.browser ||
            clientSecret.isEmpty ||
            clientId.isNotEmpty,
        'Enter the client ID for this client secret.',
      );
      if (authentication == McpAuthentication.browser && redirect.isNotEmpty) {
        final uri = Uri.tryParse(redirect);
        require(
          uri != null &&
              {'http', 'https'}.contains(uri.scheme) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              !uri.hasQuery &&
              !uri.hasFragment,
          'Enter the exact registered callback address without query parameters.',
        );
      }
      require(
        clientKey.isEmpty || clientCert.isNotEmpty,
        'Enter the certificate path for this private key.',
      );
    }
    final keyPattern = subprocess
        ? RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')
        : RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
    for (final entry in credentials.entries) {
      require(
        keyPattern.hasMatch(entry.key) &&
            entry.value.isNotEmpty &&
            (subprocess || !entry.value.contains(RegExp(r'[\r\n]'))),
        subprocess
            ? 'Enter a valid environment variable name and value.'
            : 'Enter a valid header name and value.',
      );
    }
  }

  Future<Map<String, dynamic>> save(ProfileAdministration profile) async {
    validate();
    final listing = await profile.rpc('mcp.servers.list');
    if (listing['servers'] is! List) {
      throw const AdministrationFailure(
        'Could not read the connector list. Refresh before adding a connector.',
      );
    }
    final existing = administrationRows(listing['servers']);
    if (existing.any((row) => row['name'] == name)) {
      throw const AdministrationFailure(
        'A connector with this name already exists. Open it from the connector list.',
      );
    }
    // Fresh names cannot rotate a credential owned by another connector or a
    // concurrent create. A failed create may leave unused profile credentials.
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join().toUpperCase();
    final prefix = 'MCP_WING_$suffix';
    final secrets = <String, String>{};
    String secret(String suffix, String value) {
      final key = '${prefix}_$suffix';
      secrets[key] = value;
      return '\${$key}';
    }

    final config = <String, dynamic>{
      if (subprocess) 'command': address else 'url': address,
      if (subprocess) 'args': arguments,
    };
    if (subprocess || authentication == McpAuthentication.headers) {
      var index = 0;
      config[subprocess ? 'env' : 'headers'] = {
        for (final entry in credentials.entries)
          entry.key: secret('VALUE_${index++}', entry.value),
      };
    }
    if (!subprocess && authentication == McpAuthentication.browser) {
      config['auth'] = 'oauth';
      config['oauth'] = {
        if (clientId.isNotEmpty) 'client_id': clientId,
        if (tokenEndpointAuthMethod.isNotEmpty)
          'token_endpoint_auth_method': tokenEndpointAuthMethod,
        if (clientSecret.isNotEmpty)
          'client_secret': secret('CLIENT_SECRET', clientSecret),
        if (scope.isNotEmpty) 'scope': scope,
        if (redirect.isNotEmpty) 'redirect_uri': redirect,
      };
    }
    if (!subprocess) {
      if (clientCert.isNotEmpty) config['client_cert'] = clientCert;
      if (clientKey.isNotEmpty) config['client_key'] = clientKey;
      if (caPath.isNotEmpty) config['ssl_verify'] = caPath;
    }
    try {
      // Do not put secrets into config.yaml; write profile .env references.
      for (final entry in secrets.entries) {
        await profile.write('PUT', 'env', {
          'key': entry.key,
          'value': entry.value,
        });
      }
      final result = await profile.rpc('mcp.servers.add', {
        'name': name,
        'config': config,
        if (!subprocess && authentication == McpAuthentication.bearer)
          'bearer_token': token,
      }, true);
      if (result['ok'] != true ||
          result['server'] is! Map ||
          (result['server'] as Map)['name'] != name) {
        throw const AdministrationFailure(
          'Save could not be confirmed. Refresh the connector list before retrying.',
        );
      }
      return Map<String, dynamic>.from(result['server'] as Map);
    } catch (error) {
      throw McpSetupUnconfirmed(
        mcpOperationError(error, 'Check the connector list before retrying.'),
      );
    }
  }
}
