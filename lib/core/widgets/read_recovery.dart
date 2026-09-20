import 'package:flutter/material.dart';

import '../services/network_availability.dart';

/// Gives a visible screen another chance to read after focus or network return.
/// The caller owns error classification and presentation. [retry] must handle
/// its errors and must only observe state, never replay a user mutation.
class ReadRecovery extends StatefulWidget {
  final bool Function() shouldRetry;
  final Future<void> Function() retry;
  final Widget child;

  const ReadRecovery({
    super.key,
    required this.shouldRetry,
    required this.retry,
    required this.child,
  });

  @override
  State<ReadRecovery> createState() => _ReadRecoveryState();
}

class _ReadRecoveryState extends State<ReadRecovery>
    with WidgetsBindingObserver {
  bool? _current;
  bool _active = true;
  bool _scheduled = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _active =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    NetworkAvailability.restored.addListener(_recover);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasCurrent = _current;
    _current = ModalRoute.isCurrentOf(context) ?? true;
    // Initial loading belongs to the screen; only recover on a return.
    if (wasCurrent == false && _current!) _recover();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = _active;
    _active = state == AppLifecycleState.resumed;
    if (!wasActive && _active) _recover();
  }

  bool get _visible => mounted && _active && _current == true;

  void _recover() {
    if (!_visible || _scheduled || _running) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!_visible || _running || !widget.shouldRetry()) return;
      _running = true;
      try {
        await widget.retry();
      } finally {
        _running = false;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    NetworkAvailability.restored.removeListener(_recover);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
