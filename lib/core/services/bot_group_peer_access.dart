import '../models/bots.dart';
import '../models/bot_group_peer.dart';
import 'bots_repository.dart';
import 'ws_client.dart';

/// One bounded seating attempt. The caller owns retries and visit lifetime;
/// invitations stay local to this call and never enter durable observations.
final class BotGroupPeerAccess {
  BotGroupPeerAccess({required this.owner, required this.sourcesForMember});

  final BotsRepository owner;
  final Future<List<BotsRepository>> Function(BotGroupMember member)
  sourcesForMember;

  Future<void> join(
    BotGroup group,
    BotGroupMember member, {
    required bool Function() canUse,
  }) async {
    final borrowed = <BotsRepository>{};
    void borrow(BotsRepository repository) {
      if (borrowed.add(repository)) repository.retain();
    }

    bool current() => owner.isCurrent && canUse();
    void checkCurrent() {
      if (!current()) throw const BotGroupPeerFailure('operation_retired');
    }

    try {
      checkCurrent();
      if (!member.target.isPeer ||
          member.profile != member.target.profile ||
          !group.members.any(
            (entry) =>
                entry.id == member.id &&
                entry.profile == member.profile &&
                entry.handle == member.handle &&
                entry.target == member.target,
          )) {
        throw const BotGroupPeerFailure('peer_target_mismatch');
      }
      borrow(owner);
      final selected = await _resolve(member, borrow, checkCurrent);
      final source = selected.source;
      bool dispatchable() => current() && source.isCurrent;
      final before = await owner.peerRoomState(group);
      checkCurrent();
      if (before.ended) throw const BotGroupPeerFailure('room_ended');
      // Any existing route, even an unhealthy one, makes this a renewal.
      final route = before.routes[member.id];
      final alreadyJoined = route != null && route != 'missing';
      final fresh = await _resolve(member, borrow, checkCurrent);
      if (fresh.source.scope != source.scope || !source.isCurrent) {
        throw const BotGroupPeerFailure('peer_gateway_changed');
      }
      final invitation = await source.invitePeer(
        group,
        member,
        renewalHorizon: fresh.capabilities.renewal,
        canUse: dispatchable,
      );
      if (!invitation.matches(member.target) ||
          invitation.url !=
              ((fresh.capabilities.roomLink['catalog'] as Map)['endpoint']
                  as Map)['url']) {
        throw const BotGroupPeerFailure('peer_target_mismatch');
      }

      // A late invitation must still be cleaned up after departure if the
      // captured owner proves this exact room ended. UI lifetime is irrelevant
      // to that cleanup; a replaced lender must never receive the grant.
      var endedObserved = false;
      Future<void> rejectEnded(bool ended) async {
        if (!ended) return;
        endedObserved = true;
        if (source.isCurrent) {
          try {
            await source.revokePeer(invitation, canUse: () => source.isCurrent);
          } catch (_) {
            // Cleanup failure cannot turn an ended room into a usable room.
          }
        }
        throw const BotGroupPeerFailure('room_ended');
      }

      var registrationAttempted = false;
      try {
        final afterInvite = await owner.peerRoomState(group);
        await rejectEnded(afterInvite.ended);
        checkCurrent();
        final registering = await _resolve(member, borrow, checkCurrent);
        if (registering.source.scope != source.scope || !source.isCurrent) {
          throw const BotGroupPeerFailure('peer_gateway_changed');
        }
        final catalog = registering.capabilities.roomLink['catalog'] as Map;
        final endpoint = catalog['endpoint'] as Map;
        if (!invitation.matches(member.target) ||
            invitation.url != endpoint['url']) {
          throw const BotGroupPeerFailure('peer_target_mismatch');
        }
        registrationAttempted = true;
        await owner.registerPeer(
          group,
          member,
          invitation,
          canUse: dispatchable,
        );
        checkCurrent();
        if (!source.isCurrent) {
          throw const BotGroupPeerFailure('peer_gateway_changed');
        }
      } catch (failure) {
        if (endedObserved) rethrow;
        final observed = await owner.peerRoomState(group);
        await rejectEnded(observed.ended);
        checkCurrent();
        if (!source.isCurrent) {
          throw const BotGroupPeerFailure('peer_gateway_changed');
        }
        if (registrationAttempted &&
            !alreadyJoined &&
            _uncertain(failure) &&
            observed.routes[member.id] == 'ready') {
          return;
        }
        if (failure is BotGroupPeerFailure) rethrow;
        throw const BotGroupPeerFailure('registration_unconfirmed');
      }
    } on BotGroupPeerFailure {
      rethrow;
    } catch (_) {
      // Transport errors may contain peer credentials; expose only safe copy.
      throw const BotGroupPeerFailure('registration_unconfirmed');
    } finally {
      for (final repository in borrowed) {
        repository.release();
      }
    }
  }

  Future<({BotsRepository source, BotGroupCapabilities capabilities})> _resolve(
    BotGroupMember member,
    void Function(BotsRepository) borrow,
    void Function() checkCurrent,
  ) async {
    final sources = (await sourcesForMember(
      member,
    )).where((source) => source.isCurrent).toSet();
    checkCurrent();
    final usable =
        <({BotsRepository source, BotGroupCapabilities capabilities})>[];
    var problem = 'peer_connection_missing';
    for (final source in sources) {
      borrow(source);
      try {
        final capabilities = await source.groupCapabilities(member.profile);
        checkCurrent();
        if (!source.isCurrent) continue;
        final target = capabilities.peerTarget;
        // peer_id is the room owner's frozen label, not a lender catalog fact.
        if (target == null ||
            target.installationId != member.target.installationId ||
            target.profile != member.target.profile ||
            target.capabilityDigest != member.target.capabilityDigest) {
          problem = capabilities.peerProblem ?? 'peer_target_mismatch';
          continue;
        }
        usable.add((source: source, capabilities: capabilities));
      } catch (_) {
        checkCurrent();
      }
    }
    // Saved-source membership can change while capability reads are pending.
    // Fail this attempt instead of chasing replacements or guessing a route.
    final latest = (await sourcesForMember(
      member,
    )).where((source) => source.isCurrent).toSet();
    checkCurrent();
    if (sources.length != latest.length ||
        !sources
            .map((source) => source.scope)
            .toSet()
            .containsAll(latest.map((source) => source.scope))) {
      throw const BotGroupPeerFailure('peer_gateway_changed');
    }
    if (usable.length > 1) {
      throw const BotGroupPeerFailure('peer_connection_ambiguous');
    }
    if (usable.isEmpty) throw BotGroupPeerFailure(problem);
    return usable.single;
  }

  static bool _uncertain(Object failure) => switch (failure) {
    JsonRpcError(:final reason) =>
      reason == 'request_timeout' || reason == 'connection_closed',
    BotGroupPeerFailure(:final reason) => reason == 'registration_unconfirmed',
    _ => true,
  };
}
