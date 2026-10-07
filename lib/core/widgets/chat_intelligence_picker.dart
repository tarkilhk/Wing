import 'package:flutter/material.dart';
import '../models/chat_intelligence.dart';
import '../models/model_choice.dart';
import '../presentation/chat_model_labels.dart';
import '../theme/wing_theme.dart';
import 'chat_model_controls.dart';
import 'model_chooser.dart';
import 'studio_error.dart';

class ChatIntelligenceButton extends StatelessWidget {
  const ChatIntelligenceButton({
    required this.model,
    required this.reasoningEffort,
    required this.fastMode,
    required this.observation,
    required this.onPressed,
    required this.onReasoningChanged,
    required this.onFastChanged,
    this.loading = false,
    super.key,
  });
  final String model;
  final String reasoningEffort;
  final ChatFastMode? fastMode;
  final ModelChoice? observation;
  final bool loading;
  final VoidCallback? onPressed;
  final ValueChanged<String>? onReasoningChanged;
  final ValueChanged<ChatFastMode>? onFastChanged;
  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = [
          if (observation?.controls?.reasoning == true && fastMode != null)
            ChatReasoningControl(
              effort: reasoningEffort,
              canDisable: observation!.controls!.canDisableReasoning,
              onChanged: onPressed == null ? null : onReasoningChanged,
            ),
          if (observation?.controls?.fast == true && fastMode != null)
            ChatFastControl(
              mode: fastMode!,
              onChanged: onPressed == null ? null : onFastChanged,
            ),
        ];
        final modelButton = TextButton(
          key: const Key('chat-intelligence-button'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            foregroundColor: tokens.onSurface,
            textStyle: tokens.typography.label,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              if (loading) const SizedBox(width: 4),
              Flexible(
                child: Text(
                  compactChatModelLabel(model),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
            ],
          ),
        );
        if (constraints.maxWidth < controls.length * 48 + 64 &&
            controls.isNotEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              modelButton,
              Wrap(alignment: WrapAlignment.end, children: controls),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Tooltip(message: 'Model $model', child: modelButton),
            ),
            ...controls,
          ],
        );
      },
    );
  }
}

Future<ChatIntelligenceSelection?> showChatIntelligencePicker({
  required BuildContext context,
  required List<ModelChoice> choices,
  required ModelChoice initialChoice,
  required String initialReasoningEffort,
  required ChatFastMode initialFastMode,
  required String defaultModel,
  required String profileName,
  required Future<List<ModelChoice>> Function() refreshModels,
  required Future<void> Function() reviewProviderAccess,
  required Future<bool> Function(ChatIntelligenceSelection) onCommit,
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
      initialFastMode: initialFastMode,
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

/// One compact model ledger. Model, reasoning and fast stay staged until Apply.
class ChatIntelligenceSheet extends StatefulWidget {
  const ChatIntelligenceSheet({
    required this.choices,
    required this.initialChoice,
    required this.initialReasoningEffort,
    required this.initialFastMode,
    required this.defaultModel,
    required this.profileName,
    required this.onRefreshModels,
    required this.onReviewProviderAccess,
    required this.onApply,
    required this.onCancel,
    required this.onCommit,
    this.defaultProvider,
    super.key,
  });
  final List<ModelChoice> choices;
  final ModelChoice initialChoice;
  final String initialReasoningEffort;
  final ChatFastMode initialFastMode;
  final String defaultModel;
  final String? defaultProvider;
  final String profileName;
  final Future<List<ModelChoice>> Function() onRefreshModels;
  final VoidCallback onReviewProviderAccess;
  final ValueChanged<ChatIntelligenceSelection> onApply;
  final Future<bool> Function(ChatIntelligenceSelection) onCommit;
  final VoidCallback onCancel;
  @override
  State<ChatIntelligenceSheet> createState() => _ChatIntelligenceSheetState();
}

class _ChatIntelligenceSheetState extends State<ChatIntelligenceSheet> {
  late List<ModelChoice> _choices;
  late ModelChoice _selectedChoice;
  late String _selectedEffort;
  late ChatFastMode _fastMode;
  bool _applying = false;
  String? _applyError;
  @override
  void initState() {
    super.initState();
    _choices = widget.choices;
    _selectedChoice = widget.initialChoice;
    _selectedEffort = widget.initialReasoningEffort;
    _fastMode = widget.initialFastMode;
  }

  void _selectChoice(ModelChoice choice) {
    final next = ChatIntelligenceSelection(
      choice: _selectedChoice,
      reasoningEffort: _selectedEffort,
      fastMode: _fastMode,
    ).withChoice(choice);
    setState(() {
      _selectedChoice = next.choice;
      _selectedEffort = next.reasoningEffort;
      _fastMode = next.fastMode;
    });
  }

  Future<void> _apply() async {
    if (_applying) return;
    final selection = ChatIntelligenceSelection(
      choice: _selectedChoice,
      reasoningEffort: _selectedEffort,
      fastMode: _fastMode,
    );
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      final applied = await widget.onCommit(selection);
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
            : 'Could not apply the settings. Your choice is still here.',
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _enterModel() async {
    final selected = await showDialog<ModelChoice>(
      context: context,
      builder: (_) => _ManualModelDialog(
        choices: _choices,
        initialProvider: _selectedChoice.provider,
      ),
    );
    if (mounted && selected != null) {
      _selectChoice(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final controls = _selectedChoice.controls;
    return PopScope(
      canPop: !_applying,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height * .86 - keyboard).clamp(
              0,
              720,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('Models', style: tokens.typography.section),
                      const SizedBox(width: 8),
                      Text(
                        '${_choices.length}',
                        style: tokens.typography.label.copyWith(
                          color: tokens.muted,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _applying ? null : widget.onCancel,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ModelChooser(
                    choices: _choices,
                    selected: ModelSelection.model(_selectedChoice),
                    enabled: !_applying,
                    onSelected: (selection) {
                      if (selection.choice != null) {
                        _selectChoice(selection.choice!);
                      }
                    },
                    onRefresh: widget.onRefreshModels,
                    onChoicesChanged: (choices) => setState(() {
                      _choices = choices;
                      _selectedChoice =
                          choices
                              .where(
                                (c) =>
                                    ModelSelection.model(c) ==
                                    ModelSelection.model(_selectedChoice),
                              )
                              .firstOrNull ??
                          _selectedChoice;
                    }),
                    onReviewProviderAccess: widget.onReviewProviderAccess,
                    scopeLabel: 'Models for ${widget.profileName}',
                    refreshKey: const Key('refresh-chat-models'),
                  ),
                ),
                if (_applyError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: StudioError(_applyError!),
                  ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: tokens.border)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    overflowAlignment: OverflowBarAlignment.end,
                    overflowSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (controls?.reasoning == true)
                            ChatReasoningControl(
                              effort: _selectedEffort,
                              canDisable: controls!.canDisableReasoning,
                              onChanged: _applying
                                  ? null
                                  : (value) =>
                                        setState(() => _selectedEffort = value),
                            ),
                          if (controls?.fast == true)
                            ChatFastControl(
                              mode: _fastMode,
                              showLabel: true,
                              onChanged: _applying
                                  ? null
                                  : (value) =>
                                        setState(() => _fastMode = value),
                            ),
                          PopupMenuButton<String>(
                            tooltip: 'More model options',
                            enabled: !_applying,
                            icon: const Icon(Icons.more_horiz_rounded),
                            onSelected: (value) {
                              if (value == 'manual') {
                                _enterModel();
                              } else {
                                widget.onReviewProviderAccess();
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'manual',
                                child: Text('Enter model ID'),
                              ),
                              const PopupMenuItem(
                                value: 'access',
                                child: Text('Review provider access'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      FilledButton(
                        onPressed: _applying ? null : _apply,
                        child: Text(_applying ? 'Applying…' : 'Apply'),
                      ),
                    ],
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

/// This route owns its input controller until its closing animation ends.
class _ManualModelDialog extends StatefulWidget {
  const _ManualModelDialog({
    required this.choices,
    required this.initialProvider,
  });
  final List<ModelChoice> choices;
  final String initialProvider;
  @override
  State<_ManualModelDialog> createState() => _ManualModelDialogState();
}

class _ManualModelDialogState extends State<_ManualModelDialog> {
  final _id = TextEditingController();
  late final _routes = <String, String>{
    for (final c in widget.choices) c.provider: c.routeLabel,
  };
  late String _provider;
  @override
  void initState() {
    super.initState();
    _provider = _routes.containsKey(widget.initialProvider)
        ? widget.initialProvider
        : _routes.keys.firstOrNull ?? '';
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = ModelChoice.isValidEnteredId(_id.text);
    return AlertDialog(
      scrollable: true,
      title: const Text('Enter model ID'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _routes.containsKey(_provider) ? _provider : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Provider'),
            items: [
              for (final route in _routes.entries)
                DropdownMenuItem(
                  value: route.key,
                  child: Text(route.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _provider = value);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('manual-model-id'),
            controller: _id,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Model ID',
              errorText: _id.text.isNotEmpty && !valid
                  ? 'Use a model ID without spaces or command flags.'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !valid || _provider.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.choices
                          .where(
                            (c) =>
                                c.provider == _provider &&
                                c.model == _id.text.trim(),
                          )
                          .firstOrNull ??
                      ModelChoice(
                        provider: _provider,
                        model: _id.text.trim(),
                        providerLabel: _routes[_provider],
                      ),
                ),
          child: const Text('Use model'),
        ),
      ],
    );
  }
}
