import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';

import '../models/answer_versions.dart';
import '../models/transcript_notice.dart';
import '../services/profile_gateway.dart';

typedef ChatHistoryPageLoader = Future<ProfileHistoryPage> Function(int offset);

class ChatFindResult {
  final ProfileHistoryPage page;
  final int rowId;

  const ChatFindResult({required this.page, required this.rowId});
}

class _ChatFindRow {
  final ProfileHistoryPage page;
  final Map<String, dynamic> row;

  const _ChatFindRow(this.page, this.row);
}

Future<ChatFindResult?> showChatFindSheet(
  BuildContext context, {
  required ChatHistoryPageLoader loadHistory,
}) => showModalBottomSheet<ChatFindResult>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ChatFindSheet(loadHistory: loadHistory),
);

class ChatFindSheet extends StatefulWidget {
  final ChatHistoryPageLoader loadHistory;
  const ChatFindSheet({super.key, required this.loadHistory});

  @override
  State<ChatFindSheet> createState() => _ChatFindSheetState();
}

class _ChatFindSheetState extends State<ChatFindSheet> {
  final _query = TextEditingController();
  final _history = <_ChatFindRow>[];
  final _expanded = <Object>{};
  int? _nextOffset = 0;
  int? _retryOffset;
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int offset) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _retryOffset = null;
    });
    try {
      final page = await widget.loadHistory(offset);
      if (!mounted) return;
      setState(() {
        if (offset == 0) {
          _history.clear();
        }
        final ids = _history.map((entry) => entry.row['id']).toSet();
        final rows = page.rows
            .where((row) => ids.add(row['id']))
            .map((row) => _ChatFindRow(page, row))
            .toList(growable: false);
        if (offset == 0) {
          _history.addAll(rows);
        } else {
          _history.insertAll(0, rows);
        }
        _nextOffset = page.nextOffset;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retryOffset = offset;
        _loadError = _history.isEmpty
            ? "Couldn't search this chat. Check the Hermes connection, then try again."
            : "Couldn't load older messages. Your current results are still here. Check the Hermes connection, then try again.";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ChatFindRow> get _matches {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _history.reversed
        .where((entry) => _rowText(entry.row).toLowerCase().contains(query))
        .toList(growable: false);
  }

  static String _rowText(Map<String, dynamic> row) {
    if (isHiddenAnswerMessage(row)) return '';
    final notice = transcriptNoticeText(row);
    if (notice != null) {
      return [notice, ?transcriptNoticeResult(row)].join('\n\n');
    }
    if (row['role'] == 'user') return answerMessageDisplayText(row);
    final content = row['content'] ?? row['text'] ?? row['message'];
    return content is String ? content : content?.toString() ?? '';
  }

  static Object _rowKey(Map<String, dynamic> row) =>
      row['id'] ?? identityHashCode(row);

  void _queryChanged(String _) {
    setState(_expanded.clear);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final matches = _matches;
    final hasMore = _nextOffset != null;
    return Material(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: _queryChanged,
                    decoration: const InputDecoration(
                      labelText: 'Find in chat',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: HermesRadius.control,
                      ),
                    ),
                  ),
                ),
                if (_loading && _history.isNotEmpty)
                  const LinearProgressIndicator(),
                Expanded(
                  child: _loading && _history.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _history.isEmpty && _loadError != null
                      ? _Message(_loadError!)
                      : query.isEmpty
                      ? const _Message('Type to search this chat.')
                      : matches.isEmpty
                      ? _Message(
                          hasMore
                              ? 'No matches in the messages loaded so far.'
                              : 'No matching messages.',
                        )
                      : ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (_, index) {
                            final entry = matches[index];
                            final row = entry.row;
                            final role = transcriptNoticeKind(row) != null
                                ? 'system'
                                : row['role']?.toString() ?? 'message';
                            final key = _rowKey(row);
                            final expanded = _expanded.contains(key);
                            return ExpansionTile(
                              key: ValueKey((_query.text, key)),
                              initiallyExpanded: expanded,
                              onExpansionChanged: (open) => setState(() {
                                if (open) {
                                  _expanded.add(key);
                                } else {
                                  _expanded.remove(key);
                                }
                              }),
                              leading: Icon(
                                role == 'user'
                                    ? Icons.person_outline
                                    : Icons.smart_toy_outlined,
                              ),
                              title: Text(
                                _rowText(row),
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(role),
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      8,
                                    ),
                                    child: TextButton.icon(
                                      onPressed: row['id'] is int
                                          ? () => Navigator.of(context).pop(
                                              ChatFindResult(
                                                page: entry.page,
                                                rowId: row['id'] as int,
                                              ),
                                            )
                                          : null,
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text('View in chat'),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SelectableText(_rowText(row)),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                if (!_loading || _history.isNotEmpty)
                  SafeArea(
                    top: false,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .28,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (query.isNotEmpty && matches.isNotEmpty)
                              Text(
                                hasMore
                                    ? '${_formatCount(matches.length)} matching ${matches.length == 1 ? 'message' : 'messages'} in loaded messages'
                                    : '${_formatCount(matches.length)} matching ${matches.length == 1 ? 'message' : 'messages'}',
                              ),
                            if (_loadError != null && _history.isNotEmpty)
                              Text(_loadError!),
                            if (_loadError != null)
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _load(_retryOffset ?? 0),
                                    child: const Text('Try again'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    child: const Text('Close'),
                                  ),
                                ],
                              )
                            else if (query.isNotEmpty && hasMore)
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => _load(_nextOffset!),
                                child: Text(
                                  _loading
                                      ? 'Searching older messages…'
                                      : 'Search older messages',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatCount(int value) {
  final digits = value.toString();
  final firstGroup = digits.length % 3;
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (index - firstGroup) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
