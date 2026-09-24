import 'studio_action_label.dart';
import 'studio_error.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/profile_gateway.dart';
import '../theme/wing_theme.dart';
import 'model_chooser.dart';

Future<bool> showProfileDefaultModelSheet(
  BuildContext context, {
  required ProfileGateway gateway,
  required String connectionLabel,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => ProfileDefaultModelSheet(
        gateway: gateway,
        connectionLabel: connectionLabel,
      ),
    ) ??
    false;

class ProfileDefaultModelSheet extends StatefulWidget {
  final ProfileGateway gateway;
  final String connectionLabel;

  const ProfileDefaultModelSheet({
    super.key,
    required this.gateway,
    required this.connectionLabel,
  });

  @override
  State<ProfileDefaultModelSheet> createState() =>
      _ProfileDefaultModelSheetState();
}

class _ProfileDefaultModelSheetState extends State<ProfileDefaultModelSheet> {
  late final ProfileGateway _gateway;
  late final String _profileName;
  late final String _connectionLabel;
  List<ModelChoice> _choices = const [];
  ModelChoice? _saved;
  ModelChoice? _selected;
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;
  String? _error;
  String? _notice;

  bool get _dirty =>
      _selected != null &&
      (_saved == null ||
          _saved!.provider != _selected!.provider ||
          _saved!.model != _selected!.model);

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway;
    _profileName = widget.gateway.scope.profileName;
    _connectionLabel = widget.connectionLabel;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final values = await Future.wait([
        _gateway.read('model/info'),
        _gateway.read('model/options', {'explicit_only': '1'}),
      ]);
      final current = _choiceFrom(values[0]);
      final choices = ModelChoice.fromOptions(values[1]);
      final selected = current == null
          ? const <ModelChoice>[]
          : choices
                .where(
                  (choice) =>
                      choice.provider == current.provider &&
                      choice.model == current.model,
                )
                .toList();
      if (!mounted) return;
      _choices = choices;
      _saved = selected.firstOrNull ?? current;
      _selected = _saved;
    } catch (_) {
      if (mounted) _error = 'The profile models could not be loaded. Retry.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<ModelChoice>> _refreshChoices() async => ModelChoice.fromOptions(
    await _gateway.read('model/options', {
      'explicit_only': '1',
      'refresh': '1',
    }),
  );

  Future<void> _save() async {
    final wanted = _selected;
    if (_loading || _saving || !_dirty || wanted == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      var result = await _write(wanted);
      if (result['confirm_required'] == true) {
        final message = result['confirm_message']?.toString().trim() ?? '';
        if (!mounted) return;
        final accepted =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Confirm model change'),
                content: Text(
                  message.isEmpty
                      ? 'Hermes requires confirmation before using this model.'
                      : message,
                ),
                actions: [
                  TextButton(
                    key: const Key('profile-model-confirm-cancel'),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const Key('profile-model-confirm-accept'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!accepted) {
          if (mounted) setState(() => _notice = 'Model change cancelled.');
          return;
        }
        result = await _write(wanted, confirmed: true);
      }
      if (result['confirm_required'] == true || result['ok'] != true) {
        throw StateError(
          result['confirm_message']?.toString() ?? 'Model was not changed.',
        );
      }
      final authoritative = _choiceFrom(await _gateway.read('model/info'));
      if (authoritative == null ||
          authoritative.provider != wanted.provider ||
          authoritative.model != wanted.model) {
        throw StateError('Model readback did not match');
      }
      if (!mounted) return;
      _allowPop = true;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        _error =
            'The model change could not be confirmed. Review the selection and try again.';
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>> _write(
    ModelChoice wanted, {
    bool confirmed = false,
  }) async {
    await _gateway.requireProfile();
    return _gateway.post('model/set', {
      'scope': 'main',
      'provider': wanted.provider,
      'model': wanted.model,
      if (confirmed) 'confirm_expensive_model': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WingTokens.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = (MediaQuery.sizeOf(context).height - keyboard - 24).clamp(
      0.0,
      MediaQuery.sizeOf(context).height * 0.82,
    );
    return PopScope(
      canPop: !_saving || _allowPop,
      child: AnimatedPadding(
        duration: WingMotion.standard,
        curve: WingMotion.curve,
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text(
                  'Profile default model',
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '$_profileName on $_connectionLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WingSpacing.lg),
                child: Text(
                  'For new chats only',
                  style: tokens.typography.body.copyWith(color: tokens.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WingSpacing.lg,
                  ),
                  child: StudioError(
                    _error!,
                    key: const Key('profile-model-error'),
                  ),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WingSpacing.lg,
                  ),
                  child: Text(_notice!, key: const Key('profile-model-notice')),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null && _choices.isEmpty
                    ? Center(
                        child: TextButton(
                          key: const Key('profile-model-retry'),
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      )
                    : ModelChooser(
                        choices: _choices,
                        selected: _selected == null
                            ? null
                            : ModelSelection.model(_selected!),
                        onSelected: (selection) {
                          final choice = selection.choice;
                          if (_saving || choice == null) return;
                          setState(() {
                            _selected = choice;
                            _error = null;
                            _notice = null;
                          });
                        },
                        onRefresh: _refreshChoices,
                        scopeLabel: 'Models for $_profileName',
                        keyPrefix: 'profile-model',
                        enabled: !_saving,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WingSpacing.lg,
                  WingSpacing.sm,
                  WingSpacing.lg,
                  WingSpacing.md,
                ),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      key: const Key('profile-model-save'),
                      onPressed: _dirty && !_saving ? _save : null,
                      child: StudioActionLabel('Save default', busy: _saving),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ModelChoice? _choiceFrom(Map<String, dynamic> value) {
  final provider = value['provider']?.toString().trim() ?? '';
  final model = value['model']?.toString().trim() ?? '';
  return provider.isEmpty || model.isEmpty
      ? null
      : ModelChoice(provider: provider, model: model);
}
