import 'package:flutter/material.dart';

import '../theme/wing_theme.dart';
import 'model_chooser.dart';
import 'studio_error.dart';
import 'studio_selection_tile.dart';

/// The per-chat model and reasoning values chosen in the picker.
class ChatIntelligenceSelection {
  final ModelChoice choice;
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
  required List<ModelChoice> choices,
  required ModelChoice initialChoice,
  required String initialReasoningEffort,
  required String defaultModel,
  required String profileName,
  required Future<List<ModelChoice>> Function() refreshModels,
  required Future<void> Function() reviewProviderAccess,
  Future<bool> Function(ChatIntelligenceSelection)? onCommit,
  String? defaultProvider,
}) async {
  var reviewAccess = false;
  final selection = await showModalBottomSheet<ChatIntelligenceSelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (sheetContext) => ChatIntelligenceSheet(
      choices: choices,
      initialChoice: initialChoice,
      initialReasoningEffort: initialReasoningEffort,
      defaultModel: defaultModel,
      defaultProvider: defaultProvider,
      profileName: profileName,
      onRefreshModels: refreshModels,
      onReviewProviderAccess: () {
        reviewAccess = true;
        Navigator.pop(sheetContext);
      },
      onCancel: () => Navigator.pop(sheetContext),
      onApply: (selection) => Navigator.pop(sheetContext, selection),
      onCommit: onCommit,
    ),
  );
  if (reviewAccess && context.mounted) await reviewProviderAccess();
  return selection;
}

/// Model and reasoning picker used by the modal route and widget tests.
class ChatIntelligenceSheet extends StatefulWidget {
  final List<ModelChoice> choices;
  final ModelChoice initialChoice;
  final String initialReasoningEffort;
  final String defaultModel;
  final String? defaultProvider;
  final String profileName;
  final Future<List<ModelChoice>> Function() onRefreshModels;
  final VoidCallback onReviewProviderAccess;
  final ValueChanged<ChatIntelligenceSelection> onApply;
  final Future<bool> Function(ChatIntelligenceSelection)? onCommit;
  final VoidCallback onCancel;

  const ChatIntelligenceSheet({
    required this.choices,
    required this.initialChoice,
    required this.initialReasoningEffort,
    required this.defaultModel,
    required this.profileName,
    required this.onRefreshModels,
    required this.onReviewProviderAccess,
    required this.onApply,
    required this.onCancel,
    this.onCommit,
    this.defaultProvider,
    super.key,
  });

  @override
  State<ChatIntelligenceSheet> createState() => _ChatIntelligenceSheetState();
}

class _ChatIntelligenceSheetState extends State<ChatIntelligenceSheet> {
  late List<ModelChoice> _choices;
  late ModelChoice _selectedChoice;
  late String _selectedEffort;
  bool _choosingModel = false;
  bool _applying = false;
  String? _applyError;

  Future<void> _apply() async {
    if (_applying) return;
    final selection = ChatIntelligenceSelection(
      choice: _selectedChoice,
      reasoningEffort: _selectedEffort,
    );
    final commit = widget.onCommit;
    if (commit == null) {
      widget.onApply(selection);
      return;
    }
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      final applied = await commit(selection);
      if (!mounted) return;
      if (applied) {
        widget.onApply(selection);
      } else {
        setState(
          () => _applyError =
              'Model change cancelled. Your choice is still here.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _applyError = error is StateError
            ? error.message.toString()
            : 'Could not apply the model and reasoning. Your choice is still here.',
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _choices = widget.choices;
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
    return PopScope(
      canPop: !_applying,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: availableHeight.clamp(0, 720),
            ),
            child: AnimatedSize(
              duration: WingMotion.standard,
              alignment: Alignment.bottomCenter,
              curve: WingMotion.curve,
              child: AnimatedSwitcher(
                duration: WingMotion.standard,
                switchInCurve: WingMotion.curve,
                switchOutCurve: WingMotion.curve,
                child: _choosingModel
                    ? _buildModelPage()
                    : _buildReasoningPage(),
              ),
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
        _SheetHeader(
          title: 'Intelligence',
          onClose: _applying ? null : widget.onCancel,
        ),
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
              RadioGroup<String>(
                groupValue: _selectedEffort,
                onChanged: (value) {
                  if (value != null) setState(() => _selectedEffort = value);
                },
                child: LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: WingSpacing.sm,
                    runSpacing: WingSpacing.xs,
                    children: [
                      for (final entry in chatReasoningEffortLabels.entries)
                        SizedBox(
                          width: (constraints.maxWidth - WingSpacing.sm) / 2,
                          child: StudioRadioTile<String>(
                            key: Key('reasoning-${entry.key}'),
                            value: entry.key,
                            title: Text(entry.value),
                          ),
                        ),
                    ],
                  ),
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
        if (_applyError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WingSpacing.lg),
            child: StudioError(_applyError!),
          ),
        _SheetActions(
          onCancel: _applying ? null : widget.onCancel,
          onApply: _applying ? null : _apply,
          applying: _applying,
        ),
      ],
    );
  }

  Widget _buildModelPage() => Column(
    key: const ValueKey('model-page'),
    children: [
      _SheetHeader(
        title: 'Model',
        onBack: () => setState(() => _choosingModel = false),
        onClose: _applying ? null : widget.onCancel,
      ),
      Expanded(
        child: ModelChooser(
          choices: _choices,
          selected: ModelSelection.model(_selectedChoice),
          onSelected: (selection) {
            final choice = selection.choice;
            if (choice == null) return;
            setState(() {
              _selectedChoice = choice;
              _choosingModel = false;
            });
          },
          onRefresh: widget.onRefreshModels,
          onChoicesChanged: (choices) => setState(() => _choices = choices),
          onReviewProviderAccess: widget.onReviewProviderAccess,
          scopeLabel: 'Models for ${widget.profileName}',
          refreshKey: const Key('refresh-chat-models'),
        ),
      ),
    ],
  );
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

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

class _SheetActions extends StatelessWidget {
  final VoidCallback? onCancel;
  final VoidCallback? onApply;
  final bool applying;

  const _SheetActions({
    required this.onCancel,
    required this.onApply,
    this.applying = false,
  });

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
          FilledButton(
            onPressed: onApply,
            child: Text(applying ? 'Applying…' : 'Apply'),
          ),
        ],
      ),
    );
  }
}
