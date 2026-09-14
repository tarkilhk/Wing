import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';

/// One model exposed by the active Hermes profile.
class ChatModelChoice {
  final String provider;
  final String model;
  final String? providerLabel;

  const ChatModelChoice({
    required this.provider,
    required this.model,
    this.providerLabel,
  });

  String get routeLabel => providerLabel?.trim().isNotEmpty == true
      ? providerLabel!.trim()
      : provider;

  /// Shared model/options response for per-chat and profile-default pickers.
  static List<ChatModelChoice> fromOptions(Map<String, dynamic> response) {
    final choices = <ChatModelChoice>[];
    final providers = response['providers'];
    if (providers is! List || providers.any((row) => row is! Map)) {
      throw const FormatException('Expected a list of records');
    }
    for (final row in providers) {
      final provider = Map<String, dynamic>.from(row as Map);
      final slug =
          (provider['slug'] ?? provider['id'])?.toString().trim() ?? '';
      final label =
          (provider['name'] ?? provider['display_name'] ?? provider['title'])
              ?.toString()
              .trim();
      final models = provider['models'];
      if (slug.isEmpty || models is! List) continue;
      for (final value in models) {
        final model = value is String
            ? value.trim()
            : value is Map
            ? (value['id'] ?? value['model'] ?? value['name'])
                      ?.toString()
                      .trim() ??
                  ''
            : '';
        if (model.isNotEmpty) {
          choices.add(
            ChatModelChoice(
              provider: slug,
              model: model,
              providerLabel: label?.isEmpty == true ? null : label,
            ),
          );
        }
      }
    }
    return choices;
  }
}

/// The per-chat model and reasoning values chosen in the picker.
class ChatIntelligenceSelection {
  final ChatModelChoice choice;
  final String reasoningEffort;

  const ChatIntelligenceSelection({
    required this.choice,
    required this.reasoningEffort,
  });
}

const chatReasoningEffortLabels = <String, String>{
  'none': 'Off',
  'minimal': 'Minimal',
  'low': 'Low',
  'medium': 'Medium',
  'high': 'High',
  'xhigh': 'Extra High',
  'max': 'Max',
  'ultra': 'Ultra',
};

String chatReasoningEffortLabel(String effort) {
  final normalized = effort.trim().toLowerCase();
  if (normalized == 'default' || normalized.isEmpty) return 'Default';
  return chatReasoningEffortLabels[normalized] ?? effort;
}

/// Shortens common model IDs for the composer without changing the value sent
/// to Hermes. The full ID remains visible in the picker and context header.
String compactChatModelLabel(String model) {
  var value = model.trim();
  if (value.contains('/')) value = value.split('/').last;
  if (value.toLowerCase().startsWith('gpt-')) value = value.substring(4);
  final words = value.split(RegExp(r'[-_]+')).where((word) => word.isNotEmpty);
  return words
      .map((word) {
        if (RegExp(r'^\d').hasMatch(word)) return word;
        return '${word[0].toUpperCase()}${word.substring(1)}';
      })
      .join(' ');
}

/// Compact composer control that keeps the effective model and reasoning
/// visible beside the send button.
class ChatIntelligenceButton extends StatelessWidget {
  final String model;
  final String reasoningEffort;
  final bool loading;
  final VoidCallback? onPressed;

  const ChatIntelligenceButton({
    required this.model,
    required this.reasoningEffort,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final modelLabel = compactChatModelLabel(model);
    final reasoningLabel = chatReasoningEffortLabel(reasoningEffort);

    return Semantics(
      label: 'Model $model, reasoning $reasoningLabel',
      hint: 'Change model and reasoning for this chat',
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: TextButton(
        key: const Key('chat-intelligence-button'),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: tokens.onSurface,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: HermesSpacing.sm,
            vertical: 6,
          ),
          shape: RoundedRectangleBorder(borderRadius: HermesRadius.control),
          backgroundColor: tokens.raised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              )
            else
              Icon(
                Icons.psychology_outlined,
                size: 17,
                color: onPressed == null ? tokens.muted : tokens.accent,
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    modelLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.label.copyWith(
                      color: onPressed == null
                          ? tokens.muted
                          : tokens.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    reasoningLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.label.copyWith(
                      color: tokens.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: tokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

Future<ChatIntelligenceSelection?> showChatIntelligencePicker({
  required BuildContext context,
  required List<ChatModelChoice> choices,
  required ChatModelChoice initialChoice,
  required String initialReasoningEffort,
  required String defaultModel,
  String? defaultProvider,
}) {
  return showModalBottomSheet<ChatIntelligenceSelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => ChatIntelligenceSheet(
      choices: choices,
      initialChoice: initialChoice,
      initialReasoningEffort: initialReasoningEffort,
      defaultModel: defaultModel,
      defaultProvider: defaultProvider,
      onCancel: () => Navigator.pop(sheetContext),
      onApply: (selection) => Navigator.pop(sheetContext, selection),
    ),
  );
}

/// Model and reasoning picker used by the modal route and widget tests.
class ChatIntelligenceSheet extends StatefulWidget {
  final List<ChatModelChoice> choices;
  final ChatModelChoice initialChoice;
  final String initialReasoningEffort;
  final String defaultModel;
  final String? defaultProvider;
  final ValueChanged<ChatIntelligenceSelection> onApply;
  final VoidCallback onCancel;

  const ChatIntelligenceSheet({
    required this.choices,
    required this.initialChoice,
    required this.initialReasoningEffort,
    required this.defaultModel,
    required this.onApply,
    required this.onCancel,
    this.defaultProvider,
    super.key,
  });

  @override
  State<ChatIntelligenceSheet> createState() => _ChatIntelligenceSheetState();
}

class _ChatIntelligenceSheetState extends State<ChatIntelligenceSheet> {
  late ChatModelChoice _selectedChoice;
  late String _selectedEffort;
  bool _choosingModel = false;
  String _modelQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedChoice = widget.initialChoice;
    final normalized = widget.initialReasoningEffort.trim().toLowerCase();
    _selectedEffort = chatReasoningEffortLabels.containsKey(normalized)
        ? normalized
        : 'medium';
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height * 0.86;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: availableHeight.clamp(420, 720)),
      child: AnimatedSwitcher(
        duration: HermesMotion.standard,
        switchInCurve: HermesMotion.curve,
        switchOutCurve: HermesMotion.curve,
        child: _choosingModel ? _buildModelPage() : _buildReasoningPage(),
      ),
    );
  }

  Widget _buildReasoningPage() {
    final tokens = HermesTokens.of(context);
    return Column(
      key: const ValueKey('reasoning-page'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(
          title: 'Intelligence',
          subtitle: 'Model and reasoning for this chat',
          onClose: widget.onCancel,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.sm,
              0,
              HermesSpacing.sm,
              HermesSpacing.sm,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.sm,
                  HermesSpacing.xs,
                  HermesSpacing.sm,
                  HermesSpacing.xs,
                ),
                child: Text(
                  'Reasoning',
                  style: tokens.typography.label.copyWith(color: tokens.muted),
                ),
              ),
              for (final entry in chatReasoningEffortLabels.entries)
                _PickerTile(
                  key: Key('reasoning-${entry.key}'),
                  title: entry.value,
                  selected: entry.key == _selectedEffort,
                  onTap: () => setState(() => _selectedEffort = entry.key),
                ),
              const Divider(height: HermesSpacing.xl),
              ListTile(
                key: const Key('choose-chat-model'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: HermesSpacing.sm,
                ),
                title: Text(
                  'Model',
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
                subtitle: Text(
                  '${_selectedChoice.model}  •  ${_selectedChoice.provider}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setState(() => _choosingModel = true),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.sm,
                  0,
                  HermesSpacing.sm,
                  HermesSpacing.sm,
                ),
                child: Text(
                  'Profile default: ${widget.defaultModel}'
                  '${widget.defaultProvider == null ? '' : ' • ${widget.defaultProvider}'}',
                  style: tokens.typography.label.copyWith(color: tokens.muted),
                ),
              ),
            ],
          ),
        ),
        _SheetActions(
          onCancel: widget.onCancel,
          onApply: () => widget.onApply(
            ChatIntelligenceSelection(
              choice: _selectedChoice,
              reasoningEffort: _selectedEffort,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelPage() {
    final tokens = HermesTokens.of(context);
    final normalizedQuery = _modelQuery.trim().toLowerCase();
    final visibleChoices = widget.choices
        .where((choice) {
          if (normalizedQuery.isEmpty) return true;
          return choice.model.toLowerCase().contains(normalizedQuery) ||
              choice.provider.toLowerCase().contains(normalizedQuery) ||
              choice.routeLabel.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
    final groups = <String, List<ChatModelChoice>>{};
    for (final choice in visibleChoices) {
      groups.putIfAbsent(choice.provider, () => []).add(choice);
    }

    return Column(
      key: const ValueKey('model-page'),
      children: [
        _SheetHeader(
          title: 'Model',
          subtitle: 'Available for this profile',
          onBack: () => setState(() => _choosingModel = false),
          onClose: widget.onCancel,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            0,
            HermesSpacing.lg,
            HermesSpacing.sm,
          ),
          child: TextField(
            key: const Key('model-search'),
            decoration: const InputDecoration(
              hintText: 'Search models',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: HermesRadius.control),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _modelQuery = value),
          ),
        ),
        Expanded(
          child: visibleChoices.isEmpty
              ? Center(
                  child: Text(
                    'No matching models',
                    style: tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HermesSpacing.sm,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final provider = groups.keys.elementAt(index);
                    final choices = groups[provider]!;
                    final label = choices.first.routeLabel;
                    return ExpansionTile(
                      key: Key('model-provider-$provider'),
                      initiallyExpanded: provider == _selectedChoice.provider,
                      title: Text(label),
                      subtitle: Text(provider),
                      children: [
                        for (final choice in choices)
                          _PickerTile(
                            key: Key(
                              'model-${choice.provider}-${choice.model}',
                            ),
                            title: choice.model,
                            selected:
                                choice.model == _selectedChoice.model &&
                                choice.provider == _selectedChoice.provider,
                            onTap: () => setState(() {
                              _selectedChoice = choice;
                              _choosingModel = false;
                              _modelQuery = '';
                            }),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  const _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.sm,
        HermesSpacing.xs,
        HermesSpacing.sm,
        HermesSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: onBack == null
                ? null
                : IconButton(
                    key: const Key('intelligence-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back to reasoning',
                  ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: tokens.typography.title.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: tokens.typography.label.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 48,
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: HermesSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: HermesRadius.card),
      selected: selected,
      selectedTileColor: tokens.accent.withValues(alpha: 0.1),
      title: Text(title),
      trailing: selected
          ? Icon(Icons.check_rounded, color: tokens.accent)
          : const SizedBox(width: 24),
      onTap: onTap,
    );
  }
}

class _SheetActions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onApply;

  const _SheetActions({required this.onCancel, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.raised,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        HermesSpacing.sm,
        HermesSpacing.lg,
        HermesSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: HermesSpacing.sm),
          FilledButton(onPressed: onApply, child: const Text('Apply')),
        ],
      ),
    );
  }
}
