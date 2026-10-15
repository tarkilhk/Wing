import 'package:flutter/material.dart';

import '../models/hermes_question.dart';
import '../presentation/tool_call_presentation.dart';
import 'profile_tool_call.dart';

/// Gateway request history uses Wing's standard Activity row, disclosure,
/// question/command sections, exact source viewer and outcome footer.
class HermesQuestionCard extends StatefulWidget {
  const HermesQuestionCard({super.key, required this.question});
  final HermesQuestion question;

  @override
  State<HermesQuestionCard> createState() => _HermesQuestionCardState();
}

class _HermesQuestionCardState extends State<HermesQuestionCard> {
  late ToolCallPresentation _call = ToolCallPresentation.question(
    widget.question,
  );

  @override
  void didUpdateWidget(HermesQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.question, widget.question)) {
      _call = ToolCallPresentation.question(widget.question);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ProfileToolCall(key: ValueKey(widget.question.id), call: _call);
}
