import 'dart:async';
import 'package:wing/core/services/administration_repository.dart';
import 'administration_fixture.dart';

class ProfileVoiceFixture extends AdministrationFixture {
  ProfileVoiceFixture() {
    configs['personal']!['tts'] = {
      'provider': 'edge',
      'edge': {'voice': 'en-US-AriaNeural', 'speed': 1.2},
      'openai': {'voice': 'alloy'},
      'elevenlabs': {'voice_id': 'custom-a'},
    };
  }
  Completer<void>? putStarted;
  bool elevenLabsReady = true;
  bool nousReady = false;
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
    if (path.startsWith('tools/toolsets/tts/')) {
      requests.add((method, path, {...query}, body));
      if (path.endsWith('/provider')) {
        if (reject) return {'ok': false};
        if (!ignoreSave) {
          setSetting(
            configs[query['profile']]!,
            'tts.provider',
            switch (body!['provider']) {
              'Edge' => 'edge',
              'Nous Subscription' => 'nous',
              'OpenAI TTS' => 'openai',
              'ElevenLabs' => 'elevenlabs',
              _ => throw StateError('Unknown provider'),
            },
          );
        }
        return {
          'ok': true,
          'provider': body!['provider'],
          if (body['provider'] == 'Nous Subscription' && !nousReady)
            'needs_nous_auth': true,
        };
      }
      return {
        'providers': [
          {'name': 'Edge', 'tts_provider': 'edge', 'status': 'ready'},
          // Stock Hermes exposes two routes for the same OpenAI engine.
          {
            'name': 'Nous Subscription',
            'tts_provider': 'openai',
            'requires_nous_auth': true,
            'status': nousReady ? 'ready' : 'needs_auth',
          },
          {
            'name': 'OpenAI TTS',
            'tts_provider': 'openai',
            'requires_nous_auth': false,
            'status': 'ready',
            'env_vars': [
              {
                'key': 'VOICE_TOOLS_OPENAI_KEY',
                'prompt': 'OpenAI API key',
                'is_set': true,
              },
            ],
          },
          {
            'name': 'ElevenLabs',
            'tts_provider': 'elevenlabs',
            'status': elevenLabsReady ? 'ready' : 'needs_keys',
            'env_vars': [
              {
                'key': 'ELEVENLABS_API_KEY',
                'prompt': 'API key',
                'is_set': elevenLabsReady,
              },
            ],
          },
        ],
      };
    }
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
            'tts.openai.voice': {'type': 'string'},
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
