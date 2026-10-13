import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/wing_theme.dart';

/// Fixed live-work controls. The anchored overlay never changes composer layout.
class ProfileLiveWorkDock extends StatefulWidget {
  const ProfileLiveWorkDock({
    super.key,
    required this.taskCount,
    required this.completedTasks,
    required this.subagentCount,
    required this.tasks,
    required this.subagents,
    required this.onAgentsSelected,
  });

  static const slideDuration = Duration(milliseconds: 220);
  final int? taskCount, completedTasks, subagentCount;
  final Widget tasks, subagents;
  final Future<void> Function() onAgentsSelected;

  @override
  State<ProfileLiveWorkDock> createState() => _ProfileLiveWorkDockState();
}

class _ProfileLiveWorkDockState extends State<ProfileLiveWorkDock>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _target = GlobalKey();
  final _pages = PageController();
  late final AnimationController _reveal;
  bool _open = false, _refreshingAgents = false, _openingPages = false;
  int _selected = 0, _generation = 0;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  Future<void> _refreshAgents() async {
    if (_refreshingAgents) return;
    setState(() => _refreshingAgents = true);
    try {
      await widget.onAgentsSelected();
    } catch (_) {
      // The borrowed supervision panel owns the error and retry action.
    } finally {
      if (mounted) setState(() => _refreshingAgents = false);
    }
  }

  void _select(int index, {bool keyboard = false}) {
    if (_open && index == _selected) {
      _close(keyboard: keyboard);
      return;
    }
    final wasOpen = _open;
    ++_generation;
    setState(() {
      _open = true;
      _selected = index;
    });
    _portal.show();
    if (!wasOpen) {
      _openingPages = true;
      if (_reduced || keyboard) {
        _reveal.value = 1;
      } else {
        _reveal.forward();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _open && _pages.hasClients) {
          _pages.jumpToPage(index);
          _openingPages = false;
        }
      });
    } else if (_pages.hasClients) {
      if (_reduced || keyboard) {
        _pages.jumpToPage(index);
      } else {
        _pages.animateToPage(
          index,
          duration: ProfileLiveWorkDock.slideDuration,
          curve: const _WorkPageCurve(),
        );
      }
    }
    if (index == 0) _refreshAgents();
  }

  Future<void> _close({bool keyboard = false}) async {
    final generation = ++_generation;
    setState(() => _open = false);
    if (_reduced || keyboard) {
      _reveal.value = 0;
    } else {
      try {
        await _reveal.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted && generation == _generation && !_open) _portal.hide();
  }

  @override
  void dispose() {
    ++_generation;
    _pages.dispose();
    _reveal.dispose();
    super.dispose();
  }

  Widget _bar(double width, double height, {required bool overlay}) {
    final tokens = WingTokens.of(context);
    final large = MediaQuery.textScalerOf(context).scale(12) > 16;
    final labels = [
      widget.subagentCount == null
          ? 'Subagents'
          : '${widget.subagentCount} subagents',
      widget.taskCount == null
          ? 'Tasks'
          : 'Tasks ${widget.completedTasks}/${widget.taskCount}',
    ];
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent || !_open) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _close(keyboard: true);
          return KeyEventResult.handled;
        }
        final index = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowLeft => 0,
          LogicalKeyboardKey.arrowRight => 1,
          _ => null,
        };
        if (index == null) return KeyEventResult.ignored;
        if (_selected != index) _select(index, keyboard: true);
        return KeyEventResult.handled;
      },
      child: SizedBox(
        width: width,
        height: height + 12,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: Border(
                    top: BorderSide(color: tokens.border),
                    left: BorderSide(color: tokens.border),
                    right: BorderSide(color: tokens.border),
                  ),
                  borderRadius: overlay
                      ? null
                      : const BorderRadius.vertical(top: Radius.circular(8)),
                ),
              ),
            ),
            if (_open && overlay)
              AnimatedBuilder(
                animation: _pages,
                builder: (_, _) {
                  final progress =
                      _pages.hasClients && _pages.position.hasContentDimensions
                      ? (_pages.page ?? _selected.toDouble()).clamp(0.0, 1.0)
                      : _selected.toDouble();
                  return Positioned(
                    left: 3 + progress * width / 2,
                    bottom: 3,
                    width: width / 2 - 6,
                    height: height - 6,
                    child: DecoratedBox(
                      key: const ValueKey('live-work-selection'),
                      decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: .13),
                        border: Border.all(
                          color: tokens.accent.withValues(alpha: .35),
                        ),
                        borderRadius: WingRadius.control,
                      ),
                    ),
                  );
                },
              ),
            if (!_open)
              Positioned(
                left: width / 2,
                bottom: (height - 16) / 2,
                child: Container(
                  key: const ValueKey('live-work-divider'),
                  width: 1,
                  height: 16,
                  color: Color.lerp(tokens.border, tokens.muted, .4),
                ),
              ),
            Positioned.fill(
              child: Row(
                children: [
                  for (var index = 0; index < 2; index++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        expanded: _open && _selected == index,
                        label: labels[index],
                        child: StudioButtonPress(
                          child: TextButton(
                            key: ValueKey(('live-work-tab', index, overlay)),
                            onPressed: () => _select(index),
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: _open && _selected == index
                                  ? tokens.accent
                                  : tokens.muted,
                              shape: const RoundedRectangleBorder(),
                            ),
                            child: Row(
                              children: [
                                if (!large) ...[
                                  SizedBox.square(
                                    dimension: 16,
                                    child: index == 0 && _refreshingAgents
                                        ? const CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            semanticsLabel:
                                                'Refreshing subagents',
                                          )
                                        : Icon(
                                            index == 0
                                                ? Icons.people_outline
                                                : Icons.checklist,
                                            size: 16,
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    labels[index],
                                    maxLines: 2,
                                    style: TextStyle(
                                      fontSize: large ? 11 : 12,
                                      height: 1.1,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (large && index == 0 && _refreshingAgents)
                                  const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      semanticsLabel: 'Refreshing subagents',
                                    ),
                                  )
                                else
                                  Icon(
                                    _open && _selected == index
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.keyboard_arrow_up_rounded,
                                    size: 16,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_open,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _open) _close(keyboard: true);
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = math.max(
          36.0,
          MediaQuery.textScalerOf(context).scale(12) * 3,
        );
        return OverlayPortal(
          controller: _portal,
          // Measure the anchor during overlay layout, after the composer has
          // moved for an IME inset. Build-time coordinates lag by one layout.
          overlayChildBuilder: (context) => LayoutBuilder(
            builder: (context, _) {
              final box =
                  _target.currentContext!.findRenderObject()! as RenderBox;
              final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
              final query = MediaQuery.of(context);
              final available = math.max(
                48.0,
                bottom - height - query.padding.top - 56,
              );
              final panelHeight = math.min(
                available,
                math.min(470.0, query.size.height * .55),
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: ModalBarrier(
                      color: Colors.black.withValues(alpha: .54),
                      dismissible: true,
                      onDismiss: _close,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: CompositedTransformFollower(
                      link: _link,
                      targetAnchor: Alignment.bottomLeft,
                      followerAnchor: Alignment.bottomLeft,
                      showWhenUnlinked: false,
                      child: SizedBox(
                        width: width,
                        height: panelHeight + height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: height,
                              height: panelHeight,
                              child: AnimatedBuilder(
                                animation: _reveal,
                                builder: (_, child) => Align(
                                  alignment: Alignment.bottomCenter,
                                  child: ClipRect(
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      heightFactor: Curves.easeOutCubic
                                          .transform(_reveal.value),
                                      child: child,
                                    ),
                                  ),
                                ),
                                child: Material(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLow,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      color: WingTokens.of(context).border,
                                    ),
                                    borderRadius: WingRadius.sheet,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: WingRadius.sheet,
                                    child: PageView(
                                      controller: _pages,
                                      pageSnapping: false,
                                      allowImplicitScrolling: true,
                                      physics: _WorkPagePhysics(
                                        reducedMotion: _reduced,
                                      ),
                                      onPageChanged: (index) {
                                        if (!_openingPages &&
                                            _selected != index) {
                                          setState(() => _selected = index);
                                          if (index == 0) _refreshAgents();
                                        }
                                      },
                                      children: [
                                        _WorkPage(
                                          key: const PageStorageKey(
                                            'live-subagents',
                                          ),
                                          child: widget.subagents,
                                        ),
                                        _WorkPage(
                                          key: const PageStorageKey(
                                            'live-tasks',
                                          ),
                                          child: widget.tasks,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _bar(width, height, overlay: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          child: CompositedTransformTarget(
            key: _target,
            link: _link,
            child: ExcludeSemantics(
              excluding: _portal.isShowing,
              child: _bar(width, height, overlay: false),
            ),
          ),
        );
      },
    ),
  );
}

class _WorkPage extends StatefulWidget {
  const _WorkPage({super.key, required this.child});
  final Widget child;
  @override
  State<_WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<_WorkPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: widget.child,
    );
  }
}

class _WorkPagePhysics extends PageScrollPhysics {
  const _WorkPagePhysics({required this.reducedMotion, super.parent});
  final bool reducedMotion;
  @override
  _WorkPagePhysics applyTo(ScrollPhysics? ancestor) => _WorkPagePhysics(
    reducedMotion: reducedMotion,
    parent: buildParent(ancestor),
  );
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final width = position.viewportDimension;
    if (width == 0) return null;
    var page = position.pixels / width;
    if (velocity < -toleranceFor(position).velocity) page -= .5;
    if (velocity > toleranceFor(position).velocity) page += .5;
    final target = (page.round() * width).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < .01) return null;
    return _WorkPageSimulation(
      position.pixels,
      target,
      reducedMotion
          ? 0
          : ProfileLiveWorkDock.slideDuration.inMicroseconds / 1000000,
    );
  }
}

class _WorkPageSimulation extends Simulation {
  _WorkPageSimulation(this.start, this.end, this.duration);
  final double start, end, duration;
  @override
  double x(double time) => duration == 0
      ? end
      : start +
            (end - start) *
                const _WorkPageCurve().transform(
                  (time / duration).clamp(0.0, 1.0),
                );
  @override
  double dx(double time) => duration == 0 || time >= duration
      ? 0
      : (end - start) * 3 * math.pow(1 - time / duration, 2) / duration;
  @override
  bool isDone(double time) => time >= duration;
}

class _WorkPageCurve extends Curve {
  const _WorkPageCurve();
  @override
  double transformInternal(double t) => 1 - math.pow(1 - t, 3).toDouble();
}
