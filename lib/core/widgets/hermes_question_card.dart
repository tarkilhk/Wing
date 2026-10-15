import 'package:flutter/material.dart';

import '../models/hermes_question.dart';
import 'anchored_expansion_tile.dart';
import 'source_code_block.dart';

/// A passive history entry. Code rendering is admitted only while expanded;
/// the live request owner supplies any actionable controls separately.
class HermesQuestionCard extends StatefulWidget {
  const HermesQuestionCard({super.key, required this.question});
  final HermesQuestion question;

  @override
  State<HermesQuestionCard> createState() => _HermesQuestionCardState();
}

class _HermesQuestionCardState extends State<HermesQuestionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(question.timestamp.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return AnchoredExpansionTile(
      key: ValueKey(('hermes-question', question.id)),
      title: Text(question.title),
      subtitle: Text(
        [
          if (question.sender.isNotEmpty) question.sender,
          MaterialLocalizations.of(
            context,
          ).formatShortDate(question.timestamp.toLocal()),
          time,
        ].join(' · '),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      onExpansionChanged: (value) => setState(() => _expanded = value),
      children: _expanded
          ? [
              if (question.description.isNotEmpty) Text(question.description),
              if (question.command.isNotEmpty)
                SourceCodeBlock(
                  code: question.command,
                  language: 'bash',
                  headerAction: null,
                ),
            ]
          : const [],
    );
  }
}
