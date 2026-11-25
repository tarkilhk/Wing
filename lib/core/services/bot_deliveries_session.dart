import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/bot_delivery.dart';
import '../models/bots.dart';
import 'bots_repository.dart';

/// One visible canonical Bot Chat's read-only sender-delivery visit.
/// Polls empty snapshots too; Hermes supplies no delivery-change event.
class BotDeliveriesSession extends ChangeNotifier {
  BotDeliveriesSession({required this.sender, required this.repository}) {
    if (sender.chat == null) throw ArgumentError('Canonical Bot Chat required');
    repository.retain();
  }
  final BotRecord sender;
  final BotsRepository repository;
  BotDeliveriesObservation _state = BotDeliveriesObservation();
  BotDeliveriesObservation get state => _state;
  Timer? _timer;
  Future<void>? _pending;
  int _generation = 0, _readGeneration = -1;
  bool _active = false, _closed = false, _again = false, _explicit = false;
  bool get active => _active && !_closed;

  void setActive(bool value) {
    if (_closed || value == _active) return;
    _active = value;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _explicit = false;
    _state = BotDeliveriesObservation(
      deliveries: _state.deliveries,
      error: _state.error,
    );
    // Visibility is forwarded during composition; the first read publishes
    // asynchronously and cannot notify a parent in the middle of build.
    if (value) {
      _timer = Timer(Duration.zero, () {
        _timer = null;
        unawaited(refresh(explicit: false));
      });
    }
  }

  Future<void> refresh({bool explicit = true}) {
    if (!active) return Future.value();
    _timer?.cancel();
    _timer = null;
    if (explicit && !_explicit) {
      _explicit = true;
      _publish(refreshing: true, error: _state.error);
    }
    if (_pending case final pending?) {
      if (_readGeneration != _generation) _again = true;
      return pending;
    }
    final completion = Completer<void>();
    _pending = completion.future;
    unawaited(_read(completion));
    return completion.future;
  }

  Future<void> _read(Completer<void> completion) async {
    do {
      _again = false;
      final generation = _readGeneration = _generation;
      try {
        final rows = await repository.senderDeliveries(sender);
        if (active && generation == _generation) {
          _state = BotDeliveriesObservation(
            deliveries: rows,
            refreshing: _explicit,
          );
          notifyListeners();
        }
      } catch (_) {
        if (active && generation == _generation) {
          _publish(
            refreshing: _explicit,
            error: _state.deliveries.isEmpty
                ? 'Teammate deliveries could not be loaded.'
                : 'Teammate deliveries could not be refreshed. Showing last received status.',
          );
        }
      }
    } while (active && _again);
    _pending = null;
    if (active && _readGeneration == _generation) {
      _explicit = false;
      _publish(refreshing: false, error: _state.error);
      if (_state.error == null && _timer == null) {
        _timer = Timer(const Duration(seconds: 5), () {
          _timer = null;
          unawaited(refresh(explicit: false));
        });
      }
    }
    completion.complete();
  }

  void _publish({required bool refreshing, String? error}) {
    _state = BotDeliveriesObservation(
      deliveries: _state.deliveries,
      refreshing: refreshing,
      error: error,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _timer?.cancel();
    repository.release();
    super.dispose();
  }
}
