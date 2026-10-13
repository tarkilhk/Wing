import 'package:flutter/foundation.dart';
import '../models/bots.dart';
import '../models/transcript_reader.dart';
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
  _BotGroupHistoryReading _reading = _BotGroupHistoryReading(null);
  TranscriptReader get reader => _reading;
  bool get historyAvailable => _reading._available;
  bool _closed = false;
  int _generation = 0;

  Future<void> select(BotGroupMember member) async {
    if (_closed) return;
    _member = member;
    _reading = _BotGroupHistoryReading(member.id);
    await _load(refresh: true);
  }

  Future<void> refresh() async {
    if (_closed || _reading._loading || _member == null) return;
    await _load(refresh: true);
  }

  Future<void> loadOlder() async {
    if (_closed || _reading._loading || _reading._older == null) return;
    await _load(refresh: false);
  }

  Future<void> _load({required bool refresh}) async {
    final member = _member!;
    final reading = _reading;
    final generation = ++_generation;
    reading._loading = true;
    reading._paging = !refresh;
    reading._error = null;
    notifyListeners();
    repository.retain();
    try {
      final session = refresh
          ? await repository.groupMemberSession(group, member)
          : reading._session;
      if (_closed || generation != _generation) return;
      if (session == null) {
        reading._session = null;
        reading._older = null;
        reading._rows.clear();
        reading._available = true;
        return;
      }
      final page = await repository.groupMemberHistory(
        group,
        member,
        session,
        refresh ? 0 : reading._older!,
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
      if (refresh) reading._rows.clear();
      reading._rows.addAll(rows);
      reading._session = session;
      reading._older = page.nextOffset;
      reading._available = true;
    } catch (_) {
      if (!_closed && generation == _generation) {
        reading._error =
            'Working history could not load. Refresh to try again.';
      }
    } finally {
      repository.release();
      if (!_closed && generation == _generation) {
        reading._loading = false;
        reading._paging = false;
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

/// A retired member keeps its own local scroll memory until its viewport disposes.
/// It holds saved facts only; all I/O remains in BotGroupHistorySession.
final class _BotGroupHistoryReading implements TranscriptReader {
  _BotGroupHistoryReading(this._memberId);
  final String? _memberId;
  String? _session;
  int? _older;
  final _rows = <int, Map<String, dynamic>>{};
  bool _loading = false;
  bool _paging = false;
  bool _available = false;
  String? _error;
  double _scrollOffset = 0;
  @override
  bool get historyLoading => _loading;
  @override
  bool get historyPaging => _loading && _paging;
  @override
  int? get nextHistoryOffset => _older;
  @override
  String? get historyError => _error;
  @override
  String? get historySessionId => _session;
  @override
  bool get historyUnavailable => false;
  @override
  String get streaming => '';
  @override
  double get historyScrollOffset => _scrollOffset;
  @override
  void recordScrollOffset(double offset) => _scrollOffset = offset;
  @override
  Object messagePresentationId(Map<String, dynamic> row) =>
      (_memberId, row['id']);
  @override
  List<Map<String, dynamic>> get messages => List.unmodifiable([
    for (final id in _rows.keys.toList()..sort()) _rows[id]!,
  ]);
}
