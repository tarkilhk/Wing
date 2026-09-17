import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_capabilities_screen.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';

final _scope = WorkspaceScope(connectionId: 'server-a', profileName: 'work');
const _profiles = ProfileDiscovery(
  profiles: [HermesProfile(name: 'work')],
  currentName: 'work',
  activeName: 'default',
);

ProfileGateway _gateway({
  required ScopedGet get,
  ScopedPost? put,
  bool skillsOnly = true,
}) => ProfileGateway(
  scope: _scope,
  get: (path, query) => skillsOnly && path == 'tools/toolsets'
      ? Future.value({'data': []})
      : get(path, query),
  put: put,
  rpc: (_, _) async => {},
  discover: () async => _profiles,
);

Future<void> _show(WidgetTester tester, ProfileGateway gateway) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileCapabilitiesScreen(
        onToolSetup: (_) async {},
        onLibrary: () {},
        onHub: () {},
        onPlugins: () {},
        gateway: gateway,
        connectionLabel: 'Server A',
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Installed skills'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'skill toggle stays on captured profile and refreshes server state',
    (tester) async {
      var enabled = false;
      var reads = 0;
      String? writtenPath;
      Map<String, dynamic>? writtenBody;
      await _show(
        tester,
        _gateway(
          get: (path, query) async {
            expect(path, 'skills');
            expect(query, {'profile': 'work'});
            reads++;
            return {
              'data': [
                {
                  'name': 'research',
                  'description': 'Research sources',
                  'enabled': enabled,
                },
              ],
            };
          },
          put: (path, body) async {
            writtenPath = path;
            writtenBody = body;
            enabled = body['enabled'] == true;
            return {'ok': true, 'name': 'research', 'enabled': enabled};
          },
        ),
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(writtenPath, 'skills/toggle?profile=work');
      expect(writtenBody, {'name': 'research', 'enabled': true});
      expect(reads, 2);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Saved on the server for work.'), findsOneWidget);
    },
  );

  testWidgets('rejected toggle preserves state and does not claim success', (
    tester,
  ) async {
    await _show(
      tester,
      _gateway(
        get: (_, _) async => {
          'data': [
            {'name': 'research', 'enabled': true},
          ],
        },
        put: (_, _) async => {
          'ok': false,
          'name': 'research',
          'enabled': false,
        },
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(find.text('Saved on the server for work.'), findsNothing);
  });

  testWidgets(
    'late skill load cannot replace tools and unconfigured enable requires consent',
    (tester) async {
      final skills = Completer<Map<String, dynamic>>();
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileCapabilitiesScreen(
            onToolSetup: (_) async {},
            onLibrary: () {},
            onHub: () {},
            onPlugins: () {},
            connectionLabel: 'Server A',
            gateway: _gateway(
              skillsOnly: false,
              get: (path, _) => path == 'skills'
                  ? skills.future
                  : Future.value({
                      'data': [
                        {
                          'name': 'browser',
                          'label': 'Browser',
                          'description': 'Browse pages',
                          'enabled': false,
                          'configured': false,
                          'tools': ['browse'],
                        },
                      ],
                    }),
              put: (_, _) async {
                writes++;
                return {};
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Installed skills'));
      await tester.pump();
      await tester.tap(find.text('Capabilities'));
      await tester.pumpAndSettle();
      skills.complete({
        'data': [
          {'name': 'wrong-old-result', 'enabled': true},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('wrong-old-result'), findsNothing);
      expect(find.textContaining('Setup needed'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('existing setup process'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, 0);
    },
  );

  testWidgets(
    'instructions use selected profile and search only changes display',
    (tester) async {
      await _show(
        tester,
        _gateway(
          get: (path, query) async {
            expect(query['profile'], 'work');
            if (path == 'skills/content') {
              expect(query['name'], 'research');
              return {
                'name': 'research',
                'content': 'Read the original sources.',
              };
            }
            return {
              'data': [
                {
                  'name': 'research',
                  'enabled': true,
                  'description': 'Find evidence',
                },
                {'name': 'writing', 'enabled': false},
              ],
            };
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'evidence');
      await tester.pumpAndSettle();
      expect(find.text('writing'), findsNothing);
      await tester.tap(find.text('research'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read instructions'));
      await tester.pumpAndSettle();
      expect(find.text('Read the original sources.'), findsOneWidget);
    },
  );
}
