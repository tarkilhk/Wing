import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/remote_files_client.dart';

class _StreamingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          [1, 2],
          [3],
        ]),
        200,
      );
}

void main() {
  DashboardClient dashboardWith(
    Future<http.Response> Function(http.Request request) handler,
  ) => DashboardClient(
    host: 'hermes.local',
    port: 9119,
    proxied: true,
    httpClient: MockClient(handler),
  );

  test('loads the default working directory', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/fs/default-cwd');
      return http.Response(
        jsonEncode({'cwd': '/srv/project', 'branch': 'main'}),
        200,
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final root = await client.defaultDirectory();

    expect(root.path, '/srv/project');
    expect(root.branch, 'main');
    client.close();
  });

  test('owned file access keeps the original profile and saved chat', () async {
    final requests = <http.Request>[];
    final dashboard = dashboardWith((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/read-text')) {
        return http.Response(
          jsonEncode({
            'path': request.url.queryParameters['path'],
            'text': 'contents',
          }),
          200,
        );
      }
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-disposition': 'attachment; filename=report.txt'},
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);
    final owned = OwnedRemoteFiles(
      source: client,
      profileName: 'original-profile',
      storedSessionId: 'original-chat',
    );

    await owned.readText('../exports/report.txt');
    await owned.download('../exports/report.txt');

    for (final request in requests) {
      expect(request.url.queryParameters, {
        'path': '../exports/report.txt',
        'profile': 'original-profile',
        'session_id': 'original-chat',
      });
    }
    client.close();
  });

  test('lists directories before files and preserves server paths', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.url.path, '/api/fs/list');
      expect(request.url.queryParameters['path'], '/srv/project');
      return http.Response(
        jsonEncode({
          'entries': [
            {
              'name': 'README.md',
              'path': '/srv/project/README.md',
              'isDirectory': false,
            },
            {'name': 'lib', 'path': '/srv/project/lib', 'isDirectory': true},
          ],
        }),
        200,
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final entries = await client.listDirectory('/srv/project');

    expect(entries.map((entry) => entry.name), ['lib', 'README.md']);
    expect(entries.first.isDirectory, isTrue);
    client.close();
  });

  test('reads a text preview with language and truncation metadata', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.url.path, '/api/fs/read-text');
      expect(request.url.queryParameters['path'], '/srv/project/main.dart');
      expect(request.url.queryParameters['profile'], 'writer');
      expect(request.url.queryParameters['session_id'], 'chat-7');
      return http.Response(
        jsonEncode({
          'path': '/srv/project/main.dart',
          'text': 'void main() {}',
          'language': 'dart',
          'mimeType': 'text/x-dart',
          'byteSize': 14,
          'binary': false,
          'truncated': true,
        }),
        200,
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final preview = await client.readText(
      '/srv/project/main.dart',
      profileName: 'writer',
      storedSessionId: 'chat-7',
    );

    expect(preview.text, 'void main() {}');
    expect(preview.language, 'dart');
    expect(preview.truncated, isTrue);
    client.close();
  });

  test('downloads bytes with the server filename', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.url.path, '/api/fs/download');
      expect(request.url.queryParameters['path'], '/srv/project/report.pdf');
      expect(request.url.queryParameters['profile'], 'writer');
      expect(request.url.queryParameters['session_id'], 'chat-7');
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-disposition': 'attachment; filename="report.pdf"'},
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final download = await client.download(
      '/srv/project/report.pdf',
      profileName: 'writer',
      storedSessionId: 'chat-7',
    );

    expect(download.filename, 'report.pdf');
    expect(download.bytes, [1, 2, 3]);
    client.close();
  });

  test('download rejects a declared body above the mobile limit', () async {
    final dashboard = dashboardWith(
      (_) async => http.Response.bytes([1, 2, 3], 200),
    );
    final client = RemoteFilesClient(dashboard: dashboard, maxDownloadBytes: 2);

    await expectLater(
      client.download(
        '/srv/project/large.bin',
        profileName: 'writer',
        storedSessionId: 'chat-7',
      ),
      throwsA(isA<DashboardResponseTooLargeException>()),
    );
    client.close();
  });

  test('download also bounds a chunked body without a declared size', () async {
    final dashboard = DashboardClient(
      host: 'hermes.local',
      port: 9119,
      proxied: true,
      httpClient: _StreamingClient(),
    );
    final client = RemoteFilesClient(dashboard: dashboard, maxDownloadBytes: 2);

    await expectLater(
      client.download(
        '/srv/project/chunked.bin',
        profileName: 'writer',
        storedSessionId: 'chat-7',
      ),
      throwsA(isA<DashboardResponseTooLargeException>()),
    );
    client.close();
  });

  test('download reduces encoded server filenames to a basename', () async {
    final dashboard = dashboardWith(
      (_) async => http.Response.bytes(
        [1],
        200,
        headers: {
          'content-disposition':
              "attachment; filename*=UTF-8''..%2Fprivate%2Freport%20one.pdf",
        },
      ),
    );
    final client = RemoteFilesClient(dashboard: dashboard);

    final download = await client.download(
      '/srv/private/internal-name',
      profileName: 'writer',
      storedSessionId: 'chat-7',
    );

    expect(download.filename, 'report one.pdf');
    client.close();
  });

  test('file reads require both chat owner fields', () async {
    final dashboard = dashboardWith((_) async => http.Response('{}', 200));
    final client = RemoteFilesClient(dashboard: dashboard);

    await expectLater(
      client.readText(
        '/srv/project/report.md',
        profileName: '',
        storedSessionId: 'chat-7',
      ),
      throwsArgumentError,
    );
    await expectLater(
      client.download(
        '/srv/project/report.md',
        profileName: 'writer',
        storedSessionId: '',
      ),
      throwsArgumentError,
    );
    client.close();
  });
}
