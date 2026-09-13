import 'package:flutter/material.dart';

import '../models/queued_prompt_draft.dart';

class QueuedPromptEditor extends StatefulWidget {
  const QueuedPromptEditor({
    super.key,
    required this.prompt,
    required this.onSave,
  });

  final QueuedPromptDraft prompt;
  final Future<void> Function(String) onSave;

  @override
  State<QueuedPromptEditor> createState() => _QueuedPromptEditorState();
}

class _QueuedPromptEditorState extends State<QueuedPromptEditor> {
  late final _text = TextEditingController(text: widget.prompt.text);
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_text.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Edit queued message'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const ValueKey('queued-message-editor'),
              controller: _text,
              autofocus: true,
              enabled: !_saving,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Message'),
              validator: (value) {
                final text = value!.trim();
                if (text.isEmpty && widget.prompt.attachments.isEmpty) {
                  return 'Enter a message.';
                }
                if (text.startsWith('/')) {
                  return 'Slash commands cannot be queued.';
                }
                return null;
              },
            ),
            for (final attachment in widget.prompt.attachments)
              Text(attachment.name),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}
