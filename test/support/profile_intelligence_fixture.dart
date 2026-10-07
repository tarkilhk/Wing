import 'dart:async';

import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'profile_browser_fixture.dart';

/// Isolated gateway responses for the real profile screen/controller device check.
class ProfileIntelligenceFixture extends ProfileBrowserFixture {
  static const modelWarning = '''!!! LARGE CONTEXT MODEL SWITCH !!!

This session holds ~169,028 tokens of context.
Switching to gpt-5.6-sol makes the next reply re-read all of it uncached (providers key prompt caches per model) — a one-time full-price input cost.

Threshold: model.switch_context_confirm_tokens (currently 100,000; 0 disables this check).
Confirm only if you intend to switch now.''';
  final writes = <Map<String, dynamic>>[];
  void Function(Map<String, dynamic>)? onAcceptedWrite;
  String? resumedRuntimeId;
  bool failReasoning = false;
  bool failFast = false;
  String fastMode = 'normal';
  bool confirmModel = false;
  bool repeatConfirmation = false;
  bool failConfirmedModel = false;
  bool codexAppearsOnRefresh = false;
  final modelOptionReads = <Map<String, String>>[];
  Completer<void>? configGetStarted;
  Completer<void>? configGetDelay;
  String configGetValue = 'high';
  String resumedReasoningEffort = 'high';
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
          modelOptionReads.add(Map.of(query));
          return {
            'providers': [
              if (!codexAppearsOnRefresh || query['refresh'] == '1')
                {
                  'slug': 'openai-codex',
                  'name': 'OpenAI subscription',
                  'models': ['gpt-6-astra', 'gpt-5.6-sol', 'gpt-5.4-mini'],
                  'capabilities': {
                    for (final model in [
                      'gpt-6-astra',
                      'gpt-5.6-sol',
                      'gpt-5.4-mini',
                    ])
                      model: {'reasoning': true, 'fast': true},
                  },
                },
              if (codexAppearsOnRefresh && query['refresh'] != '1')
                {
                  'slug': 'openrouter',
                  'name': 'OpenRouter',
                  'models': ['openai/gpt-6-astra'],
                },
            ],
          };
        }
        return base.read(path, query);
      },
      rpc: (method, params) async {
        if (method == 'config.get') {
          if (params['key'] == 'fast') return {'value': fastMode};
          final started = configGetStarted;
          if (started != null && !started.isCompleted) started.complete();
          await configGetDelay?.future;
          return {'value': configGetValue};
        }
        if (method == 'config.set') {
          writes.add(Map.of(params));
          if (params['confirm_expensive_model'] == true && failConfirmedModel) {
            throw StateError('Model rejected');
          }
          if (params['key'] == 'model' &&
              confirmModel &&
              (params['confirm_expensive_model'] != true ||
                  repeatConfirmation)) {
            return {'confirm_required': true, 'confirm_message': modelWarning};
          }
          if (params['key'] == 'fast') {
            if (failFast) throw StateError('Fast rejected');
            fastMode = params['value'] as String;
          }
          if (params['key'] == 'reasoning' && failReasoning) {
            throw StateError('Reasoning rejected');
          }
          onAcceptedWrite?.call(params);
          return {'status': 'ok', 'value': params['value']};
        }
        final result = await base.call(method, params);
        if (method == 'session.resume' || method == 'session.create') {
          return {
            ...result,
            if (method == 'session.resume' && resumedRuntimeId != null)
              'session_id': resumedRuntimeId,
            'info': {
              'profile_name': scope.profileName,
              'model': 'gpt-6-astra',
              'provider': 'openai-codex',
              'reasoning_effort': resumedReasoningEffort,
            },
          };
        }
        return result;
      },
    );
  }
}
