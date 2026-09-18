import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'administration_repository.dart';
import 'mcp_error.dart';
import 'ws_client.dart';

typedef McpLoopbackFactory =
    Future<McpLoopback> Function(
      Uri redirect,
      Future<bool> Function(Uri) receive,
    );

/// A listener on this device only. Callback values never enter logs or storage.
class McpLoopback {
  final Uri redirectUri;
  final Future<void> Function() close;
  McpLoopback({required this.redirectUri, required this.close});

  static Future<McpLoopback> bind(
    Uri redirect,
    Future<bool> Function(Uri) receive,
  ) async {
    final address = redirect.host == '::1'
        ? InternetAddress.loopbackIPv6
        : InternetAddress.loopbackIPv4;
    final server = await HttpServer.bind(address, redirect.port);
    server.listen((request) async {
      try {
        final accepted =
            request.method == 'GET' &&
            request.uri.path == redirect.path &&
            await receive(redirect.resolveUri(request.uri));
        request.response
          ..statusCode = accepted ? 200 : 400
          ..headers.contentType = ContentType.html
          ..headers.set('Cache-Control', 'no-store')
          ..headers.set('Referrer-Policy', 'no-referrer')
          ..write(
            accepted
                ? '<h1>Authorization received</h1><p>Return to Wing to check sign-in.</p>'
                : '<h1>Callback not accepted</h1><p>Return to Wing and check sign-in.</p>',
          );
        await request.response.close();
      } catch (_) {
        // Browser disconnects must not expose the callback in exception logs.
        request.response.close().ignore();
      }
    });
    return McpLoopback(
      redirectUri: redirect,
      close: () async {
        await server.close(force: true);
      },
    );
  }
}

/// One profile-owned PKCE flow. Hermes owns state/PKCE validation and tokens;
/// Wing captures only the browser callback and relays it through the stock RPC.
class McpOAuth extends ChangeNotifier {
  final ProfileAdministration profile;
  final String name;
  final McpLoopbackFactory bindLoopback;
  late final _gateway = profile.gateway;
  McpLoopback? _listener;
  Timer? _timer;
  bool _disposed = false;
  bool _polling = false;
  bool _closing = false;
  String? _sessionId;
  String? _state;
  Uri? authUrl;
  Uri? _callbackUri;
  bool manualOnly = false;
  bool terminalRequired = false;
  String status = 'idle';
  String? error;
  bool busy = false;
  bool callbackAccepted = false;
  bool get pending => _sessionId != null && status == 'pending';

  McpOAuth({
    required this.profile,
    required this.name,
    this.bindLoopback = McpLoopback.bind,
  });

  /// Stable per connector: repeated login must not change a DCR callback port.
  /// Explicit provider-approved redirect_uri settings take precedence.
  Uri get defaultCallback {
    var hash = 2166136261;
    for (final unit
        in '${profile.server.connectionId}/${profile.name}/$name'.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xffffffff;
    }
    return Uri.parse('http://127.0.0.1:${20000 + hash % 40000}/callback');
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _request(
    String action, [
    Map<String, dynamic> params = const {},
  ]) async {
    await _gateway.connect();
    final result = await _gateway.call('mcp.servers.oauth.$action', {
      'name': name,
      ...params,
    });
    if (result['ok'] != true) {
      throw AdministrationFailure(
        mcpErrorMessage(
          result['error_message'],
          summary: 'Sign-in could not be completed.',
        ),
      );
    }
    return result;
  }

  String _failure(Object failure) {
    if (failure is JsonRpcError) {
      if (failure.code == -32601) {
        return 'This Hermes server does not support loopback sign-in. Update Hermes before trying again.';
      }
      final detail = failure.message.toLowerCase();
      if (detail.contains('device authorization') ||
          detail.contains('--flow device')) {
        terminalRequired = true;
        return 'This service needs device-code sign-in. Use the terminal instructions below, then test the connector here.';
      }
      if (detail.contains('redirect_uri') ||
          detail.contains('approved callback')) {
        return mcpErrorMessage(
          failure.message,
          summary:
              'The service rejected the callback address. Check the provider’s registered-client settings. Pasting a URL cannot bypass this restriction.',
        );
      }
      if (detail.contains('timed out waiting for mcp authorization url')) {
        return 'Hermes did not return a sign-in page. Test the connector to check whether it is already authorized before retrying.';
      }
      return mcpErrorMessage(
        failure.message,
        summary: 'Sign-in did not complete.',
      );
    }
    if (failure is AdministrationFailure) return failure.message;
    if (failure is SocketException) {
      return 'Could not open the callback on this phone. Close other sign-in attempts and try again.';
    }
    return 'Sign-in could not be confirmed. Check the connection and try again.';
  }

  Future<void> start() async {
    if (busy || pending || _disposed) return;
    _sessionId = null;
    authUrl = null;
    callbackAccepted = false;
    terminalRequired = false;
    busy = true;
    error = null;
    _changed();
    try {
      await profile.requireProfile();
      if (_disposed) return;
      // Read only the settings needed for this flow; never retain/log raw config.
      final config = await profile.config();
      final servers = config['mcp_servers'];
      final entry = servers is Map ? servers[name] : null;
      if (entry is! Map || entry['url'] is! String) {
        throw const AdministrationFailure(
          'This browser sign-in needs an existing remote connector. Refresh the connector list.',
        );
      }
      final oauth = entry['oauth'] is Map ? entry['oauth'] as Map : const {};
      if (oauth['flow'] == 'device') {
        terminalRequired = true;
        throw const AdministrationFailure(
          'This connector uses device-code sign-in. Complete it in a terminal on Hermes, then test the connection here.',
        );
      }
      final configured = oauth['redirect_uri'];
      final target = configured is String && configured.isNotEmpty
          ? Uri.tryParse(configured)
          : defaultCallback;
      if (target == null ||
          !{'http', 'https'}.contains(target.scheme) ||
          target.host.isEmpty ||
          target.userInfo.isNotEmpty ||
          target.hasQuery ||
          target.hasFragment) {
        throw const AdministrationFailure(
          'The connector has an invalid callback address. Correct its OAuth settings on Hermes before signing in.',
        );
      }
      _callbackUri = target;
      manualOnly =
          !(target.scheme == 'http' &&
              {'127.0.0.1', 'localhost', '::1'}.contains(target.host) &&
              target.hasPort);
      if (!manualOnly) {
        _listener = await bindLoopback(
          target,
          (uri) => submitCallback(uri.toString()),
        );
      }
      if (_disposed) return;
      final result = await _request('start', {
        'client_redirect_uri': (manualOnly ? defaultCallback : _callbackUri!)
            .toString(),
      });
      final session = result['session_id'];
      if (session is! String || session.isEmpty) {
        throw const AdministrationFailure(
          'Sign-in start could not be confirmed.',
        );
      }
      _sessionId = session;
      status = 'pending';
      if (_disposed) {
        await _request('cancel', {'session_id': session});
        return;
      }
      final url = result['auth_url'] is String
          ? Uri.tryParse(result['auth_url'] as String)
          : null;
      if (result['flow'] != 'pkce' ||
          url == null ||
          !{'https', 'http'}.contains(url.scheme) ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          (url.queryParameters['state'] ?? '').isEmpty) {
        throw const AdministrationFailure(
          'Hermes returned an invalid sign-in link. Cancel this sign-in and try again.',
        );
      }
      if (url.queryParameters['redirect_uri'] != _callbackUri.toString()) {
        throw const AdministrationFailure(
          'Hermes returned a different callback address. Cancel this sign-in and check the connector’s OAuth settings.',
        );
      }
      authUrl = url;
      _state = url.queryParameters['state'];
      _schedulePoll();
    } catch (e) {
      error = _failure(e);
    } finally {
      if (_disposed || _sessionId == null) await _closeListener();
      busy = false;
      _changed();
    }
  }

  /// Full URLs only: reject a different listener, missing/duplicate parameters,
  /// wrong state, and replays before sending a code to the captured profile.
  Future<bool> submitCallback(String input) async {
    if (!pending || busy || callbackAccepted || _disposed) return false;
    final uri = Uri.tryParse(input.trim());
    final target = _callbackUri;
    final values = uri?.queryParametersAll;
    final valid =
        uri != null &&
        target != null &&
        uri.scheme == target.scheme &&
        uri.host == target.host &&
        uri.port == target.port &&
        uri.path == target.path &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        values != null &&
        ['code', 'state', 'error', 'iss'].every(
          (key) => !values.containsKey(key) || values[key]!.length == 1,
        ) &&
        uri.queryParameters['state'] == _state &&
        _state != null &&
        ((uri.queryParameters['code'] ?? '').isNotEmpty !=
            (uri.queryParameters['error'] ?? '').isNotEmpty);
    if (!valid) {
      error = 'Paste the complete callback URL from this sign-in attempt.';
      _changed();
      return false;
    }
    busy = true;
    error = null;
    _timer?.cancel();
    _changed();
    try {
      await _request('callback', {
        'session_id': _sessionId,
        for (final key in ['code', 'state', 'error', 'iss'])
          if (uri.queryParameters.containsKey(key))
            key: uri.queryParameters[key],
      });
      callbackAccepted = true;
      return true;
    } catch (e) {
      error = _failure(e);
      return false;
    } finally {
      busy = false;
      _changed();
      _schedulePoll();
    }
  }

  void _schedulePoll() {
    _timer?.cancel();
    if (pending && !_disposed && !_closing) {
      _timer = Timer(const Duration(seconds: 3), poll);
    }
  }

  Future<void> poll() async {
    if (!pending || busy || _polling || _disposed || _closing) return;
    _timer?.cancel();
    _polling = true;
    try {
      final result = await _request('poll', {'session_id': _sessionId});
      if (_disposed || _closing || !pending) return;
      if (!{'pending', 'approved', 'error'}.contains(result['status'])) {
        throw const AdministrationFailure(
          'Hermes returned an unknown sign-in status.',
        );
      }
      status = result['status'] as String;
      error = status == 'error'
          ? mcpErrorMessage(
              result['error_message'],
              summary: 'Sign-in did not complete.',
            )
          : null;
      if (!pending) await _closeListener();
      _schedulePoll();
    } catch (e) {
      if (!_closing) error = _failure(e);
    } finally {
      _polling = false;
      _changed();
    }
  }

  Future<bool> cancel() async {
    if (busy || _disposed) return false;
    if (!pending) return true;
    busy = true;
    _closing = true;
    _timer?.cancel();
    _changed();
    try {
      await _request('cancel', {'session_id': _sessionId});
      status = 'cancelled';
      await _closeListener();
      return true;
    } catch (_) {
      error = 'Cancellation was not confirmed. Retry before closing.';
      return false;
    } finally {
      busy = false;
      _closing = false;
      _changed();
    }
  }

  Future<void> _closeListener() async {
    final listener = _listener;
    _listener = null;
    _state = null;
    _callbackUri = null;
    if (listener != null) await listener.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (pending && !_closing) {
      _request('cancel', {'session_id': _sessionId}).ignore();
    }
    _closeListener().ignore();
    super.dispose();
  }
}
