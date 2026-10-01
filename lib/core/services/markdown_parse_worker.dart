import 'dart:async';
import 'dart:isolate';

import 'package:markdown/markdown.dart' as md;

import 'markdown_inline_parser.dart';

class MarkdownParseResult {
  const MarkdownParseResult(
    this.nodes,
    this.parseMicros,
    this.cacheHits,
    this.inlineParses,
  );
  final List<md.Node> nodes;
  final int parseMicros;
  final int cacheHits;
  final int inlineParses;
}

/// One lazy isolate shared by mounted QA Markdown bodies. Widgets coalesce
/// updates before calling parse, so each owner has at most one in-flight job.
class MarkdownParseWorker {
  static MarkdownParseWorker? _shared;
  static MarkdownParseWorker get shared {
    if (_shared == null || _shared!._closed) _shared = MarkdownParseWorker();
    return _shared!;
  }

  final _requests = <int, (int, Completer<MarkdownParseResult>)>{};
  final _queue = <int, List<Object>>{};
  final _owners = <int>{};
  final _messages = ReceivePort();
  final _ready = Completer<SendPort>();
  Isolate? _isolate;
  Future<SendPort>? _starting;
  StreamSubscription<Object?>? _subscription;
  SendPort? _send;
  var _nextRequest = 0;
  var _closed = false;
  int? _active;

  Future<SendPort> _start() async {
    // Disposal can finish readiness while Isolate.spawn is still pending.
    // Attach an error handler now; awaiting the same future below still fails.
    _ready.future.ignore();
    _subscription = _messages.listen((message) {
      if (message is SendPort) {
        _send = message;
        if (!_ready.isCompleted) _ready.complete(message);
      } else if (message is List &&
          message.length == 3 &&
          message[0] == 'result') {
        _requests
            .remove(message[1])
            ?.$2
            .complete(message[2] as MarkdownParseResult);
        _queue.remove(message[1]);
        _active = null;
        _pump();
      } else if (message is List &&
          message.length == 2 &&
          message[0] == 'failed') {
        _requests
            .remove(message[1])
            ?.$2
            .completeError(StateError('Markdown parsing failed.'));
        _queue.remove(message[1]);
        _active = null;
        _pump();
      } else {
        // Isolate errors and exit notifications contain no exported diagnostics.
        _close();
      }
    });
    try {
      final isolate = await Isolate.spawn(
        _parseLoop,
        _messages.sendPort,
        debugName: 'wing-markdown-parser',
        onError: _messages.sendPort,
        onExit: _messages.sendPort,
      );
      if (_closed) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('Markdown worker is closed.');
      }
      _isolate = isolate;
      return await _ready.future;
    } catch (_) {
      _close();
      rethrow;
    }
  }

  Future<MarkdownParseResult> parse({
    required int owner,
    required String source,
    required bool deliverables,
    bool cacheEnabled = true,
    bool guardCode = true,
  }) {
    if (_closed) return Future.error(StateError('Markdown worker is closed.'));
    _owners.add(owner);
    final id = ++_nextRequest;
    final result = Completer<MarkdownParseResult>();
    _requests[id] = (owner, result);
    _queue[id] = [
      'parse',
      id,
      owner,
      source,
      deliverables,
      cacheEnabled,
      guardCode,
    ];
    _dispatch();
    return result.future;
  }

  Future<void> _dispatch() async {
    try {
      await (_starting ??= _start());
      _pump();
    } catch (_) {
      _close();
    }
  }

  void _pump() {
    if (_closed || _send == null || _active != null || _queue.isEmpty) return;
    final entry = _queue.entries.first;
    _active = entry.key;
    _send!.send(entry.value);
  }

  void release(int owner) {
    _owners.remove(owner);
    for (final entry in _requests.entries.toList()) {
      if (entry.value.$1 == owner) {
        _queue.remove(entry.key);
        _requests
            .remove(entry.key)
            ?.$2
            .completeError(StateError('Markdown request canceled.'));
      }
    }
    _send?.send(['release', owner]);
    if (_owners.isEmpty) _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    for (final request in _requests.values) {
      request.$2.completeError(StateError('Markdown worker is closed.'));
    }
    _requests.clear();
    _queue.clear();
    _owners.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _subscription?.cancel();
    _messages.close();
    if (_starting != null && !_ready.isCompleted) {
      // _start may still be spawning; its own continuation kills a late isolate.
      _ready.completeError(StateError('Markdown worker is closed.'));
    }
  }

  Future<void> dispose() async {
    _close();
    try {
      await _starting;
    } catch (_) {
      // Pending requests already received the sanitized lifecycle error.
    }
  }
}

void _parseLoop(SendPort replies) {
  final inbox = ReceivePort();
  final parsers = <int, ((bool, bool, bool), MarkdownInlineParser)>{};
  replies.send(inbox.sendPort);
  inbox.listen((dynamic message) {
    final values = message as List;
    if (values[0] == 'release') {
      parsers.remove(values[1])?.$2.clear();
      return;
    }
    final id = values[1] as int;
    try {
      final owner = values[2] as int;
      final configuration = (
        values[4] as bool,
        values[5] as bool,
        values[6] as bool,
      );
      final existing = parsers[owner];
      final parser = existing?.$1 == configuration
          ? existing!.$2
          : MarkdownInlineParser(
              deliverables: configuration.$1,
              cacheEnabled: configuration.$2,
              guardCode: configuration.$3,
            );
      parsers[owner] = (configuration, parser);
      final nodes = parser.parse(values[3] as String);
      replies.send([
        'result',
        id,
        MarkdownParseResult(
          nodes,
          parser.lastParseMicros,
          parser.cacheHits,
          parser.inlineParses,
        ),
      ]);
    } catch (_) {
      replies.send(['failed', id]);
    }
  });
}
