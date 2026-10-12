import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/group_notification.dart';
import '../models/hermes_profile.dart';
import 'bot_group_read_state.dart';

typedef GroupNotificationRead =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

final class _WatchedGroup {
  _WatchedGroup(this.title, this.cursor);
  String title;
  int cursor;
  int sending = 0;
  bool working = false, blocked = false, uncertain = false, pending = false;
  bool get active => working || sending > 0 || pending;
}

/// Owns room work, replay cursors and delivery ordering for one connection.
/// Private bot runtime states never establish shared discussion completion.
class GroupNotificationSession extends ChangeNotifier {
  GroupNotificationSession({
    required this.scope,
    required this.instance,
    required this.preferences,
    required this.read,
    required this.publish,
    required this.clearRead,
    this.pollInterval = const Duration(seconds: 5),
  }) {
    final saved = preferences.getString(_storageKey);
    if (saved != null) {
      try {
        final values = jsonDecode(saved) as Map<String, dynamic>;
        for (final entry in values.entries) {
          if (entry.value is int && entry.value >= 0) {
            _cursors[entry.key] = entry.value as int;
          }
        }
      } catch (_) {
        /* Unusable local cursors establish a fresh baseline. */
      }
    }
  }
  final WorkspaceScope scope;
  final String instance;
  final SharedPreferences preferences;
  final GroupNotificationRead read;
  final Future<void> Function(GroupAnswerNotification) publish;
  final Future<void> Function(GroupNotificationTarget, int) clearRead;
  final Duration pollInterval;
  final _groups = <String, _WatchedGroup>{};
  final _cursors = <String, int>{};
  String get _storageKey =>
      'group_notification_sequences/${scope.connectionIdentity}';
  bool _closed = false, _activated = false, _foreground = true, _again = false;
  Future<void>? _refreshing;
  Timer? _timer;

  bool get hasActiveGroups => _groups.values.any((group) => group.active);
  Iterable<({String title, String state})> get monitoringGroups sync* {
    for (final group in _groups.values) {
      if (group.active) {
        yield (
          title: group.title,
          state: group.uncertain
              ? 'reconnecting'
              : group.blocked
              ? 'needs input'
              : 'working',
        );
      }
    }
  }

  void _changed() {
    if (_closed) return;
    _timer?.cancel();
    _timer = null;
    if (_activated && (_foreground || hasActiveGroups)) {
      _timer = Timer(pollInterval, () => unawaited(refresh()));
    }
    notifyListeners();
  }

  void setForeground(bool value) {
    if (_closed || _foreground == value) return;
    _foreground = value;
    _changed();
    if (value && _activated) unawaited(refresh());
  }

  Future<void> activate() {
    _activated = true;
    return refresh();
  }

  void beginSend(String roomId, String title) {
    if (_closed) return;
    _activated = true;
    final group = _groups.putIfAbsent(
      roomId,
      () => _WatchedGroup(title, _cursors[roomId] ?? -1),
    );
    group.sending++;
    _changed();
  }

  Future<void> endSend(String roomId, {required bool dispatched}) async {
    if (_closed) return;
    // Keep the send lease until the room's accepted state has been observed.
    await refresh();
    if (_closed) return;
    final group = _groups[roomId];
    if (group != null && group.sending > 0) {
      group.sending--;
      if (dispatched && group.uncertain) group.pending = true;
    }
    _changed();
  }

  Future<void> acknowledge(String roomId, int sequence) =>
      clearRead(GroupNotificationTarget(scope, roomId), sequence);

  Future<void> refresh() {
    if (_closed) return Future.value();
    if (_refreshing != null) {
      _again = true;
      return _refreshing!;
    }
    _refreshing =
        (() async {
          do {
            _again = false;
            await _refresh();
          } while (_again && !_closed);
        })().whenComplete(() {
          _refreshing = null;
        });
    return _refreshing!;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) throw const FormatException('Missing group observation');
    return Map<String, dynamic>.from(value);
  }

  static int _sequence(dynamic value) {
    if (value is! int || value < 0) {
      throw const FormatException('Invalid group sequence');
    }
    return value;
  }

  Future<void> _saveCursor(String roomId, int sequence) async {
    final next = {..._cursors, roomId: sequence};
    if (!await preferences.setString(_storageKey, jsonEncode(next))) {
      throw StateError('Group notification cursor could not be saved');
    }
    _cursors.addAll(next);
  }

  Future<void> _refresh() async {
    try {
      final rooms = <String, String>{};
      var offset = 0;
      while (!_closed) {
        final result = await read('groups.list', {
          'limit': 100,
          'offset': offset,
        });
        if (_closed) return;
        final rows = result['rooms'];
        if (rows is! List) throw const FormatException('Missing group list');
        for (final raw in rows) {
          final row = _map(raw);
          final id = row['room_id'], name = row['name'];
          if (id is! String ||
              id.isEmpty ||
              name is! String ||
              name.trim().isEmpty ||
              rooms.containsKey(id)) {
            throw const FormatException('Invalid group identity');
          }
          rooms[id] = name;
        }
        final next = result['next_offset'];
        if (next == null) break;
        if (next is! int || next <= offset || rows.isEmpty) {
          throw const FormatException('Invalid group list cursor');
        }
        offset = next;
      }
      // Missing rooms are uncertain; they cannot release previously seen work.
      for (final entry in _groups.entries) {
        if (!rooms.containsKey(entry.key) && entry.value.active) {
          try {
            await _refreshRoom(entry.key, entry.value);
          } catch (_) {
            entry.value.uncertain = true;
          }
        }
      }
      for (final entry in rooms.entries) {
        if (_closed) return;
        final group = _groups.putIfAbsent(
          entry.key,
          () => _WatchedGroup(entry.value, _cursors[entry.key] ?? -1),
        );
        group.title = entry.value;
        try {
          await _refreshRoom(entry.key, group);
        } catch (_) {
          group.uncertain = true;
        }
      }
    } catch (_) {
      for (final group in _groups.values) {
        group.uncertain = true;
      }
    } finally {
      _changed();
    }
  }

  Future<void> _refreshRoom(String id, _WatchedGroup group) async {
    final state = await read('groups.state', {
      'room_id': id,
      'include_disbanded': true,
    });
    if (_closed) return;
    final room = _map(state['room']);
    if (room['room_id'] != id) {
      throw const FormatException('Wrong group state owner');
    }
    if (room['disbanded_at'] != null) {
      final disbanded = room['disbanded_at'];
      if (disbanded is! num || !disbanded.isFinite) {
        throw const FormatException('Invalid group disband receipt');
      }
      group.working = false;
      group.pending = false;
      group.uncertain = false;
      return;
    }
    final driver = _map(state['driver_status']);
    if (room['room_id'] != id ||
        driver['working'] is! bool ||
        driver['blocked'] is! bool) {
      throw const FormatException('Invalid shared group state');
    }
    final latest = _sequence(room['latest_seq']);
    if (latest < group.cursor) {
      throw const FormatException('Group sequence moved backwards');
    }
    final working = driver['working'] == true || driver['blocked'] == true;
    if (working) {
      group.working = true;
      group.uncertain = false;
      _changed();
    }
    if (group.cursor < 0) {
      // First discovery is a quiet history baseline, including an active room.
      await _saveCursor(id, latest);
      if (_closed) return;
      group.cursor = latest;
    } else if (latest > group.cursor) {
      group.pending = true;
      _changed();
      var cursor = group.cursor;
      Map<String, dynamic>? answer;
      do {
        final page = await read('groups.log', {
          'room_id': id,
          'since_seq': cursor,
          'limit': 100,
        });
        if (_closed) return;
        final authority = _map(page['authority']);
        if (authority['gateway_id'] is! String ||
            (authority['gateway_id'] as String).isEmpty ||
            _sequence(authority['epoch']) < 1 ||
            page['events'] is! List ||
            page['has_more'] is! bool) {
          throw const FormatException('Invalid group log');
        }
        final next = _sequence(page['cursor']),
            end = _sequence(page['latest_seq']);
        if (next < cursor ||
            next > end ||
            end < latest ||
            (page['has_more'] == true && next == cursor)) {
          throw const FormatException('Invalid group log cursor');
        }
        var previous = cursor;
        for (final raw in page['events'] as List) {
          final event = _map(raw);
          final seq = _sequence(event['seq']);
          if (event['room_id'] != id ||
              seq <= previous ||
              seq > next ||
              event['kind'] is! String) {
            throw const FormatException('Invalid group event owner');
          }
          previous = seq;
          if (event['kind'] == 'message.member') {
            final payload = _map(event['payload']);
            if (payload['text'] is! String) {
              throw const FormatException('Invalid group answer');
            }
            if ((payload['text'] as String).trim().isNotEmpty) answer = event;
          }
        }
        cursor = next;
        if (page['has_more'] != true) break;
      } while (!_closed);
      if (answer != null) {
        final sequence = answer['seq'] as int;
        // Actual viewport receipts, not opening a route, suppress read replies.
        final target = GroupNotificationTarget(scope, id);
        final readSequence = BotGroupReadState.savedSequence(
          preferences,
          target.key,
        );
        if (sequence > readSequence) {
          await publish(
            GroupAnswerNotification(
              target: target,
              title: group.title,
              instance: instance,
              sequence: sequence,
              text: _map(answer['payload'])['text'] as String,
            ),
          );
        }
        final reached = BotGroupReadState.savedSequence(
          preferences,
          target.key,
        );
        if (sequence <= reached) await clearRead(target, reached);
      }
      if (_closed) return;
      await _saveCursor(id, cursor);
      if (_closed) return;
      group.cursor = cursor;
      group.pending = false;
    }
    group.working = working;
    group.blocked = driver['blocked'] == true;
    group.pending = false;
    group.uncertain = false;
  }

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    super.dispose();
  }
}
