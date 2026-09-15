import 'package:flutter/material.dart';

import '../models/connection.dart';

/// Edits access-proxy headers while keeping saved secret values hidden.
class GatewayHeadersEditor extends StatefulWidget {
  final Set<String> savedNames;
  final bool enabled;
  final ValueChanged<Map<String, String?>> onChanged;

  const GatewayHeadersEditor({
    super.key,
    required this.savedNames,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  State<GatewayHeadersEditor> createState() => _GatewayHeadersEditorState();
}

class _HeaderRow {
  final String? savedName;
  final TextEditingController name;
  final TextEditingController value = TextEditingController();

  _HeaderRow([this.savedName])
    : name = TextEditingController(text: savedName ?? '');

  bool get keepsSavedValue =>
      savedName != null &&
      name.text.trim().toLowerCase() == savedName!.toLowerCase() &&
      value.text.isEmpty;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

class _GatewayHeadersEditorState extends State<GatewayHeadersEditor> {
  late List<_HeaderRow> _rows = _savedRows();

  List<_HeaderRow> _savedRows() {
    final names = widget.savedNames.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.map(_HeaderRow.new).toList();
  }

  @override
  void didUpdateWidget(covariant GatewayHeadersEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.savedNames.length == widget.savedNames.length &&
        oldWidget.savedNames.containsAll(widget.savedNames)) {
      return;
    }
    for (final row in _rows) {
      row.dispose();
    }
    _rows = _savedRows();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  String? _nameError(int index) {
    final name = _rows[index].name.text.trim();
    if (name.isEmpty) {
      return 'Header name is required';
    }
    final duplicate = _rows.indexed.any(
      (entry) =>
          entry.$1 != index &&
          entry.$2.name.text.trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      return 'Header names must be unique.';
    }
    try {
      validateGatewayHeaders(<String, String>{name: 'value'});
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _valueError(int index) {
    final row = _rows[index];
    if (row.keepsSavedValue) {
      return null;
    }
    if (row.value.text.isEmpty) {
      return 'Value is required';
    }
    try {
      validateGatewayHeaders(<String, String>{
        'X-Hermes-Validation': row.value.text,
      });
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  void _changed() {
    setState(() {});
    final names = <String>{};
    final result = <String, String?>{};
    for (final row in _rows) {
      final name = row.name.text.trim();
      if (name.isEmpty || !names.add(name.toLowerCase())) {
        return;
      }
      final value = row.keepsSavedValue ? null : row.value.text;
      try {
        validateGatewayHeaders(<String, String>{name: value ?? 'value'});
      } on FormatException {
        return;
      }
      result[name] = value;
    }
    widget.onChanged(result);
  }

  void _add() {
    if (!widget.enabled) {
      return;
    }
    setState(() => _rows.add(_HeaderRow()));
  }

  void _remove(int index) {
    if (!widget.enabled) {
      return;
    }
    final row = _rows.removeAt(index);
    row.dispose();
    _changed();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Access header credentials'),
      const SizedBox(height: 4),
      Text(
        'Use the names and values supplied by your administrator. Saved values stay hidden.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      for (final entry in _rows.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: ObjectKey(entry.$2.name),
                controller: entry.$2.name,
                enabled: widget.enabled,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (_) => _nameError(entry.$1),
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(labelText: 'Header name'),
                autocorrect: false,
              ),
              TextFormField(
                key: ObjectKey(entry.$2.value),
                controller: entry.$2.value,
                enabled: widget.enabled,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (_) => _valueError(entry.$1),
                onChanged: (_) => _changed(),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Value',
                  hintText: entry.$2.savedName == null
                      ? null
                      : 'Keep saved value',
                ),
                autocorrect: false,
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: 'Remove header',
                  onPressed: widget.enabled ? () => _remove(entry.$1) : null,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: widget.enabled ? _add : null,
          icon: const Icon(Icons.add),
          label: const Text('Add header'),
        ),
      ),
    ],
  );
}
