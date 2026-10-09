import 'package:flutter/material.dart';
import '../../services/bot_group_session.dart';
import '../../models/bots.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';

class BotGroupScreen extends StatefulWidget {
  const BotGroupScreen({super.key, required this.createSession});
  final BotGroupSession Function() createSession;
  @override
  State<BotGroupScreen> createState() => _BotGroupScreenState();
}

class _BotGroupScreenState extends State<BotGroupScreen>
    with WidgetsBindingObserver {
  late final _session = widget.createSession();
  final _composer = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    _session.setVisible(true);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final submitted = _composer.text;
    if (await _session.send(submitted) &&
        mounted &&
        _composer.text == submitted) {
      _composer.clear();
    }
  }

  Future<void> _retry(BotGroupAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retry interrupted group work?'),
        content: const Text(
          'The previous attempt has an uncertain outcome. Retrying may repeat work that already completed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _session.resolve(action);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: WingAppBar(
      context: context,
      title: Text(_session.group.name),
      actions: [
        IconButton(
          tooltip: 'Refresh group',
          onPressed: _session.loading ? null : _session.refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Stop group work',
          onPressed: _session.acting ? null : _session.stop,
          icon: const Icon(Icons.stop_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${_session.group.instance} · Discussion',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (_session.loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_session.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: StudioError(_session.error!),
                  ),
                if (_session.runtime case final runtime?) ...[
                  if (runtime.working) const Text('Bots are working…'),
                  if (runtime.blocked && runtime.actions.isEmpty)
                    const Text(
                      'Group work is interrupted. Refresh to check its recovery options.',
                    ),
                  for (final action in runtime.actions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.kind == 'retry'
                                ? 'Interrupted work'
                                : '${action.member} needs approval',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (action.description.isNotEmpty)
                            Text(action.description),
                          if (action.command.isNotEmpty)
                            SelectableText(action.command),
                          Wrap(
                            children: [
                              if (action.kind == 'retry')
                                IconButton(
                                  tooltip: 'Review retry',
                                  onPressed: _session.acting
                                      ? null
                                      : () => _retry(action),
                                  icon: const Icon(Icons.refresh),
                                ),
                              for (final choice in action.choices)
                                IconButton(
                                  tooltip: choice == 'once'
                                      ? 'Allow once'
                                      : 'Deny',
                                  onPressed: _session.acting
                                      ? null
                                      : () => _session.resolve(
                                          action,
                                          choice: choice,
                                        ),
                                  icon: Icon(
                                    choice == 'once'
                                        ? Icons.check
                                        : Icons.close,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final member in _session.group.members)
                      ActionChip(
                        label: Text('@${member.handle}'),
                        onPressed:
                            _session.pendingText != null || _session.sending
                            ? null
                            : () {
                                final text =
                                    '${_composer.text}@${member.handle} ';
                                _composer.value = TextEditingValue(
                                  text: text,
                                  selection: TextSelection.collapsed(
                                    offset: text.length,
                                  ),
                                );
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_session.events.where((event) => event.isMessage).isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Start a discussion. Mention a bot to focus the reply, or ask the whole group.',
                    ),
                  ),
                for (final event in _session.events.where(
                  (event) => event.isMessage,
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.kind == 'message.user' ? 'You' : event.actor,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(event.text),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: WingTokens.of(context).raised,
              border: Border(
                top: BorderSide(color: WingTokens.of(context).border),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      readOnly:
                          _session.pendingText != null || _session.sending,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message the group',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _session.pendingText == null
                        ? 'Send group message'
                        : 'Retry same message',
                    onPressed: _session.sending ? null : _send,
                    icon: Icon(
                      _session.pendingText == null
                          ? Icons.arrow_upward
                          : Icons.refresh,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
