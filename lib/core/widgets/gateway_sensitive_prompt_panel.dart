import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';

import '../models/gateway_sensitive_prompt.dart';

typedef SensitivePromptResponder = Future<void> Function(String value);

class GatewaySensitivePromptPanel extends StatefulWidget {
  final GatewaySensitivePromptRequest request;
  final SensitivePromptResponder onRespond;
  final bool enabled;

  const GatewaySensitivePromptPanel({
    required this.request,
    required this.onRespond,
    this.enabled = true,
    super.key,
  });

  @override
  State<GatewaySensitivePromptPanel> createState() =>
      _GatewaySensitivePromptPanelState();
}

class _GatewaySensitivePromptPanelState
    extends State<GatewaySensitivePromptPanel> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _enabled => widget.enabled && !_submitting;

  @override
  void didUpdateWidget(GatewaySensitivePromptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.kind != widget.request.kind ||
        oldWidget.request.requestId != widget.request.requestId) {
      _controller.clear();
      _passwordController.clear();
      _submitting = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.clear();
    _passwordController.clear();
    _controller.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _respond(String value) async {
    if (!_enabled) return;
    final kind = widget.request.kind;
    final requestId = widget.request.requestId;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onRespond(value);
      if (mounted &&
          widget.request.kind == kind &&
          widget.request.requestId == requestId) {
        _controller.clear();
        _passwordController.clear();
      }
    } catch (_) {
      if (!mounted ||
          widget.request.kind != kind ||
          widget.request.requestId != requestId) {
        return;
      }
      setState(() {
        _controller.clear();
        _passwordController.clear();
        _submitting = false;
        _error = 'Hermes could not accept the response. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final savesLogin =
        request.kind == GatewaySensitivePromptKind.vaultSaveLogin;
    final showsCode = request.kind == GatewaySensitivePromptKind.vaultCode;
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
                Icons.key_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(request.description),
          const SizedBox(height: 12),
          TextField(
            key: const Key('sensitive-prompt-field'),
            controller: _controller,
            enabled: _enabled,
            obscureText: !showsCode && !savesLogin,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const <String>[],
            keyboardType: showsCode ? TextInputType.number : null,
            textInputAction: savesLogin
                ? TextInputAction.next
                : TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(borderRadius: HermesRadius.control),
              labelText: request.fieldLabel,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (value) {
              if (!savesLogin && _canSubmit) _respond(_responseValue);
            },
          ),
          if (savesLogin) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('sensitive-prompt-password'),
              controller: _passwordController,
              enabled: _enabled,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const <String>[],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(borderRadius: HermesRadius.control),
                labelText: 'Password',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) {
                if (_canSubmit) _respond(_responseValue);
              },
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('sensitive-prompt-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                key: const Key('sensitive-prompt-cancel'),
                onPressed: _enabled ? () => _respond('') : null,
                child: Text(switch (request.kind) {
                  GatewaySensitivePromptKind.vaultUnlock => 'Keep locked',
                  GatewaySensitivePromptKind.vaultSaveLogin => 'Don\'t save',
                  GatewaySensitivePromptKind.vaultCode => 'Skip',
                  _ => 'Cancel',
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _controller,
                    _passwordController,
                  ]),
                  builder: (context, _) => FilledButton(
                    key: const Key('sensitive-prompt-submit'),
                    onPressed: _enabled && _canSubmit
                        ? () => _respond(_responseValue)
                        : null,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            request.kind ==
                                    GatewaySensitivePromptKind.vaultSaveLogin
                                ? 'Save login'
                                : 'Continue',
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _canSubmit {
    if (widget.request.kind == GatewaySensitivePromptKind.vaultSaveLogin) {
      return _controller.text.trim().isNotEmpty &&
          _passwordController.text.isNotEmpty;
    }
    if (widget.request.kind == GatewaySensitivePromptKind.vaultCode) {
      return _normalizedCode.isNotEmpty;
    }
    return _controller.text.isNotEmpty;
  }

  String get _normalizedCode =>
      _controller.text.replaceAll(RegExp(r'[\s-]'), '');

  String get _responseValue {
    if (widget.request.kind == GatewaySensitivePromptKind.vaultSaveLogin) {
      return jsonEncode({
        'identifier': _controller.text.trim(),
        'password': _passwordController.text,
      });
    }
    if (widget.request.kind == GatewaySensitivePromptKind.vaultCode) {
      return _normalizedCode;
    }
    return _controller.text;
  }
}
