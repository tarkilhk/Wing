import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

void main() {
  test(
    'profile browsing reuses one sign-in without closing the live socket',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final requestedProfiles = <String>{};
      var logins = 0;
      final subscription = server.listen((request) async {
        if (request.uri.path == '/api/ws') {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.listen((raw) {
            final rpc = jsonDecode(raw as String) as Map;
            final params = rpc['params'] as Map;
            requestedProfiles.add(params['profile'] as String);
            socket.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': rpc['id'],
                'result': rpc['method'] == 'session.active_list'
                    ? {'sessions': []}
                    : {'projects': []},
              }),
            );
          });
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {'type': 'gateway.ready', 'payload': {}},
            }),
          );
          return;
        }
        Object result;
        if (request.uri.path == '/auth/password-login') {
          logins++;
          await request.drain<void>();
          if (logins > 1) {
            request.response.statusCode = HttpStatus.tooManyRequests;
            await request.response.close();
            return;
          }
          request.response.headers.add(
            'set-cookie',
            'hermes_session_at=fixture; Path=/',
          );
          result = <String, Object>{};
        } else {
          expect(request.headers.value('cookie'), 'hermes_session_at=fixture');
          result = switch (request.uri.path) {
            '/api/profiles' => {
              'profiles': [
                {'name': 'personal'},
                {'name': 'work'},
              ],
            },
            '/api/profiles/active' => {
              'current': 'personal',
              'active': 'personal',
            },
            '/api/auth/ws-ticket' => {'ticket': 'fixture-ticket'},
            '/api/sessions' => {
              'sessions': [],
              'offset': int.parse(request.uri.queryParameters['offset']!),
              'limit': int.parse(request.uri.queryParameters['limit']!),
              'total': 0,
            },
            _ => throw StateError('Unexpected fixture route'),
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
      });
      SharedPreferences.setMockInitialValues({});
      final controller = ProfileWorkspaceController(
        connection: SavedConnection(
          id: 'test',
          label: 'Fixture',
          host: '127.0.0.1',
          port: server.port,
          dashboardPortOverride: server.port,
          apiKey: '',
          dashboardUsername: 'fixture',
          dashboardPassword: 'fixture',
        ),
        connectionIdentity: 'fixture',
        preferences: await SharedPreferences.getInstance(),
      );
      final browser = ChatBrowserData(controller);
      addTearDown(() async {
        browser.dispose();
        controller.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await subscription.cancel();
        await server.close(force: true);
      });
      await controller.initialize();
      expect(controller.initialized, isTrue);
      final owner = controller.current;
      for (var i = 0; i < 5; i++) {
        await browser.refresh(archivedOnly: false);
        expect(browser.errors, isEmpty);
      }
      expect(browser.errors, isEmpty);
      expect(requestedProfiles, containsAll(['personal', 'work']));
      expect(controller.current, same(owner));
      expect(await owner!.gateway.call('session.active_list'), {
        'sessions': [],
      });
      expect(controller.connectionStatus.description, 'Connected');
      expect(
        logins,
        1,
        reason: 'profile readers share the saved connection authentication',
      );
    },
  );
}
