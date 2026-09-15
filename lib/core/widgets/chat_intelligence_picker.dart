import 'package:flutter/material.dart';

import '../theme/wing_theme.dart';

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
    final tokens = WingTokens.of(context);
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
            horizontal: WingSpacing.sm,
            vertical: 4,
          ),
          shape: RoundedRectangleBorder(borderRadius: WingRadius.control),
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
            const SizedBox(width: 8),
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
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height * 0.86 - keyboard;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight.clamp(0, 720)),
          child: AnimatedSize(
            duration: WingMotion.standard,
            alignment: Alignment.bottomCenter,
            curve: WingMotion.curve,
            child: AnimatedSwitcher(
              duration: WingMotion.standard,
              switchInCurve: WingMotion.curve,
              switchOutCurve: WingMotion.curve,
              child: _choosingModel ? _buildModelPage() : _buildReasoningPage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReasoningPage() {
    final tokens = WingTokens.of(context);
    return Column(
      key: const ValueKey('reasoning-page'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(title: 'Intelligence', onClose: widget.onCancel),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              WingSpacing.sm,
              0,
              WingSpacing.sm,
              WingSpacing.sm,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WingSpacing.sm,
                  WingSpacing.xs,
                  WingSpacing.sm,
                  WingSpacing.xs,
                ),
                child: Text(
                  'Reasoning',
                  style: tokens.typography.label.copyWith(color: tokens.muted),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: WingSpacing.sm,
                  runSpacing: WingSpacing.xs,
                  children: [
                    for (final entry in chatReasoningEffortLabels.entries)
                      SizedBox(
                        width: (constraints.maxWidth - WingSpacing.sm) / 2,
                        child: _PickerTile(
                          key: Key('reasoning-${entry.key}'),
                          title: entry.value,
                          selected: entry.key == _selectedEffort,
                          onTap: () =>
                              setState(() => _selectedEffort = entry.key),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: WingSpacing.md),
              ListTile(
                key: const Key('choose-chat-model'),
                dense: true,
                minTileHeight: 56,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: WingSpacing.sm,
                ),
                title: Text(
                  _selectedChoice.model,
                  style: tokens.typography.body.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
                subtitle: Text(
                  _selectedChoice.routeLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setState(() => _choosingModel = true),
              ),
              if (_selectedChoice.model != widget.defaultModel ||
                  (widget.defaultProvider != null &&
                      _selectedChoice.provider != widget.defaultProvider))
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WingSpacing.sm,
                    0,
                    WingSpacing.sm,
                    WingSpacing.sm,
                  ),
                  child: Text(
                    'Profile default: ${widget.defaultModel}'
                    '${widget.defaultProvider == null ? '' : ' • ${widget.defaultProvider}'}',
                    style: tokens.typography.label.copyWith(
                      color: tokens.muted,
                    ),
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
    final tokens = WingTokens.of(context);
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
          onBack: () => setState(() => _choosingModel = false),
          onClose: widget.onCancel,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WingSpacing.lg,
            0,
            WingSpacing.lg,
            WingSpacing.sm,
          ),
          child: TextField(
            key: const Key('model-search'),
            decoration: const InputDecoration(
              hintText: 'Search models',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: WingRadius.control),
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
                    horizontal: WingSpacing.sm,
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
  final VoidCallback? onBack;
  final VoidCallback onClose;

  const _SheetHeader({required this.title, required this.onClose, this.onBack});

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(WingSpacing.sm, 0, WingSpacing.sm, 0),
      child: Row(
        children: [
          if (onBack != null)
            SizedBox(
              width: 48,
              child: IconButton(
                key: const Key('intelligence-back'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to reasoning',
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: WingSpacing.sm),
              child: Text(
                title,
                style: tokens.typography.section.copyWith(
                  color: tokens.onSurface,
                ),
              ),
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
    final tokens = WingTokens.of(context);
    return ListTile(
      dense: true,
      minTileHeight: 48,
      minVerticalPadding: WingSpacing.xs,
      contentPadding: const EdgeInsets.symmetric(horizontal: WingSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: WingRadius.card),
      selected: selected,
      selectedTileColor: tokens.accent.withValues(alpha: 0.1),
      title: Text(title, style: tokens.typography.body),
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
    final tokens = WingTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.raised,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        WingSpacing.lg,
        WingSpacing.sm,
        WingSpacing.lg,
        WingSpacing.sm,
      ),
      child: OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: WingSpacing.sm,
        overflowSpacing: WingSpacing.xs,
        children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          FilledButton(onPressed: onApply, child: const Text('Apply')),
        ],
      ),
    );
  }
}
