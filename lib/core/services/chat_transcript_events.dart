import 'chat_runtime.dart';
import 'transcript_reading.dart';

/// Shared display handoff for live chats and passive worker event replay.
/// Each caller keeps transport, publication fencing and completion authority.
void applyChatTranscriptEvent({
  required ChatRuntime runtime,
  required TranscriptReading reading,
  required String type,
  required Map<String, dynamic> data,
}) {
  switch (type) {
    case 'message.start':
      if (!runtime.observation.executionActive) {
        runtime.beginTurn(submitting: false);
        reading.cancelReads();
        reading.updateStreaming('');
      }
    case 'message.delta':
      final text = data['text']?.toString() ?? '';
      reading.appendStreaming(text);
      runtime.observeText(text);
    case 'message.interim':
      final text = data['text']?.toString() ?? reading.streaming;
      if (text.isNotEmpty) {
        reading.appendAssistant(
          text,
          turnGeneration: runtime.turnRevision,
          reasoning: '',
          responseReused: false,
          interim: true,
        );
      }
      reading.updateStreaming('');
      runtime.finishSegment();
    case 'tool.generating':
    case 'tool.start':
    case 'tool.complete':
      final activity = runtime.observeTool(type, data);
      if (activity != null && type != 'tool.generating') {
        reading.observeTool(activity);
      }
    case 'reasoning.delta':
    case 'reasoning.available':
      runtime.observeReasoning(type, data);
  }
}
