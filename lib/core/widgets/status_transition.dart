import 'package:flutter/material.dart';

import '../theme/wing_theme.dart';

/// Reveals transient status without reserving space while it is absent.
class StatusTransition extends StatelessWidget {
  const StatusTransition({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child ?? const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: WingMotion.standard,
      switchInCurve: WingMotion.curve,
      switchOutCurve: WingMotion.curve,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: animation,
          alwaysIncludeSemantics: true,
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [
          for (final child in previous)
            ExcludeSemantics(child: IgnorePointer(child: child)),
          ?current,
        ],
      ),
      // Text changes update in place; only presence changes animate.
      child: child == null
          ? const SizedBox.shrink(key: ValueKey('status-hidden'))
          : KeyedSubtree(key: const ValueKey('status-visible'), child: child!),
    );
  }
}
