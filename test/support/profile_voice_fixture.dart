import 'dart:async';
import 'administration_fixture.dart';

class ProfileVoiceFixture extends AdministrationFixture {
  ProfileVoiceFixture() {
    configs['personal']!['tts'] = {
      'provider': 'edge',
      'edge': {'voice': 'en-US-AriaNeural', 'speed': 1.2},
      'elevenlabs': {'voice_id': 'custom-a'},
    };
  }
  Completer<void>? putStarted;
  Completer<Map<String, dynamic>>? audioGate;
  Map<String, dynamic> catalogue = {
    'available': true,
    'voices': [
      {
        'voice_id': 'custom-a',
        'name': 'Narrator',
        'label': 'Narrator (cloned)',
      },
      {'voice_id': 'custom-b', 'name': 'Storyteller', 'label': 'Storyteller'},
    ],
  };
  final audio = {
    'ok': true,
    'data_url': 'data:audio/mpeg;base64,AQID',
    'provider': 'edge',
  };
  @override
  Future<Map<String, dynamic>> send(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic>? body,
  ) async {
    if (method == 'PUT' &&
        path == 'config' &&
        putStarted?.isCompleted == false) {
      putStarted!.complete();
    }
    if (path == 'config/schema' || path.startsWith('audio/')) {
      requests.add((method, path, {...query}, body));
      return switch (path) {
        'config/schema' => {
          'fields': {
            'tts.edge.voice': {'type': 'string'},
            'tts.elevenlabs.voice_id': {'type': 'string'},
          },
        },
        'audio/elevenlabs/voices' => catalogue,
        'audio/speak' => audioGate?.future ?? audio,
        _ => throw StateError(
          'Non-vanilla or unexpected audio endpoint: $path',
        ),
      };
    }
    return super.send(method, path, query, body);
  }
}
