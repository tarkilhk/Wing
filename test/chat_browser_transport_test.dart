import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:convert';
import 'dart:async';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'dart:io';

import 'support/gateway_application_requests.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/chat_browser_data.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

void main() {
  test(
    'retired captured browser PATCH held at authentication sends zero writes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final entered = Completer<void>(), release = Completer<void>();
      var writes = 0;
      final subscription = server.listen((request) async {
        Object result;
        if (request.uri.path == '/auth/password-login') {
          await request.drain<void>();
          entered.complete();
          await release.future;
          request.response.headers.add(
            'set-cookie',
            'hermes_session_at=fixture; Path=/',
          );
          result = <String, Object>{};
        } else if (request.method == 'PATCH') {
          writes++;
          result = {'ok': true};
        } else {
          result = switch (request.uri.path) {
            '/api/profiles' => {
              'profiles': [
                {'name': 'personal'},
              ],
            },
            '/api/profiles/active' => {
              'current': 'personal',
              'active': 'personal',
            },
            _ => throw StateError(
              'Unexpected fixture route: ${request.uri.path}',
            ),
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
      });
      final connection = SavedConnection(
        id: 'held',
        label: 'Fixture',
        host: '127.0.0.1',
        port: server.port,
        dashboardPortOverride: server.port,
        apiKey: '',
        dashboardUsername: 'fixture',
        dashboardPassword: 'fixture',
      );
      final gateway = ProfileGateway.forConnection(
        ConnectionAccess(connection: connection, dashboardOAuth: null),
        WorkspaceScope(
          connectionId: 'held',
          profileName: 'personal',
          connectionIdentity: 'held-auth',
        ),
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        gateway.close();
        await subscription.cancel();
        await server.close(force: true);
      });
      var active = true;
      final pending = gateway.updateSession('chat', {
        'unread': false,
      }, canDispatch: () => active);
      final checked = expectLater(
        pending,
        throwsA(isA<DashboardRequestNotSentException>()),
      );
      await entered.future.timeout(const Duration(seconds: 5));
      active = false;
      release.complete();
      await checked;
      expect(writes, 0);
    },
  );

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
          gatewayApplicationRequests(socket).listen((raw) {
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
      final preferences = await SharedPreferences.getInstance();
      final appPreferences = AppPreferences(preferences);
      addTearDown(appPreferences.dispose);
      final controller = ProfileWorkspaceController(
        access: ConnectionAccess(
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
          dashboardOAuth: null,
        ),
        connectionIdentity: 'fixture',
        preferences: preferences,
        appPreferences: appPreferences,
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
        expect(
          browser.state.profiles.values.where(
            (profile) => profile.error != null,
          ),
          isEmpty,
        );
      }
      expect(
        browser.state.profiles.values.where((profile) => profile.error != null),
        isEmpty,
      );
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
