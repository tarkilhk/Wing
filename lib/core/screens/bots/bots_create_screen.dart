import 'package:flutter/material.dart';
import '../../models/bots.dart';
import '../../services/bots_session.dart';
import '../../services/bot_group_create_session.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/bot_avatar.dart';
import '../../widgets/bot_group_picture.dart';
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
    this.createGroupSession,
  });
  final BotsSession session;
  final bool group;
  final BotRecord? clone;
  final BotGroupCreateSession Function()? createGroupSession;
  @override
  State<BotsCreateScreen> createState() => _BotsCreateScreenState();
}

class _BotsCreateScreenState extends State<BotsCreateScreen> {
  final _name = TextEditingController();
  late final _opening = widget.session.state;
  late final _group = widget.group
      ? widget.createGroupSession?.call() ??
            BotGroupCreateSession(widget.session)
      : null;
  final _search = TextEditingController();
  late String? _identity =
      widget.clone?.scope.connectionIdentity ??
      _opening.instances.firstOrNull?.identity;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _group?.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _group?.dispose();
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  bool _canUse() => mounted && ModalRoute.of(context)?.isCurrent == true;

  Future<void> _saveGroup() async {
    final saved = await _group!.create(canUse: _canUse);
    if (mounted && saved) Navigator.pop(context, true);
  }

  Future<void> _generatePicture() async {
    final draft = _group!;
    var prompt = draft.picturePrompt;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Room picture'),
        content: TextFormField(
          initialValue: prompt,
          onChanged: (value) => prompt = value,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Prompt'),
        ),
        actions: [
          IconButton(
            tooltip: 'Cancel',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          IconButton.filled(
            tooltip: 'Generate picture',
            onPressed: () => Navigator.pop(context, prompt),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
        ],
      ),
    );
    if (mounted && value != null) {
      await draft.generatePicture(value, canUse: _canUse);
    }
  }

  Widget _buildGroup(BuildContext context) {
    final draft = _group!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editable = draft.editable;
    final hint = draft.frozen && !draft.creating
        ? 'Retry with the same room details'
        : draft.selected.length < 2
        ? 'Choose 2–6 bots'
        : '${draft.selected.length} bots · ${draft.instance}';
    final name = TextField(
      key: const ValueKey('group-name'),
      controller: _name,
      enabled: editable,
      maxLength: 64,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      decoration: InputDecoration(
        labelText: 'Group name (optional)',
        hintText: draft.suggestedName.isEmpty
            ? 'e.g. Launch team'
            : draft.suggestedName,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      onChanged: (value) {
        draft.setName(value);
        if (_name.text != draft.name) {
          _name.value = TextEditingValue(
            text: draft.name,
            selection: TextSelection.collapsed(offset: draft.name.length),
          );
        }
      },
    );
    final picture = Stack(
      alignment: Alignment.center,
      children: [
        BotGroupPicture(
          name: draft.effectiveName,
          color: draft.iconColor,
          image: draft.picture,
          size: 64,
        ),
        if (draft.pictureBusy)
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Preparing room picture',
            ),
          ),
      ],
    );
    final pictureActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Upload room picture',
          onPressed: editable && !draft.pictureBusy
              ? () => draft.pickPicture(canUse: _canUse)
              : null,
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
        IconButton(
          tooltip: 'Generate room picture',
          onPressed: draft.canGenerate ? _generatePicture : null,
          icon: const Icon(Icons.auto_awesome_outlined),
        ),
        if (draft.picture != null)
          IconButton(
            tooltip: 'Remove room picture',
            onPressed: editable && !draft.pictureBusy
                ? draft.removePicture
                : null,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    );
    return Scaffold(
      appBar: WingAppBar(context: context, title: const Text('New group')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(WingSpacing.lg),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (draft.error != null) ...[
                  StudioError(draft.error!),
                  const SizedBox(height: WingSpacing.lg),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20;
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              picture,
                              const SizedBox(width: 12),
                              pictureActions,
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Saved to Hermes when you create the group',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          name,
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Row(
                          children: [
                            picture,
                            const SizedBox(width: 16),
                            Expanded(child: name),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            pictureActions,
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Saved to Hermes when you create the group',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: WingSpacing.md),
                if (draft.hosts.length > 1)
                  StudioSelect<String>(
                    value: draft.identity,
                    label: 'Hermes instance',
                    options: [
                      for (final host in draft.hosts)
                        (value: host.identity, label: host.label),
                    ],
                    onChanged: editable
                        ? (value) {
                            draft.chooseInstance(value);
                            _search.clear();
                          }
                        : null,
                  )
                else if (draft.hosts.isNotEmpty)
                  Text(
                    'On ${draft.instance}',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: WingSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text('Members', style: theme.textTheme.titleSmall),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '${draft.selected.length} of 6 selected',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WingSpacing.md),
                if (draft.identity == null)
                  const Text(
                    'Group chats are unavailable. Return to Bots and check that your Hermes instance is ready.',
                  )
                else if (draft.bots.length < 2)
                  const Text(
                    'This instance needs at least 2 bots. Return to Bots to create them, or choose another instance.',
                  ),
                if (draft.bots.isNotEmpty) ...[
                  if (draft.selected.isNotEmpty) ...[
                    _PickedGroupMembers(
                      members: draft.selected,
                      onRemove: editable
                          ? (bot) => draft.select(bot, false)
                          : null,
                    ),
                    const SizedBox(height: WingSpacing.md),
                  ],
                  TextField(
                    key: ValueKey('group-member-search-${draft.identity}'),
                    controller: _search,
                    enabled: editable,
                    decoration: InputDecoration(
                      hintText: 'Search bots',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: draft.query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: editable
                                  ? () {
                                      _search.clear();
                                      draft.search('');
                                    }
                                  : null,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                    onChanged: draft.search,
                  ),
                  const SizedBox(height: WingSpacing.sm),
                  if (draft.matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        draft.query.trim().isEmpty &&
                                draft.selected.length == draft.bots.length
                            ? 'All bots have been picked.'
                            : 'No bots match your search.',
                      ),
                    )
                  else
                    for (final bot in draft.matches)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          key: ValueKey('group-member-${bot.id}'),
                          enabled: draft.canSelect(bot),
                          onTap: draft.canSelect(bot)
                              ? () => draft.select(bot, true)
                              : null,
                          minTileHeight: 48,
                          minVerticalPadding: 8,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: Row(
                            children: [
                              ExcludeSemantics(
                                child: BotAvatar(
                                  name: bot.title,
                                  shape: bot.shape,
                                  color: bot.color,
                                  image: bot.avatar,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: WingSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      bot.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '@bot_${bot.profile.name}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    BotGroupPicture(
                      name: draft.effectiveName,
                      color: draft.iconColor,
                      image: draft.picture,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              draft.effectiveName.isEmpty
                                  ? 'Your new group'
                                  : draft.effectiveName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(hint, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const ValueKey('group-create'),
                      tooltip: 'Create group',
                      onPressed: draft.canCreate ? _saveGroup : null,
                      icon: draft.creating
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: 'Creating group',
                              ),
                            )
                          : const Icon(Icons.group_add_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_identity == null || _busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a profile name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.session.createBot(
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
  Widget build(BuildContext context) => widget.group
      ? _buildGroup(context)
      : Scaffold(
          appBar: WingAppBar(
            context: context,
            title: Text(widget.clone == null ? 'New bot' : 'Duplicate bot'),
            actions: [
              IconButton(
                tooltip: 'Create bot',
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
                  'No instance is ready to create bots. Return to Bots and check your Hermes connection.',
                ),
              if (widget.clone == null && _identity != null)
                StudioSelect<String>(
                  value: _identity,
                  label: 'Hermes instance',
                  options: [
                    for (final instance in _opening.instances)
                      (value: instance.identity, label: instance.label),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _identity = value;
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
                enabled: !_busy,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Profile name',
                  helperText:
                      'Lowercase letters, numbers, hyphens and underscores',
                  helperMaxLines: 4,
                ),
                textCapitalization: TextCapitalization.none,
              ),
              const SizedBox(height: 20),
              Text(
                widget.clone == null
                    ? 'The new profile inherits this instance’s launch credentials and model defaults. You can change its name, avatar and settings after creation.'
                    : 'Copies profile settings, credentials and skills. Channel bindings are excluded, so the copy will not take over existing messaging channels.',
              ),
            ],
          ),
        );
}

/// Picked membership has one home; the roster below is only an add action.
class _PickedGroupMembers extends StatelessWidget {
  const _PickedGroupMembers({required this.members, required this.onRemove});
  final List<BotRecord> members;
  final ValueChanged<BotRecord>? onRemove;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final bot in members)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                key: ValueKey('group-picked-${bot.id}'),
                container: true,
                selected: true,
                child: Material(
                  color: colors.primaryContainer,
                  borderRadius: WingRadius.control,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      ExcludeSemantics(
                        child: BotAvatar(
                          name: bot.title,
                          shape: bot.shape,
                          color: bot.color,
                          image: bot.avatar,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          bot.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${bot.title}',
                        onPressed: onRemove == null
                            ? null
                            : () => onRemove!(bot),
                        icon: const Icon(Icons.close, size: 18),
                        color: colors.onPrimaryContainer,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
