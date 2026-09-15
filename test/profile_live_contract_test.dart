import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';

/// Opt-in, no model calls. Uses existing disposable profiles on the unmodified
/// local Desktop-managed server. Authentication is fetched, never logged/saved.
void main() {
  const port = int.fromEnvironment('HERMES_TEST_PORT');
  test(
    'stock local Hermes profile REST and RPC contract',
    () async {
      final connection = SavedConnection(
        id: 'local-qa',
        label: 'Prestige QA',
        host: '127.0.0.1',
        port: port,
        dashboardPortOverride: port,
        apiKey: '',
      );
      for (final profile in ['android-qa-a', 'android-qa-b']) {
        final gateway = ProfileGateway.forConnection(
          connection,
          WorkspaceScope(connectionId: connection.id, profileName: profile),
        );
        addTearDown(gateway.close);
        expect((await gateway.discover()).named(profile), isNotNull);
        await gateway.connect();
        final sessions = await gateway.sessions();
        expect(sessions.rows.every((s) => s['profile'] == profile), isTrue);
        await gateway.projects();
        final session = await gateway.createSession(title: 'Android QA draft');
        expect(session['info']['profile_name'], profile);
        expect(session['stored_session_id'], isA<String>());
        await gateway
            .connect(); // Reusing a healthy socket must not detach drafts.
        final attachment = await gateway.call('file.attach', {
          'session_id': session['session_id'],
          'name': 'android-qa.txt',
          'data_url': 'data:text/plain;base64,SGVybWVzIEFuZHJvaWQgUUE=',
        });
        expect(attachment['ref_text'], isA<String>());
      }
    },
    skip: port == 0,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
