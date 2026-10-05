import 'model_choice.dart';

/// The per-chat model and reasoning values chosen in the picker.
class ChatIntelligenceSelection {
  final ModelChoice choice;
  final String reasoningEffort;

  const ChatIntelligenceSelection({
    required this.choice,
    required this.reasoningEffort,
  });
}
