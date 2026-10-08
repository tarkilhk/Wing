import 'studio_error.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';

import '../models/chat_reading.dart';
import '../services/chat_reading_session.dart';

Future<bool?> showChatFindSheet(
  BuildContext context, {
  required ChatReadingSession Function() createSession,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ChatFindSheet(createSession: createSession),
);

class ChatFindSheet extends StatefulWidget {
  final ChatReadingSession Function() createSession;
  const ChatFindSheet({super.key, required this.createSession});

  @override
  State<ChatFindSheet> createState() => _ChatFindSheetState();
}

class _ChatFindSheetState extends State<ChatFindSheet> {
  final _query = TextEditingController();
  late final _session = widget.createSession();
  final _expanded = <ChatReadingMatch>{};

  @override
  void initState() {
    super.initState();
    unawaited(_session.start());
  }

  void _queryChanged(String query) {
    _expanded.clear();
    _session.search(query);
  }

  @override
  void dispose() {
    _query.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) => _content(context, _session.observation),
  );

  Widget _content(BuildContext context, ChatReadingObservation state) {
    final query = state.query;
    final matches = state.matches;
    final hasMore = state.hasMore;
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
                        borderRadius: WingRadius.control,
                      ),
                    ),
                  ),
                ),
                if (state.loading && state.hasLoadedMessages)
                  const LinearProgressIndicator(),
                Expanded(
                  child: state.loading && !state.hasLoadedMessages
                      ? const Center(child: CircularProgressIndicator())
                      : !state.hasLoadedMessages && state.error != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: StudioError(state.error!),
                        )
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
                            final role = entry.role;
                            final key = entry;
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
                                entry.text,
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
                                      onPressed:
                                          entry.canSelect && !state.retired
                                          ? () {
                                              if (_session.select(entry) &&
                                                  mounted) {
                                                Navigator.of(context).pop(true);
                                              }
                                            }
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
                                    child: SelectableText(entry.text),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                if (!state.loading || state.hasLoadedMessages)
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
                            if (state.error != null && state.hasLoadedMessages)
                              StudioError(state.error!),
                            if (state.error != null)
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: state.loading || state.retired
                                        ? null
                                        : _session.retry,
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
                                onPressed: state.loading || state.retired
                                    ? null
                                    : _session.loadOlder,
                                child: Text(
                                  state.loading
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
