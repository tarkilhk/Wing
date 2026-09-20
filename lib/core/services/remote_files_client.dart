import 'dart:typed_data';

import 'connection_manager.dart';
import 'desktop_gateway_client.dart';

class RemoteDirectory {
  final String path;
  final String? branch;

  const RemoteDirectory({required this.path, this.branch});
}

class RemoteFileEntry {
  final String name;
  final String path;
  final bool isDirectory;

  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  factory RemoteFileEntry.fromJson(Map<String, dynamic> json) =>
      RemoteFileEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDirectory: json['isDirectory'] == true,
      );
}

class RemoteTextPreview {
  final String path;
  final String text;
  final String language;
  final String mimeType;
  final int byteSize;
  final bool binary;
  final bool truncated;

  const RemoteTextPreview({
    required this.path,
    required this.text,
    required this.language,
    required this.mimeType,
    required this.byteSize,
    required this.binary,
    required this.truncated,
  });

  factory RemoteTextPreview.fromJson(Map<String, dynamic> json) =>
      RemoteTextPreview(
        path: json['path'] as String? ?? '',
        text: json['text'] as String? ?? '',
        language: json['language'] as String? ?? 'text',
        mimeType: json['mimeType'] as String? ?? 'text/plain',
        byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
        binary: json['binary'] == true,
        truncated: json['truncated'] == true,
      );
}

class RemoteFileDownload {
  final String filename;
  final Uint8List bytes;

  RemoteFileDownload({required this.filename, required List<int> bytes})
    : bytes = Uint8List.fromList(bytes);
}

abstract class RemoteFilesDataSource {
  Future<RemoteDirectory> defaultDirectory();
  Future<List<RemoteFileEntry>> listDirectory(String path);
  Future<RemoteTextPreview> readText(
    String path, {
    required String profileName,
    required String storedSessionId,
  });
  Future<RemoteFileDownload> download(
    String path, {
    required String profileName,
    required String storedSessionId,
  });
}

/// Binds remote file requests to the profile and saved chat that exposed them.
class OwnedRemoteFiles {
  final RemoteFilesDataSource source;
  final String profileName;
  final String storedSessionId;

  const OwnedRemoteFiles({
    required this.source,
    required this.profileName,
    required this.storedSessionId,
  });

  Future<RemoteTextPreview> readText(String path) => source.readText(
    path,
    profileName: profileName,
    storedSessionId: storedSessionId,
  );

  Future<RemoteFileDownload> download(String path) => source.download(
    path,
    profileName: profileName,
    storedSessionId: storedSessionId,
  );
}

class RemoteFilesClient implements RemoteFilesDataSource {
  static const defaultMaxDownloadBytes = 32 * 1024 * 1024;

  final DashboardClient dashboard;
  final int maxDownloadBytes;

  RemoteFilesClient({
    required this.dashboard,
    this.maxDownloadBytes = defaultMaxDownloadBytes,
  });

  factory RemoteFilesClient.fromConnection(SavedConnection connection) {
    final baseUri = Uri.parse(
      DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
    );
    return RemoteFilesClient(
      dashboard: DashboardClient(
        host: baseUri.host,
        port: baseUri.port,
        useHttps: baseUri.scheme == 'https',
        pathPrefix: baseUri.path == '/' ? '' : baseUri.path,
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
        dashboardOAuth: connection.dashboardOAuth,
        requiresOAuth: connection.isCloud,
        gatewayHeaders: connection.gatewayHeaders,
      ),
    );
  }

  @override
  Future<RemoteDirectory> defaultDirectory() async {
    final data = await dashboard.apiGet('fs/default-cwd');
    return RemoteDirectory(
      path: data['cwd'] as String? ?? '/',
      branch: data['branch'] as String?,
    );
  }

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async {
    final data = await dashboard.apiGet(
      'fs/list',
      queryParameters: {'path': path},
    );
    final error = data['error'] as String?;
    if (error != null && error.isNotEmpty) {
      throw Exception('Could not read directory: $error');
    }
    final entries = (data['entries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteFileEntry.fromJson)
        .toList();
    entries.sort(
      (left, right) => left.isDirectory == right.isDirectory
          ? left.name.toLowerCase().compareTo(right.name.toLowerCase())
          : left.isDirectory
          ? -1
          : 1,
    );
    return entries;
  }

  @override
  Future<RemoteTextPreview> readText(
    String path, {
    required String profileName,
    required String storedSessionId,
  }) async {
    final owner = _owner(profileName, storedSessionId);
    var previewPath = path;
    // Stock read-text has no session_id parameter. Resolve relative paths
    // against the originating session before calling it, just as desktop does.
    // Downloads resolve their own session cwd on the server.
    if (!_rootedPath.hasMatch(path)) {
      final session = await dashboard.apiGet(
        'sessions/${Uri.encodeComponent(owner['session_id']!)}',
        queryParameters: {'profile': owner['profile']!},
      );
      final cwd = session['cwd'] as String?;
      if (cwd == null || !_rootedPath.hasMatch(cwd)) {
        throw const DashboardHttpException(400, 'fs/read-text');
      }
      previewPath = '$cwd/$path';
    }
    final data = await dashboard.apiGet(
      'fs/read-text',
      queryParameters: {'path': previewPath, ...owner},
    );
    return RemoteTextPreview.fromJson(data);
  }

  static final _rootedPath = RegExp(r'^(?:/|~|[A-Za-z]:[\\/]|\\\\)');

  @override
  Future<RemoteFileDownload> download(
    String path, {
    required String profileName,
    required String storedSessionId,
  }) async {
    final owner = _owner(profileName, storedSessionId);
    final response = await dashboard.apiGetBytes(
      'fs/download',
      queryParameters: {'path': path, ...owner},
      maxBytes: maxDownloadBytes,
    );
    final disposition = response.headers['content-disposition'] ?? '';
    final encoded = RegExp(
      r'''filename\*=(?:UTF-8'')?([^;]+)''',
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1);
    final plain = RegExp(
      r'''filename=["']?([^"';]+)''',
      caseSensitive: false,
    ).firstMatch(disposition)?.group(1);
    return RemoteFileDownload(
      filename: _safeBasename(encoded ?? plain ?? path),
      bytes: response.bodyBytes,
    );
  }

  Map<String, String> _owner(String profileName, String storedSessionId) {
    final profile = profileName.trim();
    final session = storedSessionId.trim();
    if (profile.isEmpty || session.isEmpty) {
      throw ArgumentError('A profile and saved chat identity are required');
    }
    return {'profile': profile, 'session_id': session};
  }

  String _safeBasename(String value) {
    var decoded = value.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    try {
      decoded = Uri.decodeComponent(decoded);
    } on FormatException {
      // Keep the literal server name when percent encoding is malformed.
    }
    final name = decoded.split(RegExp(r'[\\/]')).last.trim();
    return name.isEmpty || name == '.' || name == '..' ? 'download' : name;
  }

  void close() => dashboard.close();
}
