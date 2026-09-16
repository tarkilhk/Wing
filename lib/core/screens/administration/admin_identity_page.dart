import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/profile_gateway.dart';
import '../../widgets/server_connection_label.dart';
import 'admin_widgets.dart';

Future<bool> showAdminIdentityEditor(
  BuildContext context, {
  required ProfileGateway gateway,
  required String connectionLabel,
}) async {
  final status = ServerConnectionScope.of(context);
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) {
            final page = AdminIdentityPage(
              gateway: gateway,
              connectionLabel: connectionLabel,
            );
            return status == null
                ? page
                : ServerConnectionScope(status: status, child: page);
          },
        ),
      ) ??
      false;
}

/// Edits the description and SOUL owned by one captured server profile.
class AdminIdentityPage extends StatefulWidget {
  final ProfileGateway gateway;
  final String connectionLabel;

  const AdminIdentityPage({
    super.key,
    required this.gateway,
    required this.connectionLabel,
  });

  @override
  State<AdminIdentityPage> createState() => _AdminIdentityPageState();
}

class _AdminIdentityPageState extends State<AdminIdentityPage> {
  final _description = TextEditingController();
  final _soul = TextEditingController();
  late final ProfileGateway _gateway;
  late final String _profileName;
  late final String _connectionLabel;
  String _savedDescription = '';
  String _savedSoul = '';
  bool _loading = true;
  bool _loaded = false;
  bool _saving = false;
  bool _anyApplied = false;
  bool _allowPop = false;
  String? _error;
  String? _notice;

  bool get _descriptionDirty => _description.text != _savedDescription;
  bool get _soulDirty => _soul.text != _savedSoul;
  bool get _dirty => _descriptionDirty || _soulDirty;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway;
    _profileName = widget.gateway.scope.profileName;
    _connectionLabel = widget.connectionLabel;
    _description.addListener(_edited);
    _soul.addListener(_edited);
    unawaited(_load());
  }

  @override
  void dispose() {
    _description.dispose();
    _soul.dispose();
    super.dispose();
  }

  void _edited() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, String>> _describe() async {
    final result = await _gateway.call('profiles.describe', {
      'name': _profileName,
    });
    if (result['name'] != _profileName ||
        result['description'] is! String ||
        result['soul'] is! String) {
      throw const FormatException('Invalid profile description');
    }
    return {
      'description': result['description'] as String,
      'soul': result['soul'] as String,
    };
  }

  Future<void> _load() async {
    if (_saving) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final values = await _describe();
      if (!mounted) {
        return;
      }
      _savedDescription = values['description']!;
      _savedSoul = values['soul']!;
      _description.text = _savedDescription;
      _soul.text = _savedSoul;
      _loaded = true;
    } catch (_) {
      if (mounted) {
        _error = 'This profile could not be loaded. Retry.';
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_loaded || _loading || _saving || !_dirty) {
      return;
    }
    final wanted = <String, String>{
      if (_descriptionDirty) 'description': _description.text,
      if (_soulDirty) 'soul': _soul.text,
    };
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await _gateway.requireProfile();
      if (!mounted) {
        return;
      }
      final response = await _gateway.call('profiles.configure', {
        'name': _profileName,
        ...wanted,
      });
      final ok = response['ok'];
      final rawApplied = response['applied'];
      if (ok is! bool || rawApplied is! Map) {
        throw const FormatException('Invalid profile save response');
      }
      if (wanted.keys.any((key) => rawApplied[key] is! bool)) {
        throw const FormatException('Incomplete profile save response');
      }
      final applied = <String>{
        for (final key in wanted.keys)
          if (rawApplied[key] == true) key,
      };
      if (ok != (applied.length == wanted.length)) {
        throw const FormatException('Inconsistent profile save response');
      }

      Map<String, String>? authoritative;
      try {
        authoritative = await _describe();
      } catch (_) {
        // The acknowledgement is still exact for these replacement writes.
      }
      if (!mounted) {
        return;
      }
      _applyResult(wanted, applied, authoritative);
      _anyApplied = _anyApplied || applied.isNotEmpty;
      if (applied.length == wanted.length) {
        await _finish(true);
        return;
      }
      final saved = _fieldLabels(applied);
      final missed = _fieldLabels(wanted.keys.toSet().difference(applied));
      _notice = saved.isEmpty ? null : 'Saved: $saved.';
      _error = 'Not applied: $missed. Review the fields before trying again.';
    } catch (_) {
      if (mounted) {
        _error =
            'The save could not be confirmed. Your edits are still here; review them before trying again.';
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _applyResult(
    Map<String, String> wanted,
    Set<String> applied,
    Map<String, String>? authoritative,
  ) {
    final preserveDescription =
        wanted.containsKey('description') && !applied.contains('description');
    final preserveSoul =
        wanted.containsKey('soul') && !applied.contains('soul');
    if (authoritative != null) {
      _savedDescription = authoritative['description']!;
      _savedSoul = authoritative['soul']!;
      if (!preserveDescription) {
        _description.text = _savedDescription;
      }
      if (!preserveSoul) {
        _soul.text = _savedSoul;
      }
      return;
    }
    if (applied.contains('description')) {
      _savedDescription = wanted['description']!.trim();
      _description.text = _savedDescription;
    }
    if (applied.contains('soul')) {
      _savedSoul = wanted['soul']!;
      _soul.text = _savedSoul;
    }
  }

  Future<void> _close() async {
    if (_saving) {
      return;
    }
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('Edits that were not saved will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) {
        return;
      }
    }
    await _finish(_anyApplied);
  }

  Future<void> _finish(bool result) async {
    if (!mounted) {
      return;
    }
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AdminPage(
      title: 'Identity',
      scope: '$_connectionLabel / $_profileName',
      bottomNavigationBar: !_loaded
          ? null
          : AdminEditorActions(
              dirtyCount: (_descriptionDirty ? 1 : 0) + (_soulDirty ? 1 : 0),
              saving: _saving,
              onClose: _close,
              onSave: _dirty ? _save : null,
            ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_loaded
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: AdminNotice.error(
                _error ?? 'This profile could not be loaded.',
                retry: _load,
              ),
            )
          : SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Give your agent a point of view',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A short description helps you recognize this profile. Its SOUL gives the agent instructions about how to work.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stored for this profile on $_connectionLabel.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  if (_notice != null) AdminNotice(_notice!),
                  if (_error != null) AdminNotice.error(_error!),
                  TextField(
                    key: const ValueKey('profile-description-field'),
                    controller: _description,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'What this profile is for',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const ValueKey('profile-soul-field'),
                    controller: _soul,
                    enabled: !_saving,
                    minLines: 12,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: 'SOUL',
                      hintText: 'Instructions that shape this profile',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    ),
  );
}

String _fieldLabels(Set<String> fields) => [
  if (fields.contains('description')) 'description',
  if (fields.contains('soul')) 'SOUL',
].join(', ');
