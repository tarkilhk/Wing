import 'package:flutter/foundation.dart';
import '../models/bots.dart';
import '../models/transcript_message.dart';
import 'bots_repository.dart';

/// One passive inspection route. No runtime admission, polling or commands.
class BotGroupHistorySession extends ChangeNotifier {
  BotGroupHistorySession(this.repository, this.group) {
    repository.retain();
  }

  final BotsRepository repository;
  final BotGroup group;
  BotGroupMember? _member;
  BotGroupMember? get member => _member;
  String? _session;
  int? _older;
  final _rows = <int, Map<String, dynamic>>{};
  bool _loading = false, _closed = false;
  int _generation = 0;
  String? _error;
  bool get loading => _loading;
  bool get hasOlder => _older != null;
  String? get error => _error;
  List<TranscriptMessage> get messages => [
    for (final id in _rows.keys.toList()..sort())
      TranscriptMessage.fromRow(_rows[id]!),
  ].where((message) => message.kind != TranscriptMessageKind.hidden).toList();

  Future<void> select(BotGroupMember member) async {
    if (_closed) return;
    _member = member;
    _session = null;
    _older = null;
    _rows.clear();
    await _load(refresh: true);
  }

  Future<void> refresh() async {
    if (_closed || _loading || _member == null) return;
    await _load(refresh: true);
  }

  Future<void> loadOlder() async {
    if (_closed || _loading || _older == null) return;
    await _load(refresh: false);
  }

  Future<void> _load({required bool refresh}) async {
    final member = _member!;
    final generation = ++_generation;
    _loading = true;
    _error = null;
    notifyListeners();
    repository.retain();
    try {
      final session = refresh
          ? await repository.groupMemberSession(group, member)
          : _session;
      if (_closed || generation != _generation) return;
      if (session == null) {
        _session = null;
        _older = null;
        _rows.clear();
        return;
      }
      final page = await repository.groupMemberHistory(
        group,
        member,
        session,
        refresh ? 0 : _older!,
      );
      if (_closed || generation != _generation) return;
      // Validate the complete page before replacing a previously readable one.
      final rows = <int, Map<String, dynamic>>{};
      for (final row in page.rows) {
        final id = row['id'];
        if (id is! int || rows.containsKey(id)) {
          throw const FormatException('Invalid worker history row');
        }
        rows[id] = Map.unmodifiable(row);
      }
      if (refresh) _rows.clear();
      _rows.addAll(rows);
      _session = session;
      _older = page.nextOffset;
    } catch (_) {
      if (!_closed && generation == _generation) {
        _error = 'Working history could not load. Refresh to try again.';
      }
    } finally {
      repository.release();
      if (!_closed && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    ++_generation;
    repository.release();
    super.dispose();
  }
}
