import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_approval.dart';

void main() {
  group('GatewayApprovalRequest', () {
    test('preserves command indentation and trailing newlines for review', () {
      const command = '  echo fixture\n';
      expect(
        GatewayApprovalRequest.fromEventData({'command': command}).command,
        command,
      );
    });

    test('uses all official choices when the gateway allows them', () {
      final request = GatewayApprovalRequest.fromEventData({
        'command': 'echo fixture',
        'description': 'Run a fixture command',
        'allow_permanent': true,
        'choices': ['once', 'session', 'always', 'deny'],
      });

      expect(request.command, 'echo fixture');
      expect(request.allowPermanent, isTrue);
      expect(request.choices, GatewayApprovalChoice.values);
    });

    test('removes permanent approval when Hermes disallows it', () {
      final request = GatewayApprovalRequest.fromEventData({
        'allow_permanent': false,
        'choices': ['once', 'session', 'always'],
      });

      expect(request.allowPermanent, isFalse);
      expect(request.choices, [
        GatewayApprovalChoice.once,
        GatewayApprovalChoice.session,
        GatewayApprovalChoice.deny,
      ]);
    });

    test('pending queue entries respect disabled session approval', () {
      final request = GatewayApprovalRequest.fromEventData({
        'allow_session': false,
      });
      expect(request.choices, [
        GatewayApprovalChoice.once,
        GatewayApprovalChoice.deny,
      ]);
    });

    test('smart denied approvals can only be run once or denied', () {
      final request = GatewayApprovalRequest.fromEventData({
        'smart_denied': true,
        'choices': ['once', 'session', 'always', 'deny'],
      });

      expect(request.choices, [
        GatewayApprovalChoice.once,
        GatewayApprovalChoice.deny,
      ]);
    });

    test('falls back to the official non-permanent choices', () {
      final request = GatewayApprovalRequest.fromEventData({
        'allow_permanent': false,
        'choices': ['unknown'],
      });

      expect(request.choices, [
        GatewayApprovalChoice.once,
        GatewayApprovalChoice.session,
        GatewayApprovalChoice.deny,
      ]);
    });
  });
}
