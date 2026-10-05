import 'studio_task_marker.dart';
import 'studio_selection_tile.dart';
import 'studio_action_label.dart';
import 'studio_error.dart';
import 'package:flutter/material.dart';
import '../theme/wing_theme.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/gateway_clarify.dart';
import '../theme/profile_markdown_style.dart';

typedef ClarifyResponder = Future<void> Function(String answer);

class GatewayClarifyDialog extends StatefulWidget {
  final GatewayClarifyRequest request;
  final ClarifyResponder onRespond;
  final int number;
  final int total;

  const GatewayClarifyDialog({
    required this.request,
    required this.onRespond,
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
  bool get wantKeepAlive => true;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Hermes could not accept the answer. Please try again.';
      });
    }
  }

  Widget _choice(int index) {
    final theme = Theme.of(context);
    final multiple = widget.request.multiSelect;
    final selected = multiple
        ? _selectedIndices.contains(index)
        : _selectedIndex == index;
    final title = Text(widget.request.choices[index]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: WingRadius.card,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: multiple
            ? StudioSelectionTile(
                key: Key('clarify-choice-$index'),
                value: selected,
                onChanged: _submitting ? null : (_) => _selectChoice(index),
                title: title,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              )
            : StudioRadioTile<int>(
                key: Key('clarify-choice-$index'),
                value: index,
                enabled: !_submitting,
                title: title,
                minTileHeight: 48,
                minVerticalPadding: 8,
                contentPadding: EdgeInsets.zero,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final request = widget.request;
    final answer = request.answer(
      selectedIndex: _selectedIndex,
      selectedIndices: _selectedIndices,
      customText: _otherController.text,
    );

    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Theme(
              data: profileMarkdownTheme(theme),
              child: MarkdownBody(
                checkboxBuilder: (checked) =>
                    StudioTaskMarker(completed: checked),
                data: request.question,
                selectable: true,
                sizedImageBuilder: (_) => const Text('[Image omitted]'),
                styleSheet: profileMarkdownStyle(theme, compact: true),
              ),
            ),
            if (request.hasChoices) ...[
              const SizedBox(height: 12),
              Text(
                request.multiSelect
                    ? 'Select one or more options, then continue.'
                    : 'Select one option, or enter another answer.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RadioGroup<int>(
                groupValue: _selectedIndex,
                onChanged: (index) {
                  if (index != null) _selectChoice(index);
                },
                child: Column(
                  children: [
                    for (var index = 0; index < request.choices.length; index++)
                      _choice(index),
                  ],
                ),
              ),
            ],
            SizedBox(height: request.hasChoices ? 8 : 16),
            TextField(
              key: const Key('clarify-other-field'),
              controller: _otherController,
              enabled: !_submitting,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(borderRadius: WingRadius.control),
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
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              StudioError(_error!, key: const Key('clarify-error')),
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
        child: StudioActionLabel(
          widget.number < widget.total
              ? 'Confirm & next'
              : 'Confirm & continue',
          busy: _submitting,
        ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: WingRadius.card,
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
          const SizedBox(height: 12),
          content,
          const SizedBox(height: 12),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 12,
            overflowSpacing: 8,
            children: actions,
          ),
        ],
      ),
    );
  }
}
