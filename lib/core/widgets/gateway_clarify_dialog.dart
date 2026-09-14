import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/gateway_clarify.dart';
import '../theme/profile_markdown_style.dart';

typedef ClarifyResponder = Future<void> Function(String answer);

class GatewayClarifyDialog extends StatefulWidget {
  final GatewayClarifyRequest request;
  final ClarifyResponder onRespond;
  final bool inline;
  final int number;
  final int total;

  const GatewayClarifyDialog({
    required this.request,
    required this.onRespond,
    this.inline = false,
    this.number = 1,
    this.total = 1,
    super.key,
  });

  @override
  State<GatewayClarifyDialog> createState() => _GatewayClarifyDialogState();
}

class _GatewayClarifyDialogState extends State<GatewayClarifyDialog>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.inline;
  final TextEditingController _otherController = TextEditingController();
  final Set<int> _selectedIndices = {};
  int? _selectedIndex;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String get _answer {
    final custom = _otherController.text.trim();
    if (!widget.request.multiSelect) {
      if (custom.isNotEmpty) return custom;
      final selectedIndex = _selectedIndex;
      return selectedIndex == null ? '' : widget.request.choices[selectedIndex];
    }

    final ordered = _selectedIndices.toList()..sort();
    final parts = [
      for (final index in ordered) widget.request.choices[index],
      if (custom.isNotEmpty) custom,
    ];
    return parts.join(', ');
  }

  void _selectChoice(int index) {
    if (_submitting) return;
    setState(() {
      _error = null;
      if (widget.request.multiSelect) {
        if (!_selectedIndices.add(index)) {
          _selectedIndices.remove(index);
        }
      } else {
        _selectedIndex = index;
        _otherController.clear();
      }
    });
  }

  Future<void> _respond(String answer) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onRespond(answer);
      if (mounted && !widget.inline) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Hermes could not accept the answer. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final request = widget.request;
    final answer = _answer;

    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: widget.inline ? double.infinity : 620,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.inline)
              Theme(
                data: profileMarkdownTheme(theme),
                child: MarkdownBody(
                  data: request.question,
                  selectable: true,
                  sizedImageBuilder: (_) => const Text('[Image omitted]'),
                  styleSheet: profileMarkdownStyle(theme, compact: true),
                ),
              )
            else
              SelectableText(
                request.question,
                key: const Key('clarify-question'),
                style: widget.inline
                    ? theme.textTheme.bodyMedium?.copyWith(height: 1.4)
                    : theme.textTheme.titleMedium,
              ),
            if (request.hasChoices) ...[
              const SizedBox(height: 12),
              Text(
                request.multiSelect
                    ? 'Select one or more options, then continue.'
                    : 'Select one option, or enter another answer.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              for (var index = 0; index < request.choices.length; index++)
                Semantics(
                  selected: request.multiSelect
                      ? _selectedIndices.contains(index)
                      : _selectedIndex == index,
                  button: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color:
                          (request.multiSelect
                              ? _selectedIndices.contains(index)
                              : _selectedIndex == index)
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: HermesRadius.card,
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: Key('clarify-choice-$index'),
                        minTileHeight: 48,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        leading: Icon(
                          request.multiSelect
                              ? (_selectedIndices.contains(index)
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded)
                              : (_selectedIndex == index
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded),
                        ),
                        title: Text(
                          request.choices[index],
                          style: theme.textTheme.bodyMedium,
                        ),
                        enabled: !_submitting,
                        onTap: () => _selectChoice(index),
                      ),
                    ),
                  ),
                ),
            ],
            SizedBox(height: request.hasChoices ? 8 : 16),
            TextField(
              key: const Key('clarify-other-field'),
              controller: _otherController,
              autofocus: !widget.inline && !request.hasChoices,
              enabled: !_submitting,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(borderRadius: HermesRadius.control),
                labelText: request.hasChoices ? 'Other answer' : 'Your answer',
              ),
              onChanged: (value) {
                setState(() {
                  _error = null;
                  if (!request.multiSelect && value.trim().isNotEmpty) {
                    _selectedIndex = null;
                  }
                });
              },
              onSubmitted: (_) {
                if (widget.inline) return;
                final currentAnswer = _answer;
                if (currentAnswer.isNotEmpty) _respond(currentAnswer);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('clarify-error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final actions = [
      TextButton(
        key: const Key('clarify-skip'),
        onPressed: _submitting ? null : () => _respond(''),
        child: const Text('Skip'),
      ),
      FilledButton(
        key: const Key('clarify-continue'),
        onPressed: _submitting || answer.isEmpty
            ? null
            : () => _respond(answer),
        child: _submitting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                widget.inline
                    ? (widget.number < widget.total
                          ? 'Confirm & next'
                          : 'Confirm & continue')
                    : 'Continue',
              ),
      ),
    ];
    if (widget.inline) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: HermesRadius.card,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.question_answer_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your input',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (widget.total > 1)
                  Text(
                    '${widget.number} of ${widget.total}',
                    style: theme.textTheme.labelMedium,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            content,
            const SizedBox(height: 10),
            Row(
              children: [
                actions.first,
                const SizedBox(width: 12),
                Expanded(child: actions.last),
              ],
            ),
          ],
        ),
      );
    }
    return AlertDialog(
      icon: const Icon(Icons.help_outline_rounded),
      title: const Text('Hermes needs your input'),
      content: content,
      actions: actions,
    );
  }
}
