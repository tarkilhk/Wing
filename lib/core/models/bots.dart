import 'package:flutter/foundation.dart';

import 'hermes_profile.dart';
import 'profile_session_key.dart';
import 'profile_colors.dart';

enum BotPresence { idle, working, groupWorking, needsInput, unknown }

const botShapes = [
  'circle',
  'blob',
  'squircle',
  'pill',
  'triangle',
  'hexagon',
  'cloud',
  'drop',
];

/// A roster observation belongs to an exact instance and canonical profile.
@immutable
class BotRecord {
  BotRecord({
    required this.scope,
    required this.instance,
    required this.profile,
    required this.title,
    required this.shape,
    required this.color,
    required this.pinned,
    required this.hidden,
    required this.hasAvatar,
    required this.revision,
    required Map<String, Object?> metadata,
    this.chat,
    this.resolvedChat,
    this.workerLastActive,
    this.lastActive,
    this.preview = '',
    this.presence = BotPresence.unknown,
    Uint8List? avatar,
  }) : metadata = Map.unmodifiable(metadata),
       avatar = avatar?.asUnmodifiableView();

  final WorkspaceScope scope;
  final String instance, title, shape, color, preview;
  final HermesProfile profile;
  final bool pinned, hidden, hasAvatar;
  final int revision;
  // Opaque, recursively frozen stock metadata. Only the repository merges it.
  final Map<String, Object?> metadata;

  /// Only an explicit stock choice admits procedural motion. The displayed
  /// shape can be a client default, so it is not sufficient by itself.
  bool get hasExplicitClassicShape =>
      metadata['imageKind'] == 'shape' &&
      metadata['shape'] == shape &&
      botShapes.contains(shape);
  final ProfileSessionKey? chat;
  final ProfileSessionKey? resolvedChat;

  /// Profile-owned background work reported by stock profiles.list.
  final DateTime? workerLastActive;

  /// Newest stock conversation or worker activity for this profile.
  final DateTime? lastActive;

  static int compareForRoster(BotRecord a, BotRecord b) {
    final activity = switch ((a.lastActive, b.lastActive)) {
      (final DateTime left, final DateTime right) => right.compareTo(left),
      (null, final DateTime _) => 1,
      (final DateTime _, null) => -1,
      (null, null) => 0,
    };
    if (activity != 0) return activity;
    final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
    if (pin != 0) return pin;
    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return title != 0 ? title : a.id.compareTo(b.id);
  }

  bool describesConversation(ProfileSessionKey key) =>
      key == chat || key == resolvedChat;
  final BotPresence presence;
  final Uint8List? avatar;
  String get id => '${scope.connectionIdentity}/${profile.name}';

  BotRecord withPresence(BotPresence value) => BotRecord(
    scope: scope,
    instance: instance,
    profile: profile,
    title: title,
    shape: shape,
    color: color,
    pinned: pinned,
    hidden: hidden,
    hasAvatar: hasAvatar,
    revision: revision,
    metadata: metadata,
    chat: chat,
    resolvedChat: resolvedChat,
    workerLastActive: workerLastActive,
    lastActive: lastActive,
    preview: preview,
    presence: value,
    avatar: avatar,
  );

  /// Adopt a confirmed asset write independently of metadata acknowledgements.
  BotRecord withAvatar(Uint8List? image) =>
      _withAvatar(image, hasAvatar: image != null);

  /// Reading an asset does not change Hermes's saved has-avatar metadata.
  BotRecord withObservedAvatar(Uint8List? image) =>
      _withAvatar(image, hasAvatar: hasAvatar);

  BotRecord _withAvatar(Uint8List? image, {required bool hasAvatar}) =>
      BotRecord(
        scope: scope,
        instance: instance,
        profile: profile,
        title: title,
        shape: shape,
        color: color,
        pinned: pinned,
        hidden: hidden,
        hasAvatar: hasAvatar,
        revision: revision,
        metadata: metadata,
        chat: chat,
        resolvedChat: resolvedChat,
        workerLastActive: workerLastActive,
        lastActive: lastActive,
        preview: preview,
        presence: presence,
        avatar: image,
      );

  BotRecord withMetadata({
    required Map<String, Object?> metadata,
    required int revision,
    String? title,
    String? shape,
    String? color,
    bool? pinned,
    bool? hidden,
  }) => BotRecord(
    scope: scope,
    instance: instance,
    profile: profile,
    title: title ?? this.title,
    shape: shape ?? this.shape,
    color: color ?? this.color,
    pinned: pinned ?? this.pinned,
    hidden: hidden ?? this.hidden,
    hasAvatar: hasAvatar,
    revision: revision,
    metadata: metadata,
    chat: chat,
    resolvedChat: resolvedChat,
    workerLastActive: workerLastActive,
    lastActive: lastActive,
    preview: preview,
    presence: presence,
    avatar: avatar,
  );
}

@immutable
class BotGroupMember {
  const BotGroupMember({
    required this.id,
    required this.profile,
    required this.handle,
    required this.name,
  });
  final String id, profile, handle, name;
}

@immutable
/// Immutable member display observations borrowed from the canonical owner.
final class BotGroupAppearance {
  const BotGroupAppearance.empty() : byHandle = const {};
  BotGroupAppearance._(Map<String, BotRecord> appearances)
    : byHandle = Map.unmodifiable(appearances);

  factory BotGroupAppearance.forGroup(
    BotGroup group,
    Iterable<BotRecord> bots,
  ) {
    final appearances = <String, BotRecord>{};
    for (final member in group.members) {
      final matches = bots.where(
        (bot) =>
            bot.scope.connectionId == group.scope.connectionId &&
            bot.scope.connectionIdentity == group.scope.connectionIdentity &&
            bot.profile.name == member.profile,
      );
      if (matches.length == 1) appearances[member.handle] = matches.single;
    }
    return BotGroupAppearance._(appearances);
  }

  final Map<String, BotRecord> byHandle;
  @override
  bool operator ==(Object other) =>
      other is BotGroupAppearance && mapEquals(byHandle, other.byHandle);
  @override
  int get hashCode => Object.hashAllUnordered(
    byHandle.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

class BotGroup {
  BotGroup({
    required this.scope,
    required this.instance,
    required this.id,
    required this.name,
    required Iterable<BotGroupMember> members,
    required this.observationComplete,
    this.preview = '',
    this.working = false,
    this.blocked = false,
    Iterable<String> activeMemberProfiles = const [],
    this.lastMessageAt,
    this.lastMessageSequence = 0,
    this.lastAnswerSequence = 0,
    this.pinned = false,
    this.iconColor,
    this.iconRevision,
    Uint8List? picture,
  }) : members = List.unmodifiable(members),
       activeMemberProfiles = Set.unmodifiable(activeMemberProfiles),
       picture = picture?.asUnmodifiableView();
  final WorkspaceScope scope;
  final String instance, id, name, preview;
  final List<BotGroupMember> members;
  final bool working, blocked;

  /// Members of a room observed working in this read, not individual writers.
  /// Retained room details never carry this positive activity into a failed read.
  final Set<String> activeMemberProfiles;

  /// False means runtime/message reads failed; absent fields are unknown.
  final bool observationComplete;
  final DateTime? lastMessageAt;
  final int lastMessageSequence, lastAnswerSequence;
  final bool pinned;
  final Uint8List? picture;
  final ProfileColorChoice? iconColor;

  /// Null means the backend icon metadata was not admitted for editing.
  final int? iconRevision;
  String get key => '${scope.connectionIdentity}/$id';
  BotGroup withDetails({
    required String name,
    required ProfileColorChoice color,
    required Uint8List? picture,
    required int revision,
  }) => BotGroup(
    scope: scope,
    instance: instance,
    id: id,
    name: name,
    members: members,
    observationComplete: observationComplete,
    preview: preview,
    working: working,
    blocked: blocked,
    activeMemberProfiles: activeMemberProfiles,
    lastMessageAt: lastMessageAt,
    lastMessageSequence: lastMessageSequence,
    lastAnswerSequence: lastAnswerSequence,
    pinned: pinned,
    picture: picture,
    iconColor: color,
    iconRevision: revision,
  );
  BotGroup withPinned(bool value) => BotGroup(
    scope: scope,
    instance: instance,
    id: id,
    name: name,
    members: members,
    observationComplete: observationComplete,
    preview: preview,
    working: working,
    blocked: blocked,
    activeMemberProfiles: activeMemberProfiles,
    lastMessageAt: lastMessageAt,
    lastMessageSequence: lastMessageSequence,
    lastAnswerSequence: lastAnswerSequence,
    pinned: value,
    picture: picture,
    iconColor: iconColor,
    iconRevision: iconRevision,
  );
  BotGroup withIcon({
    Uint8List? picture,
    ProfileColorChoice? color,
    int? revision,
  }) => BotGroup(
    scope: scope,
    instance: instance,
    id: id,
    name: name,
    members: members,
    observationComplete: observationComplete,
    preview: preview,
    working: working,
    blocked: blocked,
    activeMemberProfiles: activeMemberProfiles,
    lastMessageAt: lastMessageAt,
    lastMessageSequence: lastMessageSequence,
    lastAnswerSequence: lastAnswerSequence,
    pinned: pinned,
    picture: picture,
    iconColor: color,
    iconRevision: revision,
  );

  /// Keep confirmed runtime/message facts when only room identity refreshed.
  BotGroup withRetainedObservation(BotGroup previous) {
    if (key != previous.key || observationComplete) {
      throw ArgumentError(
        'Expected the same room with an unavailable observation',
      );
    }
    return BotGroup(
      scope: scope,
      instance: instance,
      id: id,
      name: name,
      members: members,
      observationComplete: false,
      preview: previous.preview,
      working: previous.working,
      blocked: previous.blocked,
      activeMemberProfiles: activeMemberProfiles,
      lastMessageAt: previous.lastMessageAt,
      lastMessageSequence: previous.lastMessageSequence,
      lastAnswerSequence: previous.lastAnswerSequence,
      pinned: pinned,
      picture: picture,
      iconColor: iconColor,
      iconRevision: iconRevision,
    );
  }
}

class BotGroupEditConflict implements Exception {
  const BotGroupEditConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

@immutable
class BotGroupEvent {
  const BotGroupEvent({
    required this.sequence,
    required this.kind,
    required this.actor,
    required this.actorId,
    required this.actorName,
    required this.timestamp,
    required this.text,
  });
  final int sequence;
  final String kind, actor, actorId, actorName, text;
  final DateTime timestamp;
  bool get isMessage => kind == 'message.user' || kind == 'message.member';
}

@immutable
class BotGroupPage {
  BotGroupPage(Iterable<BotGroupEvent> events, this.cursor, this.hasMore)
    : events = List.unmodifiable(events);
  final List<BotGroupEvent> events;
  final int cursor;
  final bool hasMore;
}

@immutable
class BotGroupAction {
  BotGroupAction({
    required this.kind,
    required this.task,
    this.member = '',
    this.request = '',
    this.generation = 0,
    this.command = '',
    this.description = '',
    Iterable<String> choices = const [],
  }) : choices = List.unmodifiable(choices);
  final String kind, task, member, request, command, description;
  final int generation;
  final List<String> choices;
  String get key => '$kind/$task/$member/$request/$generation';
}

@immutable
class BotGroupRuntime {
  BotGroupRuntime({
    required this.working,
    required this.blocked,
    required Iterable<BotGroupAction> actions,
  }) : actions = List.unmodifiable(actions);
  final bool working, blocked;
  final List<BotGroupAction> actions;
}

@immutable
class BotsSnapshot {
  BotsSnapshot({
    required this.botsAvailable,
    required this.groupsAvailable,
    Iterable<BotRecord> bots = const [],
    Iterable<BotGroup> groups = const [],
    this.loading = false,
    this.busy = false,
    Iterable<String> errors = const [],
    Iterable<String> groupHosts = const [],
    Iterable<BotInstance> instances = const [],
  }) : bots = List.unmodifiable(bots),
       groups = List.unmodifiable(groups),
       errors = List.unmodifiable(errors),
       groupHosts = List.unmodifiable(groupHosts),
       instances = List.unmodifiable(instances);
  final List<BotRecord> bots;
  final List<BotGroup> groups;
  final List<String> errors, groupHosts;
  final List<BotInstance> instances;
  final bool loading, busy;
  final bool botsAvailable, groupsAvailable;
}

@immutable
class BotInstance {
  const BotInstance(this.identity, this.label);
  final String identity, label;
}

@immutable
class BotMetadataConflict implements Exception {
  const BotMetadataConflict();
  @override
  String toString() =>
      'This bot changed in another client. Reload and review your changes before saving.';
}
