import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bots.dart';
import 'bots_repository.dart';

/// Read-only stock screen frames. Never acquires a human keyboard lease.
class BotScreenSession extends ChangeNotifier {
  BotScreenSession(this.repository, this.bot) {
    repository.retain();
  }
  final BotsRepository repository;
  final BotRecord bot;
  BotScreenFrame? _frame;
  BotScreenFrame? get frame => _frame;
  String? _error;
  String? get error => _error;
  bool _closed = false, _busy = false, _visible = false;
  bool get busy => _busy;
  Timer? _poll;
  void setVisible(bool visible) {
    _visible = visible;
    _poll?.cancel();
    if (visible && !_closed) {
      unawaited(refresh());
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh() async {
    if (_closed || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final value = await repository.screen(bot);
      if (!_closed && _visible) {
        _frame = value;
        _error = null;
      }
    } catch (_) {
      if (!_closed) {
        _frame = null;
        _error =
            'Screen could not be loaded. Check this profile’s desktop setup.';
      }
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> power(bool start) async {
    if (_closed || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      await repository.screenPower(bot, start, () => !_closed, () {});
    } catch (_) {
      if (!_closed) _error = 'Screen change could not be confirmed.';
    } finally {
      if (!_closed) {
        _busy = false;
        notifyListeners();
        unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    repository.release();
    super.dispose();
  }
}
