import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_account_usage.dart';

/// One account-report visit. The workspace retains authority over its route.
class ChatAccountUsageSession extends ChangeNotifier {
  ChatAccountUsageSession(this._authority, this._isCurrent, this._read) {
    _authority.addListener(_checkAuthority);
  }

  final Listenable _authority;
  final bool Function() _isCurrent;
  final Future<ChatAccountUsage> Function() _read;
  ChatAccountUsage? _report;
  String? _error;
  bool _loading = false, _retired = false, _closed = false;
  int _generation = 0;
  Future<void>? _pending;

  ChatAccountUsage? get report => _report;
  String? get error => _error;
  bool get loading => _loading;
  bool get retired => _retired;

  void _checkAuthority() {
    if (_closed || _retired || _isCurrent()) return;
    _retired = true;
    _generation++;
    _loading = false;
    _report = null;
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    _checkAuthority();
    if (_retired) return Future.value();
    if (_pending case final pending?) return pending;
    final completion = Completer<void>();
    _pending = completion.future;
    _loading = true;
    final generation = ++_generation;
    notifyListeners();
    unawaited(_load(generation, completion));
    return completion.future;
  }

  bool _accepts(int generation) {
    _checkAuthority();
    return !_closed && !_retired && generation == _generation;
  }

  Future<void> _load(int generation, Completer<void> completion) async {
    try {
      final value = await _read();
      if (_accepts(generation)) {
        _report = value;
        _error = null;
      }
    } catch (_) {
      if (_accepts(generation)) {
        _error = _report == null
            ? 'Account usage could not be loaded.'
            : 'Account usage could not be refreshed. Showing the last received report.';
      }
    } finally {
      _pending = null;
      if (_accepts(generation)) {
        _loading = false;
        notifyListeners();
      }
      completion.complete();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _authority.removeListener(_checkAuthority);
    super.dispose();
  }
}
