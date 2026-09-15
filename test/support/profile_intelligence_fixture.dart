import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'profile_browser_fixture.dart';

/// Isolated gateway responses for the real profile screen/controller device check.
class ProfileIntelligenceFixture extends ProfileBrowserFixture {
  final writes = <Map<String, dynamic>>[];
  bool failReasoning = false;
  bool confirmModel = false;
  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: (path, query) async {
        if (path == 'model/info') {
          return {'model': 'gpt-6-astra', 'provider': 'openai-codex'};
        }
        if (path == 'model/options') {
          return {
            'providers': [
              {
                'slug': 'openai-codex',
                'name': 'OpenAI subscription',
                'models': ['gpt-6-astra', 'gpt-5.6-sol', 'gpt-5.4-mini'],
              },
            ],
          };
        }
        return base.read(path, query);
      },
      rpc: (method, params) async {
        if (method == 'config.get') return {'value': 'high'};
        if (method == 'config.set') {
          writes.add(Map.of(params));
          if (params['key'] == 'model' && confirmModel) {
            return {'confirm_required': true};
          }
          if (params['key'] == 'reasoning' && failReasoning) {
            throw StateError('Reasoning rejected');
          }
          return {'status': 'ok'};
        }
        final result = await base.call(method, params);
        if (method == 'session.resume' || method == 'session.create') {
          return {
            ...result,
            'info': {
              'profile_name': scope.profileName,
              'model': 'gpt-6-astra',
              'provider': 'openai-codex',
              'reasoning_effort': 'high',
            },
          };
        }
        return result;
      },
    );
  }
}
