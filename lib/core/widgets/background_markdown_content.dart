import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import '../services/markdown_parse_worker.dart';
import '../services/markdown_inline_parser.dart';
import 'studio_error.dart';

/// Captures a transcript's reading position immediately before async growth.
class MarkdownContentWillChange extends Notification {
  MarkdownContentWillChange(this.source);
  final BuildContext source;
}

/// Keeps the last completed snapshot visible while a newer one parses.
/// A single in-flight snapshot and the latest source bound work during a burst.
class BackgroundMarkdownContent extends StatefulWidget {
  const BackgroundMarkdownContent({
    super.key,
    required this.data,
    required this.deliverables,
    required this.builder,
    this.streaming = false,
    this.parse,
  });

  final String data;
  final bool deliverables;
  final bool streaming;
  final Widget Function(String source, List<md.Node> nodes) builder;
  final Future<MarkdownParseResult> Function(String source)? parse;

  @override
  State<BackgroundMarkdownContent> createState() =>
      BackgroundMarkdownContentState();
}

class BackgroundMarkdownContentState extends State<BackgroundMarkdownContent>
    with WidgetsBindingObserver {
  static int _nextOwner = 0;
  // A streaming row can become a new saved row in the same frame. Seed it from
  // an already displayed matching snapshot rather than collapsing to zero
  // height. Only mounted states participate; no history cache survives disposal.
  static final _displayed = <BackgroundMarkdownContentState>{};
  int _owner = ++_nextOwner;
  int _epoch = 0;
  bool _busy = false;
  bool _foreground = true;
  bool _failed = false;
  MarkdownParseWorker? _worker;
  String? _renderedSource;
  List<md.Node>? _nodes;

  String? get renderedSource => _renderedSource;
  bool get pending => _busy || _renderedSource != widget.data;
  int parsesCompleted = 0;
  int updatesCoalesced = 0;
  int totalParserMicros = 0;
  int totalCacheHits = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (widget.parse == null) {
      BackgroundMarkdownContentState? previous;
      for (final state in _displayed) {
        final source = state._renderedSource;
        if (state._foreground &&
            state.widget.parse == null &&
            state.widget.deliverables == widget.deliverables &&
            source != null &&
            source.isNotEmpty &&
            widget.data.startsWith(source) &&
            (previous == null ||
                source.length > previous._renderedSource!.length)) {
          previous = state;
        }
      }
      if (previous != null) {
        _renderedSource = previous._renderedSource;
        _nodes = copyMarkdownNodes(previous._nodes!);
      }
    }
    if (widget.streaming) _displayed.add(this);
    _request();
  }

  @override
  void didUpdateWidget(covariant BackgroundMarkdownContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming) {
      _displayed.add(this);
    } else {
      _displayed.remove(this);
    }
    final changedConfiguration =
        widget.deliverables != oldWidget.deliverables ||
        widget.parse != oldWidget.parse;
    if (changedConfiguration || !widget.data.startsWith(oldWidget.data)) {
      _reset();
      // Nodes from another grammar cannot be rendered by the new builders.
      if (changedConfiguration || widget.data.isEmpty) {
        _nodes = null;
        _renderedSource = null;
      }
    } else if (_busy && widget.data != oldWidget.data) {
      updatesCoalesced++;
    }
    _failed = false;
    _request();
  }

  void _reset() {
    _epoch++;
    _worker?.release(_owner);
    _worker = null;
    _owner = ++_nextOwner;
    _busy = false;
  }

  void _request() {
    if (!mounted ||
        !_foreground ||
        _busy ||
        _failed ||
        widget.data == _renderedSource) {
      return;
    }
    final source = widget.data;
    final epoch = _epoch;
    _busy = true;
    final parse = widget.parse;
    final future = Future<MarkdownParseResult>.sync(
      () => parse != null
          ? parse(source)
          : (_worker ??= MarkdownParseWorker.shared).parse(
              owner: _owner,
              source: source,
              deliverables: widget.deliverables,
            ),
    );
    future
        .then(
          (result) {
            if (!mounted || !_foreground || epoch != _epoch) return;
            MarkdownContentWillChange(context).dispatch(context);
            setState(() {
              // Accept newer completed progress even if another update is pending.
              // Otherwise a fast stream could starve rendering until it completes.
              _renderedSource = source;
              _nodes = result.nodes;
              parsesCompleted++;
              totalParserMicros += result.parseMicros;
              totalCacheHits += result.cacheHits;
            });
          },
          onError: (Object error, StackTrace stack) {
            if (mounted && epoch == _epoch && _foreground) {
              setState(() {
                _reset();
                _failed = true;
              });
            }
          },
        )
        .whenComplete(() {
          if (!mounted || epoch != _epoch) return;
          _busy = false;
          _request();
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _reset();
    } else {
      _failed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _foreground) _request();
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _nodes == null
        ? const SizedBox.shrink()
        : widget.builder(_renderedSource!, _nodes!);
    return _failed
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              const StudioError('Could not display this message.'),
            ],
          )
        : child;
  }

  @override
  void dispose() {
    _displayed.remove(this);
    WidgetsBinding.instance.removeObserver(this);
    _reset();
    super.dispose();
  }
}
