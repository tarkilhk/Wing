import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/hermes_voice.dart';

void main() {
  test(
    'authenticated audio requests retain explicit profile and contain no voice overrides',
    () async {
      var logins = 0;
      var transcriptions = 0;
      final bodies = <Map<String, dynamic>>[];
      final dashboard = DashboardClient(
        host: 'hermes.test',
        port: 9119,
        username: 'owner',
        password: 'fixture',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            logins++;
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie': 'hermes_session_at=fixture$logins; Path=/',
              },
            );
          }
          expect(request.method, 'POST');
          expect(request.headers['cookie'], contains('hermes_session_at='));
          expect(request.url.queryParameters, {'profile': 'work'});
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (request.url.path == '/api/audio/transcribe') {
            transcriptions++;
            if (transcriptions == 1) return http.Response('', 401);
            return http.Response(
              '{"ok":true,"transcript":" Hello ","provider":"fixture"}',
              200,
            );
          }
          expect(request.url.path, '/api/audio/speak');
          return http.Response(
            '{"ok":true,"data_url":"data:audio/wav;base64,AQID"}',
            200,
          );
        }),
      );
      final client = HermesVoice(
        profile: 'work',
        request: (path, body) => dashboard.apiPost(path, body: body),
        closeClient: dashboard.close,
      );
      addTearDown(client.close);
      expect(await client.transcribe(Uint8List.fromList([1, 2, 3])), 'Hello');
      expect(await client.synthesize('Reply'), [1, 2, 3]);
      expect(logins, 2);
      expect(bodies[0], {
        'data_url': 'data:audio/mp4;base64,AQID',
        'mime_type': 'audio/mp4',
      });
      expect(bodies[1], bodies[0]);
      expect(bodies[2], {'text': 'Reply'});
    },
  );
  test(
    'rejects invalid audio and provider envelopes instead of playing or inventing text',
    () async {
      var calls = 0;
      Map<String, dynamic> response = {'ok': false, 'transcript': 'bad'};
      final client = HermesVoice(
        profile: 'personal',
        closeClient: () {},
        request: (_, _) async {
          calls++;
          return response;
        },
      );
      await expectLater(client.transcribe(Uint8List(0)), throwsStateError);
      expect(calls, 0);
      await expectLater(
        client.transcribe(Uint8List.fromList([1])),
        throwsFormatException,
      );
      response = {'ok': true, 'data_url': 'https://foreign.example/audio.mp3'};
      await expectLater(client.synthesize('hello'), throwsFormatException);
      response = {'ok': true, 'data_url': 'data:audio/mp3;base64,'};
      await expectLater(client.synthesize('hello'), throwsFormatException);
    },
  );
}
