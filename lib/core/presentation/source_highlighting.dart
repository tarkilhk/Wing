import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

typedef SourceToken = ({String text, String? scope});

/// Immutable, isolate-safe input. No UI styles or backend bags cross this seam.
final class SourceHighlightRequest {
  const SourceHighlightRequest(this.text, this.language, this.numberedLines);
  final String text;
  final String? language;
  final bool numberedLines;
}

final _highlight = Highlight()..registerLanguages(builtinAllLanguages);
const _maxSourceTokens = 768;

/// Reject oversized snapshots before launching a worker or loading grammars.
/// Count only as far as the admission limit, including numbered receipts.
bool sourceHighlightEligible(SourceHighlightRequest request) {
  if (request.text.isEmpty ||
      request.text.length > 8 * 1024 ||
      (request.language == null && !request.numberedLines)) {
    return false;
  }
  var offset = -1;
  for (var lines = 1; lines <= 200; ++lines) {
    offset = request.text.indexOf('\n', offset + 1);
    if (offset < 0) return true;
  }
  return false;
}

final _linePrefix = RegExp(r'^\d+\|');

/// Tokenize a complete source snapshot, retaining multiline grammar context.
/// Unknown/unlabelled text has no guessed grammar. Work on very large receipts
/// is bounded; their complete literal text remains selectable and copyable.
List<SourceToken> highlightSource(SourceHighlightRequest request) {
  final literal = <SourceToken>[(text: request.text, scope: null)];
  // Stock /api/fs/read-text calls shell source "shell". The library's
  // "shell" grammar instead expects console prompts, so adapt that wire value.
  final suppliedLanguage = request.language?.trim().toLowerCase();
  final language = suppliedLanguage == 'shell' ? 'bash' : suppliedLanguage;
  if (!sourceHighlightEligible(request)) return literal;
  final lines = request.text.split('\n');
  final prefixes = <String>[];
  final undecorated = <String>[];
  if (request.numberedLines) {
    for (final line in lines) {
      final prefix = _linePrefix.firstMatch(line)?.group(0) ?? '';
      prefixes.add(prefix);
      undecorated.add(line.substring(prefix.length));
    }
  }
  final source = request.numberedLines ? undecorated.join('\n') : request.text;
  var tokens = <SourceToken>[(text: source, scope: null)];
  if (source.isNotEmpty &&
      language != null &&
      _highlight.getLanguage(language) != null) {
    final renderer = _SourceTokenRenderer();
    _highlight.highlight(code: source, language: language).render(renderer);
    // Grammar bugs must never alter selectable source bytes.
    if (renderer.tokens.map((token) => token.text).join() == source) {
      tokens = renderer.tokens;
    }
  }
  if (tokens.length > _maxSourceTokens) return literal;
  if (!request.numberedLines) return tokens;

  // Insert the original receipt decoration after parsing, so `12|` cannot
  // confuse Python indentation, Bash strings, or a multiline source grammar.
  final result = <SourceToken>[];
  var line = 0;
  void prefix() {
    if (prefixes[line].isNotEmpty) {
      result.add((text: prefixes[line], scope: 'wing-line-number'));
    }
  }

  prefix();
  for (final token in tokens) {
    final parts = token.text.split('\n');
    for (var i = 0; i < parts.length; ++i) {
      if (i > 0) {
        result.add((text: '\n', scope: token.scope));
        ++line;
        prefix();
      }
      if (parts[i].isNotEmpty) {
        result.add((text: parts[i], scope: token.scope));
      }
    }
  }
  return result.length > _maxSourceTokens ? literal : result;
}

final class _SourceTokenRenderer implements HighlightRenderer {
  final _tokens = <SourceToken>[];
  final _scopes = <String?>[];
  final _text = StringBuffer();
  String? _scope;

  List<SourceToken> get tokens {
    _flush();
    return _tokens;
  }

  void _flush() {
    if (_text.isEmpty) return;
    _tokens.add((text: _text.toString(), scope: _scope));
    _text.clear();
  }

  @override
  void openNode(DataNode node) =>
      _scopes.add(node.scope ?? (_scopes.isEmpty ? null : _scopes.last));

  @override
  void closeNode(DataNode node) => _scopes.removeLast();

  @override
  void addText(String text) {
    if (text.isNotEmpty) {
      final scope = _scopes.isEmpty ? null : _scopes.last;
      if (_text.isNotEmpty && scope != _scope) _flush();
      _scope = scope;
      _text.write(text);
    }
  }
}
