import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../presentation/source_highlighting.dart';
import '../theme/wing_theme.dart';

/// One selectable source renderer for chat, tool payloads and file previews.
/// The mounted view owns only its latest tokens and asynchronous paint lifetime.
class SourceCodeText extends StatefulWidget {
  const SourceCodeText({
    super.key,
    required this.text,
    required this.language,
    required this.style,
    this.numberedLines = false,
    this.highlightingEnabled = true,
  });

  final String text;
  final String? language;
  final TextStyle style;
  final bool numberedLines;
  final bool highlightingEnabled;

  @override
  State<SourceCodeText> createState() => _SourceCodeTextState();
}

class _SourceCodeTextState extends State<SourceCodeText> {
  Timer? _debounce;
  List<SourceToken>? _tokens;
  TextSpan? _span;
  WingTokens? _spanColors;
  var _revision = 0;
  var _busy = false;
  var _ready = true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant SourceCodeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text &&
        oldWidget.language == widget.language &&
        oldWidget.numberedLines == widget.numberedLines &&
        oldWidget.highlightingEnabled == widget.highlightingEnabled) {
      return;
    }
    ++_revision;
    _tokens = null;
    _span = null;
    _ready = false;
    _debounce?.cancel();
    if (!widget.highlightingEnabled || !sourceHighlightEligible(_request)) {
      return;
    }
    // Coalesce changing receipts; live Markdown waits for response completion.
    _debounce = Timer(const Duration(milliseconds: 80), () {
      _ready = true;
      _prepare();
    });
  }

  SourceHighlightRequest get _request => SourceHighlightRequest(
    widget.text,
    widget.language,
    widget.numberedLines,
  );

  Future<void> _prepare() async {
    if (_busy || !_ready || !mounted) return;
    if (!widget.highlightingEnabled || !sourceHighlightEligible(_request)) {
      return;
    }
    _busy = true;
    final revision = _revision;
    try {
      final tokens = await compute(
        highlightSource,
        _request,
        debugLabel: 'wing-source-highlight',
      );
      if (mounted && revision == _revision) {
        // Literal output is already on screen; do not lay out a large/unknown
        // source again just because its worker decided against syntax styling.
        if (tokens.length != 1 ||
            tokens.single.scope != null ||
            tokens.single.text != widget.text) {
          setState(() {
            _tokens = tokens;
            _span = null;
          });
        }
      }
    } catch (error, stack) {
      // A malformed source/grammar must never remove received content.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Wing source highlighting',
        ),
      );
    } finally {
      _busy = false;
      if (mounted && revision != _revision && _ready) _prepare();
    }
  }

  @override
  void dispose() {
    ++_revision;
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WingTokens.of(context);
    if (_tokens != null &&
        (_spanColors?.brightness != colors.brightness ||
            _spanColors?.muted != colors.muted)) {
      _span = null;
    }
    _spanColors = colors;
    _span ??= _tokens == null
        ? TextSpan(text: widget.text)
        : TextSpan(
            children: [
              for (final token in _tokens!)
                TextSpan(
                  text: token.text,
                  style: TextStyle(color: colors.sourceColor(token.scope)),
                ),
            ],
          );
    return SelectableText.rich(_span!, style: widget.style);
  }
}
