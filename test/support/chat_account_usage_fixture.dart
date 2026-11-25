import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import '../profile_connection_identity_test.dart' show identityTestConnection;
import 'profile_intelligence_fixture.dart';
import 'wing_client_identity_fixture.dart';

const accountUsageReport = <String, dynamic>{
  'lines': ['OpenAI subscription', 'Session: 42% used', 'Resets in 2 hours'],
  'nous_lines': [
    'Nous Portal balance (a separate account: this session runs on another provider)',
    'Total usable: \$18.50',
  ],
  'nous_route': false,
};

class ChatAccountUsageFixture extends ProfileIntelligenceFixture {
  final accountRequests = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? accountGate;
  Map<String, dynamic> accountReport = accountUsageReport;
  bool failAccount = false;
  int executionGeneration = 0, authorityEpoch = 1;
  String replayEpoch = 'fixture-epoch';
  Completer<void>? resumeGate;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      loadClientIdentity: loadTestWingClientIdentity,
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      close: base.close,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'session.account_usage') {
          accountRequests.add(Map.of(params));
          if (accountGate case final gate?) return gate.future;
          if (failAccount) throw StateError('Private provider error');
          return accountReport;
        }
        if (method == 'session.resume') await resumeGate?.future;
        final result = await base.call(method, params);
        if (method == 'session.resume' || method == 'session.create') {
          return {
            ...result,
            'execution_generation': executionGeneration,
            'authority_epoch': authorityEpoch,
            'replay_epoch': replayEpoch,
          };
        }
        return result;
      },
    );
  }
}

class AccountUsageHarness {
  AccountUsageHarness(this.fixture, this.preferences, this.controller);
  final ChatAccountUsageFixture fixture;
  final AppPreferences preferences;
  final ProfileWorkspaceController controller;

  static Future<AccountUsageHarness> create() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final preferences = AppPreferences(prefs);
    final fixture = ChatAccountUsageFixture();
    final controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'account-usage-test',
      preferences: prefs,
      appPreferences: preferences,
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    await controller.createChat(canDispatch: () => true);
    return AccountUsageHarness(fixture, preferences, controller);
  }

  void dispose() {
    controller.dispose();
    preferences.dispose();
  }
}
