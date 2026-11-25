import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/bot_delivery.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/bot_deliveries_session.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/group_observations.dart';
import 'support/administration_fixture.dart';
import 'support/bots_fixture.dart';

Map<String, dynamic> deliveryRow({
  String state = 'waiting_on_you',
  String target = 'mira',
  String? reason,
}) => {
  'delivery_id': 'delivery-1',
  'target': target,
  'target_handle': '@$target',
  'state': state,
  'since': 1800000000,
  'preview': 'Review the release',
  if (state == 'waiting_on_you') 'waiting_on': 'approval',
  'reason': ?reason,
};

void main() {
  test(
    'production gateway binds sender and preserves all stock delivery states',
    () async {
      final fixture = BotsFixture();
      final admin = AdministrationFixture('delivery-server');
      final observations = GroupObservations(
        WorkspaceScope(
          connectionId: 'delivery-server',
          connectionIdentity: 'delivery-server-endpoint',
          profileName: 'default',
        ),
      );
      addTearDown(observations.dispose);
      addTearDown(admin.server.close);
      Map<String, dynamic> result = {
        'sender': 'atlas',
        'deliveries': [
          for (final state in [
            'queued',
            'claimed',
            'working',
            'waiting_on_you',
            'failed',
          ])
            deliveryRow(
              state: state,
              reason: state == 'failed' ? 'unknown_outcome' : null,
            ),
        ],
      };
      final paramsSeen = <Map<String, dynamic>>[];
      admin.rpcOverride = (method, params) async {
        if (method == 'bot_delivery.list') {
          paramsSeen.add(Map.of(params));
          return result;
        }
        return fixture.read(params['profile'] as String, method, params);
      };
      final repository = BotsRepository.forServer(
        admin.server,
        groupObservations: observations,
      );
      final sender = (await repository.bots()).first;
      final rows = await repository.senderDeliveries(sender);
      expect(rows.map((row) => row.state), BotDeliveryState.values);
      expect(rows.last.unknownOutcome, isTrue);
      expect(rows[3].status, 'Needs approval');
      expect(paramsSeen, [
        {'profile': 'atlas'},
      ]);
      expect(
        admin.rpcRequests.where((call) => call.$2 == 'bot_delivery.list'),
        [('atlas', 'bot_delivery.list')],
      );
      for (final malformed in <Map<String, dynamic>>[
        {'sender': 'mira', 'deliveries': []},
        {'sender': 'atlas'},
        {
          'sender': 'atlas',
          'deliveries': [{}],
        },
        {
          'sender': 'atlas',
          'deliveries': [null],
        },
        {
          'sender': 'atlas',
          'deliveries': [deliveryRow(state: 'completed')],
        },
        {
          'sender': 'atlas',
          'deliveries': [
            {...deliveryRow(), 'since': double.nan},
          ],
        },
        {
          'sender': 'atlas',
          'deliveries': [
            {...deliveryRow(), 'preview': 3},
          ],
        },
      ]) {
        result = malformed;
        await expectLater(
          repository.senderDeliveries(sender),
          throwsFormatException,
        );
      }
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'exact teammate lookup preserves instance and canonical tip without creates',
    () async {
      final fixture = BotsFixture();
      final sender = (await fixture.repository.bots()).first;
      // A title twin cannot replace the target's canonical identity.
      fixture.profiles.add(BotsFixture.profile('twin', 'Mira'));
      final key = await fixture.repository.existingTeammateChat(sender, 'mira');
      expect(
        key.workspace,
        WorkspaceScope(
          connectionId: 'host',
          connectionIdentity: 'instance-1',
          profileName: 'mira',
        ),
      );
      expect(key.sessionId, 'mira-tip');
      fixture.profiles[1].remove('canonical_session');
      await expectLater(
        fixture.repository.existingTeammateChat(sender, 'mira'),
        throwsStateError,
      );
      await expectLater(
        fixture.repository.existingTeammateChat(sender, 'absent'),
        throwsStateError,
      );
      final other = BotsRepository(
        scope: WorkspaceScope(
          connectionId: 'host',
          connectionIdentity: 'instance-2',
          profileName: 'default',
        ),
        instance: 'Other',
        groupObservations: fixture.repository.groupObservations,
        read: fixture.read,
        command: fixture.command,
        ownership: fixture.ownership,
      );
      await expectLater(other.senderDeliveries(sender), throwsStateError);
      await expectLater(
        other.existingTeammateChat(sender, 'mira'),
        throwsStateError,
      );
      expect(fixture.commands, isEmpty);
    },
  );

  testWidgets(
    'empty polls discover work; failure retains rows and stops until retry; empty removes without completion',
    (tester) async {
      final fixture = BotsFixture();
      final sender = (await fixture.repository.bots()).first;
      var reads = 0, fail = false;
      var rows = <Map<String, dynamic>>[];
      Completer<Map<String, dynamic>?>? held;
      fixture.readHook = (profile, method, params) async {
        if (method != 'bot_delivery.list') return null;
        reads++;
        if (held != null) return held.future;
        if (fail) throw StateError('storage unavailable');
        return {'sender': profile, 'deliveries': rows};
      };
      final owner = BotDeliveriesSession(
        sender: sender,
        repository: fixture.repository,
      )..setActive(true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reads, 1);
      expect(owner.state.visible, isFalse);
      rows = [deliveryRow()];
      await tester.pump(const Duration(seconds: 5));
      expect(reads, 2);
      expect(owner.state.deliveries.single.status, 'Needs approval');
      held = Completer();
      await tester.pump(const Duration(seconds: 5));
      expect(owner.state.refreshing, isFalse);
      final first = owner.refresh();
      final second = owner.refresh();
      expect(identical(first, second), isTrue);
      expect(owner.state.refreshing, isTrue);
      expect(reads, 3);
      held.completeError(StateError('storage unavailable'));
      await tester.pump(const Duration(milliseconds: 1));
      await first;
      held = null;
      expect(owner.state.error, isNotNull);
      expect(owner.state.deliveries.single.id, 'delivery-1');
      expect(owner.state.refreshing, isFalse);
      await tester.pump(const Duration(seconds: 30));
      expect(reads, 3);
      fail = true;
      await owner.refresh();
      expect(owner.state.error, isNotNull);
      fail = false;
      rows = [];
      await owner.refresh();
      expect(owner.state.error, isNull);
      expect(owner.state.deliveries, isEmpty);
      expect(owner.state.visible, isFalse);
      expect(fixture.commands, isEmpty);
      owner.dispose();
    },
  );

  testWidgets(
    'departure retires explicit cue and late result; reopening coalesces a fresh read; disposal fences completion',
    (tester) async {
      final fixture = BotsFixture();
      final sender = (await fixture.repository.bots()).first;
      final gates = <Completer<Map<String, dynamic>?>>[];
      fixture.readHook = (profile, method, params) async {
        if (method != 'bot_delivery.list') return null;
        final gate = Completer<Map<String, dynamic>?>();
        gates.add(gate);
        return gate.future;
      };
      final owner = BotDeliveriesSession(
        sender: sender,
        repository: fixture.repository,
      )..setActive(true);
      await tester.pump(const Duration(milliseconds: 1));
      final pending = owner.refresh();
      expect(owner.state.refreshing, isTrue);
      owner.setActive(false);
      expect(owner.state.refreshing, isFalse);
      owner.setActive(true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(gates, hasLength(1));
      gates.first.complete({
        'sender': 'atlas',
        'deliveries': [deliveryRow(target: 'obsolete')],
      });
      await tester.pump(const Duration(milliseconds: 1));
      expect(owner.state.deliveries, isEmpty);
      expect(owner.state.refreshing, isFalse);
      expect(gates, hasLength(2));
      gates.last.complete({
        'sender': 'atlas',
        'deliveries': [deliveryRow(target: 'mira')],
      });
      await tester.pump(const Duration(milliseconds: 1));
      await pending;
      expect(owner.state.deliveries.single.target, 'mira');
      await tester.pump(const Duration(seconds: 5));
      expect(gates, hasLength(3));
      owner.dispose();
      gates.last.complete({'sender': 'atlas', 'deliveries': []});
      await tester.pump(const Duration(milliseconds: 1));
      expect(owner.state.deliveries.single.target, 'mira');
      await tester.pump(const Duration(seconds: 30));
      expect(gates, hasLength(3));
    },
  );
}
