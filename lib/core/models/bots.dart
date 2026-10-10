import 'package:flutter/foundation.dart';

import 'hermes_profile.dart';
import 'profile_session_key.dart';

enum BotPresence { idle, working, needsInput, unknown }

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
  final ProfileSessionKey? chat;
  final ProfileSessionKey? resolvedChat;
  bool describesConversation(ProfileSessionKey key) =>
      key == chat || key == resolvedChat;
  final BotPresence presence;
  final Uint8List? avatar;
  String get id => '${scope.connectionIdentity}/${profile.name}';

  /// Adopt a confirmed asset write independently of metadata acknowledgements.
  BotRecord withAvatar(Uint8List? image) => BotRecord(
    scope: scope,
    instance: instance,
    profile: profile,
    title: title,
    shape: shape,
    color: color,
    pinned: pinned,
    hidden: hidden,
    hasAvatar: image != null,
    revision: revision,
    metadata: metadata,
    chat: chat,
    resolvedChat: resolvedChat,
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
class BotGroup {
  BotGroup({
    required this.scope,
    required this.instance,
    required this.id,
    required this.name,
    required Iterable<BotGroupMember> members,
    this.preview = '',
    this.working = false,
    this.pinned = false,
  }) : members = List.unmodifiable(members);
  final WorkspaceScope scope;
  final String instance, id, name, preview;
  final List<BotGroupMember> members;
  final bool working;
  final bool pinned;
  String get key => '${scope.connectionIdentity}/$id';
  BotGroup withPinned(bool value) => BotGroup(
    scope: scope,
    instance: instance,
    id: id,
    name: name,
    members: members,
    preview: preview,
    working: working,
    pinned: value,
  );
}

@immutable
class BotGroupEvent {
  const BotGroupEvent({
    required this.sequence,
    required this.kind,
    required this.actor,
    required this.text,
  });
  final int sequence;
  final String kind, actor, text;
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
}

@immutable
class BotInstance {
  const BotInstance(this.identity, this.label);
  final String identity, label;
}

@immutable
class BotScreenFrame {
  BotScreenFrame({Uint8List? image, required this.suppressed})
    : image = image?.asUnmodifiableView();
  final Uint8List? image;
  final bool suppressed;
}

class BotMetadataConflict implements Exception {
  const BotMetadataConflict();
  @override
  String toString() =>
      'This bot changed in another client. Reload and review your changes before saving.';
}
