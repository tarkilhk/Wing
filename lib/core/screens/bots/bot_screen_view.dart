import 'dart:async';
import '../../widgets/studio_loading.dart';
import 'package:flutter/material.dart';
import '../../services/bot_screen_session.dart';
import '../../services/bot_screen_window.dart';
import '../../widgets/bot_display_viewport.dart';
import '../../widgets/bot_display_surface.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';
import '../../widgets/server_connection_label.dart';
import '../../theme/wing_theme.dart';

class BotScreenView extends StatefulWidget {
  const BotScreenView({super.key, required this.createSession});
  final BotScreenSession Function() createSession;
  @override
  State<BotScreenView> createState() => _BotScreenViewState();
}

class _BotScreenViewState extends State<BotScreenView>
    with WidgetsBindingObserver {
  late final _session = widget.createSession();
  final _typing = TextEditingController(text: '\u200b');
  final _focus = FocusNode();
  bool _resettingKeyboard = false;
  bool _keyboard = false, _leaving = false, _canPop = false;
  bool _more = false, _barAtTop = false, _foreground = true;
  bool? _landscape, _manualFullscreen, _windowFullscreen;
  String? _windowError;
  double _lastKeyboardInset = 0;
  Timer? _restoreBars, _imeBackExpiry;
  bool _imeBackPending = false;
  final _modifiers = <int>{};
  late final _viewport = BotDisplayViewport(onPointer: _session.pointer);
  bool get _fullscreen => _manualFullscreen ?? (_landscape == true);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    _typing.addListener(_type);
    _session.setVisible(true);
  }

  void _changed() {
    if (!mounted) return;
    if (!_session.canInput) {
      _modifiers.clear();
      _viewport.setInput(false);
      _resetKeyboard();
    }
    if (!_foreground || !_session.controlling || !_session.connected) {
      _keyboard = false;
      _focus.unfocus();
    }
    setState(() {});
  }

  void _resetKeyboard() {
    _resettingKeyboard = true;
    _typing.value = const TextEditingValue(
      text: '\u200b',
      selection: TextSelection.collapsed(offset: 1),
    );
    _resettingKeyboard = false;
  }

  void _type() {
    if (_resettingKeyboard ||
        !_session.canInput ||
        !_typing.value.composing.isCollapsed) {
      return;
    }
    final text = _typing.text;
    if (text.isEmpty) {
      _session.key(0xff08, modifiers: _modifiers);
    } else {
      _session.typeText(text.replaceAll('\u200b', ''), modifiers: _modifiers);
    }
    _resetKeyboard();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final released = await _session.close();
    if (!mounted) return;
    _leaving = false;
    if (released) {
      setState(() {
        _canPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _handBack() async {
    if (_session.controlling) {
      await _session.handBack();
      return;
    }
    final force = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hand control back?'),
        content: const Text(
          'This releases the current human controller, including another device, and lets the bot use its screen.',
        ),
        actions: [
          StudioButtonPress(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
          StudioButtonPress(
            child: TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hand back'),
            ),
          ),
        ],
      ),
    );
    if (force == true && mounted) await _session.handBack(force: true);
  }

  Future<void> _takeOver() async {
    if (_session.humanHasControl) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Take control from another device?'),
          content: const Text(
            'The current controller will return to watching the screen.',
          ),
          actions: [
            StudioButtonPress(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            StudioButtonPress(
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Take control'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _session.takeOver();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // System UI overlays can temporarily remove focus. Changing immersion on
    // inactive/resumed would repeatedly dismiss/reopen Android's first-use tip.
    _foreground =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    _session.setFocused(state == AppLifecycleState.resumed);
    _session.setVisible(_foreground);
    _syncWindow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _restoreBars?.cancel();
    _imeBackExpiry?.cancel();
    _viewport.dispose();
    unawaited(BotScreenWindow.setImmersive(false));
    _session.dispose();
    _typing.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _syncWindow() {
    final desired = _fullscreen && _foreground;
    if (_windowFullscreen == desired) return;
    _windowFullscreen = desired;
    unawaited(
      BotScreenWindow.setImmersive(desired).catchError((Object _) {
        if (mounted) {
          setState(
            () => _windowError =
                'Phone fullscreen could not be updated. Exit fullscreen and try again.',
          );
        }
      }),
    );
  }

  @override
  void didChangeMetrics() {
    final inset = View.of(context).viewInsets.bottom;
    if (_lastKeyboardInset > 0 && inset == 0) {
      // Android may hide IME before forwarding that same Back to Flutter.
      // Consume its route callback once, without acting on the next UI layer.
      if (_keyboard) {
        _imeBackPending = true;
        _imeBackExpiry?.cancel();
        _imeBackExpiry = Timer(const Duration(milliseconds: 350), () {
          _imeBackPending = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _keyboard) _hideKeyboard();
      });
      _restoreBars?.cancel();
      _restoreBars = Timer(const Duration(milliseconds: 1200), () {
        _windowFullscreen = null;
        if (mounted) _syncWindow();
      });
    }
    _lastKeyboardInset = inset;
  }

  void _hideKeyboard() {
    _focus.unfocus();
    _resetKeyboard();
    setState(() => _keyboard = false);
  }

  void _toggleKeyboard() {
    _imeBackPending = false;
    _imeBackExpiry?.cancel();
    if (_keyboard) {
      _hideKeyboard();
      return;
    }
    setState(() {
      _keyboard = true;
      _more = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keyboard) _focus.requestFocus();
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _manualFullscreen = !_fullscreen;
      _more = false;
      _windowError = null;
    });
    _syncWindow();
  }

  void _back() {
    if (_imeBackPending) {
      _imeBackPending = false;
      _imeBackExpiry?.cancel();
    } else if (_keyboard) {
      _hideKeyboard();
    } else if (_more) {
      setState(() => _more = false);
    } else if (_fullscreen) {
      _toggleFullscreen();
    } else {
      _leave();
    }
  }

  void _key(int value) {
    _session.key(value, modifiers: _modifiers);
    setState(() => _more = false);
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
  }) => Semantics(
    selected: selected,
    child: StudioButtonPress(
      child: IconButton(
        tooltip: label,
        onPressed: action,
        style: selected
            ? IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
              )
            : null,
        icon: Icon(icon),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    ),
  );

  Widget _commands() {
    Widget command(
      String label,
      IconData icon,
      VoidCallback action, {
      bool input = false,
      bool selected = false,
    }) => _action(
      label,
      icon,
      input && !_session.canInput ? null : action,
      selected: selected,
    );
    Widget modifier(String label, IconData icon, int key) => command(
      label,
      icon,
      () => setState(() {
        if (!_modifiers.add(key)) _modifiers.remove(key);
      }),
      input: true,
      selected: _modifiers.contains(key),
    );
    return SingleChildScrollView(
      child: Wrap(
        children: [
          command(
            'Use trackpad',
            Icons.mouse_outlined,
            () => _viewport.setMode(BotPointerMode.trackpad),
            selected: _viewport.mode == BotPointerMode.trackpad,
          ),
          command(
            'Use direct touch',
            Icons.touch_app_outlined,
            () => _viewport.setMode(BotPointerMode.direct),
            selected: _viewport.mode == BotPointerMode.direct,
          ),
          command(
            'Move view',
            Icons.open_with,
            () => _viewport.setMode(BotPointerMode.pan),
            selected: _viewport.mode == BotPointerMode.pan,
          ),
          command('Zoom in', Icons.zoom_in, () => _viewport.zoom(1.3)),
          command('Zoom out', Icons.zoom_out, () => _viewport.zoom(1 / 1.3)),
          command('Fit screen', Icons.fit_screen, _viewport.fit),
          command(
            'Left click',
            Icons.ads_click,
            () => _viewport.click(1),
            input: true,
          ),
          command(
            'Right click',
            Icons.more_horiz,
            () => _viewport.click(4),
            input: true,
          ),
          command(
            'Hold mouse button',
            Icons.drag_indicator,
            () => _viewport.drag(_viewport.buttons == 0),
            input: true,
            selected: _viewport.buttons != 0,
          ),
          command(
            'Enter',
            Icons.keyboard_return,
            () => _key(0xff0d),
            input: true,
          ),
          command('Tab', Icons.keyboard_tab, () => _key(0xff09), input: true),
          command(
            'Escape',
            Icons.cancel_outlined,
            () => _key(0xff1b),
            input: true,
          ),
          command(
            'Backspace',
            Icons.backspace_outlined,
            () => _key(0xff08),
            input: true,
          ),
          modifier('Control modifier', Icons.keyboard_control_key, 0xffe3),
          modifier('Alt modifier', Icons.alt_route, 0xffe9),
          modifier('Shift modifier', Icons.keyboard_capslock, 0xffe1),
          command(
            'Left arrow',
            Icons.keyboard_arrow_left,
            () => _key(0xff51),
            input: true,
          ),
          command(
            'Up arrow',
            Icons.keyboard_arrow_up,
            () => _key(0xff52),
            input: true,
          ),
          command(
            'Right arrow',
            Icons.keyboard_arrow_right,
            () => _key(0xff53),
            input: true,
          ),
          command(
            'Down arrow',
            Icons.keyboard_arrow_down,
            () => _key(0xff54),
            input: true,
          ),
          command(
            'Scroll up',
            Icons.arrow_upward,
            () => _viewport.click(8),
            input: true,
          ),
          command(
            'Scroll down',
            Icons.arrow_downward,
            () => _viewport.click(16),
            input: true,
          ),
          command('Refresh screen', Icons.refresh, _session.refresh),
          if (_session.status?.running == true)
            _action(
              'Stop screen',
              Icons.stop_outlined,
              _session.canStop ? () => _session.power(false) : null,
            )
          else
            _action(
              'Start screen',
              Icons.play_arrow_outlined,
              _session.canStart ? () => _session.power(true) : null,
            ),
          if (_session.humanHasControl && !_session.controlling)
            _action(
              'Hand control back (force)',
              Icons.pan_tool_outlined,
              _session.busy ? null : _handBack,
            ),
          command(
            'Gesture help',
            Icons.help_outline,
            () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                content: const SingleChildScrollView(
                  child: Text(
                    'Trackpad: move one finger to move the pointer, tap to click, hold and move to drag. Pinch to zoom; move two fingers to scroll.\n\n'
                    'Direct touch: tap the target to click; hold and move to drag. Use two fingers to move the view and pinch to zoom.\n\n'
                    'Move view: drag to pan without sending input. Zoom buttons and Fit screen are available in this tray.\n\n'
                    'Keyboard: the view keeps its magnification and brings your last clicked point into view. You can move the view if the text caret has moved.',
                  ),
                ),
                actions: [
                  _action(
                    'Close help',
                    Icons.close,
                    () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          command('Close screen', Icons.arrow_back, _leave),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    if (_landscape != landscape) {
      _landscape = landscape;
      _manualFullscreen = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncWindow();
      });
    }
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final colors = Theme.of(context).colorScheme;
    final status = _session.status;
    final control = _session.controlling
        ? 'You have control'
        : _session.humanHasControl
        ? 'Human has control'
        : _session.connected
        ? 'Bot has control'
        : 'Screen offline';
    final message =
        _windowError ??
        _session.error ??
        (status == null
            ? null
            : !status.supported
            ? 'Bot Screen needs a supported Linux host.'
            : !status.installed
            ? 'Install the Bot Screen components on the bot’s host to use its screen.'
            : status.blocker ??
                  (!status.running
                      ? 'Start the bot’s screen to view it.'
                      : null));
    return StudioLoadingFrame(
      child: PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _back();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: _fullscreen
              ? null
              : WingAppBar(
                  context: context,
                  title: Text(
                    '${_session.bot.title} screen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: _action('Close screen', Icons.arrow_back, _leave),
                  contextRow: ServerConnectionLabel(
                    label: _session.bot.instance,
                    status: ServerConnectionScope.of(context),
                  ),
                ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final panelHeight = (bounds.maxHeight - inset - 80).clamp(
                  48.0,
                  280.0,
                );
                return Stack(
                  children: [
                    Positioned.fill(
                      key: const ValueKey('bot-screen-display'),
                      top: _barAtTop ? 56 : 0,
                      child: _session.frame == null
                          ? const Center(
                              child: Icon(
                                Icons.desktop_windows_outlined,
                                size: 48,
                              ),
                            )
                          : BotDisplaySurface(
                              frame: _session.frame!,
                              viewport: _viewport,
                              canInput: _session.canInput,
                              keyboardInset: inset,
                              barInset: _barAtTop ? 0 : 56,
                            ),
                    ),
                    if ((_session.busy || _session.connecting) &&
                        !_session.canInput)
                      Positioned.fill(
                        child: StudioPageLoading.waiting(
                          key: const ValueKey('bot-screen-progress'),
                          label: 'Connecting to bot screen',
                        ),
                      ),
                    if (message != null)
                      Positioned(
                        key: const ValueKey('bot-screen-error'),
                        top: _barAtTop ? 64 : 8,
                        left: 16,
                        right: 16,
                        child: Material(
                          color: colors.surface,
                          borderRadius: WingRadius.card,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: panelHeight),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_session.error != null ||
                                      _windowError != null)
                                    StudioError(message)
                                  else
                                    Text(message),
                                  if (status?.installed == false &&
                                      status?.installCommand != null)
                                    SelectableText(status!.installCommand!),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_keyboard &&
                        _foreground &&
                        _session.controlling &&
                        _session.connected)
                      Positioned(
                        key: const ValueKey('bot-screen-keyboard'),
                        left: 0,
                        top: 0,
                        width: 1,
                        height: 1,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0,
                            child: TextField(
                              controller: _typing,
                              focusNode: _focus,
                              // Desktop gestures and controls share this bridge.
                              // Only explicit keyboard dismissal should unfocus it.
                              onTapOutside: (_) {},
                              obscureText: true,
                              obscuringCharacter: '\u200b',
                              autocorrect: false,
                              enableSuggestions: false,
                              enableIMEPersonalizedLearning: false,
                              enableInteractiveSelection: false,
                              decoration: const InputDecoration.collapsed(
                                hintText: 'Type on the bot’s screen',
                              ),
                              onSubmitted: (_) {
                                _key(0xff0d);
                                _focus.requestFocus();
                              },
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      key: const ValueKey('bot-screen-controls'),
                      left: 8,
                      right: 8,
                      top: _barAtTop ? 8 : null,
                      bottom: _barAtTop ? null : inset + 8,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 650),
                          child: Material(
                            color: colors.surface.withValues(alpha: .94),
                            borderRadius: WingRadius.card,
                            child: AnimatedBuilder(
                              animation: _viewport,
                              builder: (context, _) => SizedBox(
                                height: 48,
                                child: Row(
                                  children: [
                                    if (_fullscreen) const StudioLoadingSlot(),
                                    GestureDetector(
                                      onVerticalDragUpdate: (e) {
                                        if (e.delta.dy.abs() > 1) {
                                          setState(() {
                                            _barAtTop = e.delta.dy < 0;
                                            _more = false;
                                          });
                                        }
                                      },
                                      child: _action(
                                        'Move controls',
                                        Icons.drag_handle,
                                        () => setState(() {
                                          _barAtTop = !_barAtTop;
                                          _more = false;
                                        }),
                                      ),
                                    ),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, statusBounds) => Tooltip(
                                          message: control,
                                          child: Semantics(
                                            label: control,
                                            liveRegion: true,
                                            child: ExcludeSemantics(
                                              child: Text(
                                                statusBounds.maxWidth < 110 ||
                                                        MediaQuery.textScalerOf(
                                                              context,
                                                            ).scale(13) >
                                                            18
                                                    ? _session.controlling
                                                          ? 'You'
                                                          : _session
                                                                .humanHasControl
                                                          ? 'Held'
                                                          : _session.connected
                                                          ? 'Bot'
                                                          : 'Off'
                                                    : control,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: _session.controlling
                                                      ? colors.error
                                                      : colors.onSurface,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _session.controlling
                                        ? _action(
                                            'Hand control back',
                                            Icons.pan_tool_outlined,
                                            _session.busy ? null : _handBack,
                                          )
                                        : _action(
                                            'Take control',
                                            Icons.touch_app_outlined,
                                            _session.canTakeOver
                                                ? _takeOver
                                                : null,
                                          ),
                                    _action(
                                      _keyboard
                                          ? 'Hide keyboard'
                                          : 'Show keyboard',
                                      Icons.keyboard_outlined,
                                      _session.canInput
                                          ? _toggleKeyboard
                                          : null,
                                      selected:
                                          _keyboard || _modifiers.isNotEmpty,
                                    ),
                                    _action(
                                      'More screen controls',
                                      Icons.more_horiz,
                                      () => setState(() => _more = !_more),
                                      selected:
                                          _more ||
                                          _modifiers.isNotEmpty ||
                                          _viewport.buttons != 0,
                                    ),
                                    _action(
                                      _fullscreen
                                          ? 'Exit fullscreen'
                                          : 'Enter fullscreen',
                                      _fullscreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      _toggleFullscreen,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_more)
                      Positioned(
                        key: const ValueKey('bot-screen-more'),
                        left: 8,
                        right: 8,
                        top: _barAtTop ? 64 : null,
                        bottom: _barAtTop ? null : inset + 64,
                        child: Material(
                          color: colors.surface,
                          borderRadius: WingRadius.card,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: panelHeight),
                            child: _commands(),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
