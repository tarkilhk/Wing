import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class CloudAccessException implements Exception {
  const CloudAccessException(this.message, {this.signInRequired = false});
  final String message;
  final bool signInRequired;
  @override
  String toString() => message;
}

/// One instance-bound grant. All clients for a saved connection share this
/// object so a rotating refresh token is exchanged only once.
class DashboardOAuthSession {
  DashboardOAuthSession({
    required this.id,
    required this.baseUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.persist,
    http.Client Function()? createClient,
  }) : _createClient = createClient ?? http.Client.new;

  final String id;
  final String baseUrl;
  String accessToken;
  String refreshToken;
  DateTime expiresAt;
  Future<void> Function()? persist;
  final http.Client Function() _createClient;
  Future<void>? _refreshing;
  bool _needsSave = false;

  static String canonicalBase(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Cloud dashboards must use an HTTPS address.',
      );
    }
    return uri
        .replace(
          port: uri.port == 443 ? null : uri.port,
          path: uri.path.replaceAll(RegExp(r'/+$'), ''),
        )
        .toString();
  }

  factory DashboardOAuthSession.fromMap(Map<String, dynamic> map) {
    final session = DashboardOAuthSession(
      id: map['id'] as String,
      baseUrl: canonicalBase(map['base_url'] as String),
      accessToken: map['access_token'] as String,
      refreshToken: map['refresh_token'] as String,
      expiresAt: DateTime.parse(map['expires_at'] as String).toUtc(),
    );
    if (session.id.isEmpty ||
        session.accessToken.isEmpty ||
        session.refreshToken.isEmpty) {
      throw const FormatException();
    }
    return session;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'base_url': baseUrl,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.toIso8601String(),
  };

  static DateTime tokenExpiry(Object? value) {
    if (value is num && value.isFinite && value > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      );
    }
    throw const FormatException('Missing session expiry.');
  }

  void invalidate() =>
      expiresAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  Future<String> bearerFor(String destination) async {
    if (canonicalBase(destination) != baseUrl) {
      throw const CloudAccessException(
        'This sign-in belongs to a different Hermes instance.',
      );
    }
    if (_needsSave) {
      await persist?.call();
      _needsSave = false;
    }
    if (!expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      final pending = _refreshing ??= _refresh();
      try {
        await pending;
      } finally {
        if (identical(_refreshing, pending)) _refreshing = null;
      }
    }
    return accessToken;
  }

  Future<void> _refresh() async {
    final client = _createClient();
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/auth/native/refresh'))
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              'provider': 'nous',
              'refresh_token': refreshToken,
            });
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const CloudAccessException(
          'Sign in to Hermes Cloud again from this connection’s settings.',
          signInRequired: true,
        );
      }
      if (response.statusCode != 200) {
        throw const CloudAccessException(
          'Couldn’t renew this Hermes sign-in. Try again.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final access = data['access_token'] as String;
      final refresh = data['refresh_token'] as String;
      final expiry = tokenExpiry(data['expires_at']);
      if (data['provider'] != 'nous' || access.isEmpty || refresh.isEmpty) {
        throw const FormatException();
      }
      accessToken = access;
      refreshToken = refresh;
      expiresAt = expiry;
      // Retain rotated tokens even if storage is temporarily unavailable. Never
      // replay the old refresh token; retry persisting before the next request.
      _needsSave = true;
      await persist?.call();
      _needsSave = false;
    } on CloudAccessException {
      rethrow;
    } catch (_) {
      throw const CloudAccessException(
        'Couldn’t renew or save this Hermes sign-in. Try again.',
      );
    } finally {
      client.close();
    }
  }
}
