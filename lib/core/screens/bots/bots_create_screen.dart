import 'package:flutter/material.dart';
import '../../models/bots.dart';
import '../../services/bots_session.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/studio_select.dart';
import '../../widgets/wing_app_bar.dart';

/// Local input only. The roster owner admits, targets and settles creation.
class BotsCreateScreen extends StatefulWidget {
  const BotsCreateScreen({
    super.key,
    required this.session,
    required this.group,
    this.clone,
  });
  final BotsSession session;
  final bool group;
  final BotRecord? clone;
  @override
  State<BotsCreateScreen> createState() => _BotsCreateScreenState();
}

class _BotsCreateScreenState extends State<BotsCreateScreen> {
  final _name = TextEditingController();
  late final _opening = widget.session.state;
  late final _roomId = widget.session.newRoomId();
  late String? _identity =
      widget.clone?.scope.connectionIdentity ??
      (widget.group
          ? _opening.groupHosts.firstOrNull
          : _opening.instances.firstOrNull?.identity);
  final _members = <String>{};
  bool _busy = false, _frozen = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _canUse() => mounted && ModalRoute.of(context)?.isCurrent == true;
  Future<void> _save() async {
    if (_identity == null || _busy) return;
    final members = _opening.bots
        .where(
          (bot) =>
              bot.scope.connectionIdentity == _identity &&
              _members.contains(bot.id),
        )
        .toList();
    if (_name.text.trim().isEmpty ||
        widget.group && (members.length < 2 || members.length > 6)) {
      setState(
        () => _error = widget.group
            ? 'Name the group and choose 2–6 bots.'
            : 'Enter a profile name.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      if (widget.group) _frozen = true;
    });
    final saved = widget.group
        ? await widget.session.createGroup(
            _identity!,
            _roomId,
            _name.text,
            members,
            canUse: _canUse,
          )
        : await widget.session.createBot(
            _identity!,
            _name.text.trim(),
            clone: widget.clone,
            canUse: _canUse,
          );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          widget.session.state.errors.firstOrNull ??
          'Creation could not be confirmed.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: WingAppBar(
      context: context,
      title: Text(
        widget.group
            ? 'New group'
            : widget.clone == null
            ? 'New bot'
            : 'Duplicate bot',
      ),
      actions: [
        IconButton(
          tooltip: widget.group ? 'Create group' : 'Create bot',
          onPressed: _busy || _identity == null ? null : _save,
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: StudioError(_error!),
          ),
        if (_identity == null)
          const Text(
            'No instance is ready to create groups. Refresh Bots and check Hermes’ group worker.',
          ),
        if (widget.clone == null && _identity != null)
          StudioSelect<String>(
            value: _identity,
            label: 'Hermes instance',
            options: [
              for (final instance in _opening.instances.where(
                (i) =>
                    !widget.group || _opening.groupHosts.contains(i.identity),
              ))
                (value: instance.identity, label: instance.label),
            ],
            onChanged: _busy || _frozen
                ? null
                : (value) => setState(() {
                    _identity = value;
                    _members.clear();
                  }),
          ),
        if (widget.clone != null)
          Text(
            'Copy ${widget.clone!.title} on ${widget.clone!.instance}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          enabled: !_busy && !_frozen,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.group ? 'Group name' : 'Profile name',
            helperText: widget.group
                ? null
                : 'Lowercase letters, numbers, hyphens and underscores',
            helperMaxLines: 4,
          ),
          textCapitalization: widget.group
              ? TextCapitalization.words
              : TextCapitalization.none,
        ),
        const SizedBox(height: 20),
        if (widget.group) ...[
          const Text(
            'Choose 2–6 bots. Discussion runs on this Hermes instance. Tap @handles in the conversation to direct replies.',
          ),
          const SizedBox(height: 12),
          for (final bot in _opening.bots.where(
            (b) => b.scope.connectionIdentity == _identity,
          ))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _members.contains(bot.id),
              title: Text(bot.title),
              subtitle: Text(bot.profile.name),
              onChanged:
                  _busy ||
                      _frozen ||
                      !_members.contains(bot.id) && _members.length >= 6
                  ? null
                  : (checked) => setState(() {
                      if (checked == true) {
                        _members.add(bot.id);
                      } else {
                        _members.remove(bot.id);
                      }
                    }),
            ),
        ] else
          Text(
            widget.clone == null
                ? 'The new profile inherits this instance’s launch credentials and model defaults. You can change its name, avatar and settings after creation.'
                : 'Copies profile settings, credentials and skills. Channel bindings are excluded, so the copy will not take over existing messaging channels.',
          ),
      ],
    ),
  );
}
