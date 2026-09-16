import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'connection_manager.dart';
import 'ws_client.dart';

/// Only failures that can recover without changing settings are retried.
bool isTemporaryWorkspaceFailure(Object error) {
  if (error is HandshakeException || error is TlsException) return false;
  if (error is WebSocketChannelException && error.inner != null) {
    return isTemporaryWorkspaceFailure(error.inner!);
  }
  return error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException ||
      error is WebSocketException ||
      error is JsonRpcError &&
          {'connection_closed', 'request_timeout'}.contains(error.reason) ||
      error is DashboardHttpException &&
          (error.statusCode == 408 ||
              error.statusCode == 429 ||
              error.statusCode >= 500 && error.statusCode <= 599);
}

String workspaceFailureMessage(Object error) {
  if (error is DashboardHttpException) {
    if (error.statusCode == 401) {
      return 'Sign-in was rejected. Check this connection’s sign-in settings.';
    }
    if (error.statusCode == 403) {
      return 'Access was denied. Check this connection’s access settings.';
    }
  }
  if (error is HandshakeException || error is TlsException) {
    return 'The server’s certificate could not be verified.';
  }
  return 'Couldn’t open this workspace. Check the connection settings and try again.';
}
