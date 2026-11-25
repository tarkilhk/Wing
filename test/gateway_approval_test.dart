import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_approval.dart';

void main() {
  group('GatewayApprovalRequest', () {
    test(
      'stock typed subjects retain exact names and sandbox choice semantics',
      () {
        final folder = GatewayApprovalRequest.fromEventData({
          'kind': 'access',
          'path': ' /srv/two  spaces/ ',
          'access': 'read_write',
          'risk': 'May change files',
          'choices': ['once', 'always', 'deny'],
        });
        expect(folder.path, ' /srv/two  spaces/ ');
        expect(folder.displaySubject, '␣/srv/two  spaces/␣');
        expect(folder.accessLabel, 'Read and write');
        expect(
          folder.choiceLabel(GatewayApprovalChoice.once),
          'Allow until sandbox is switched off',
        );
        expect(
          folder.choiceScope(GatewayApprovalChoice.always),
          'Save this access rule for future use.',
        );
        expect(folder.answer('deny', reason: '  Keep private  '), {
          'choice': 'deny',
          'reason': 'Keep private',
        });
        expect(folder.answer('once', reason: 'do not send'), {
          'choice': 'once',
        });
        final site = GatewayApprovalRequest.fromEventData({
          'kind': 'network',
          'host': 'example.org',
          'label': 'Reference website',
          'risk': 'External service',
          'choices': ['once', 'deny'],
        });
        expect(site.displaySubject, 'example.org');
        expect(site.label, 'Reference website');
        expect(site.notificationPreview, 'Review website access\nexample.org');
        expect(site.answer('deny', reason: '  '), {'choice': 'deny'});
      },
    );

    test('stock optional access level does not invent a restriction', () {
      final request = GatewayApprovalRequest.fromEventData({
        'kind': 'access',
        'path': '/srv/project',
        'choices': ['once', 'deny'],
      });
      expect(request.valid, isTrue);
      expect(request.accessLabel, isNull);
      expect(request.answer('once'), {'choice': 'once'});
    });

    test(
      'hidden target characters cannot masquerade as literal escapes or spaces',
      () {
        expect(
          GatewayApprovalRequest.displayName('a\u200bb\u202ec\n'),
          r'a\u200bb\u202ec\x0a',
        );
        expect(GatewayApprovalRequest.displayName('a\u0600b'), r'a\u0600b');
        expect(GatewayApprovalRequest.displayName(r'a\u200b'), r'a\x5cu200b');
        expect(
          GatewayApprovalRequest.displayName('a\u00a0b␣'),
          r'a\xa0b\u2423',
        );
      },
    );

    test(
      'unknown or malformed subjects fail closed and no choices are invented',
      () {
        for (final subject in [
          {'kind': 'access', 'access': 'read'},
          {'kind': 'access', 'path': '  ', 'access': 'read'},
          {'kind': 'access', 'path': 42, 'access': 'read'},
          {'kind': 'access', 'path': '/srv/private', 'access': 'execute'},
          {'kind': 'network'},
          {
            'kind': 'network',
            'host': ['example.org'],
          },
          {'kind': 'unknown', 'command': 'echo safe'},
        ]) {
          final request = GatewayApprovalRequest.fromEventData({
            ...subject,
            'choices': ['once', 'always', 'deny'],
          });
          expect(request.valid, isFalse);
          expect(request.choices, [GatewayApprovalChoice.deny]);
          expect(() => request.answer('once'), throwsArgumentError);
        }
        expect(
          GatewayApprovalRequest.fromEventData({
            'command': 'echo safe',
          }).choices,
          isEmpty,
        );
      },
    );

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
        'choices': ['once', 'session', 'always', 'deny'],
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
        'choices': ['once', 'session', 'deny'],
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

    test('does not invent choices for an explicit unrecognized list', () {
      final request = GatewayApprovalRequest.fromEventData({
        'allow_permanent': false,
        'choices': ['unknown'],
      });

      expect(request.choices, isEmpty);
    });
  });
}
