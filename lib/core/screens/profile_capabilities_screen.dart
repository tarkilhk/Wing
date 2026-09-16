import '../widgets/studio_error.dart';
import 'package:flutter/material.dart';

import '../services/profile_gateway.dart';
import '../widgets/compact_switch.dart';

enum _CapabilityKind { skills, tools }

/// Controls the capabilities of the captured server profile, never a chat override.
class ProfileCapabilitiesScreen extends StatefulWidget {
  const ProfileCapabilitiesScreen({
    required this.gateway,
    required this.connectionLabel,
    required this.onToolSetup,
    required this.onLibrary,
    required this.onHub,
    required this.onPlugins,
    super.key,
  });

  final ProfileGateway gateway;
  final String connectionLabel;
  final Future<void> Function(String name) onToolSetup;
  final VoidCallback onLibrary;
  final VoidCallback onHub;
  final VoidCallback onPlugins;

  @override
  State<ProfileCapabilitiesScreen> createState() =>
      _ProfileCapabilitiesScreenState();
}

class _ProfileCapabilitiesScreenState extends State<ProfileCapabilitiesScreen> {
  late final _gateway = widget.gateway;
  _CapabilityKind _kind = _CapabilityKind.skills;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _saving = false;
  String _query = '';
  String? _error;
  String? _notice;
  int _loadGeneration = 0;

  bool get _skills => _kind == _CapabilityKind.skills;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final skills = _skills;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _gateway.read(skills ? 'skills' : 'tools/toolsets');
      final data = result['data'];
      if (data is! List ||
          data.any(
            (row) =>
                row is! Map ||
                row['name'] is! String ||
                (row['name'] as String).isEmpty ||
                row['enabled'] is! bool ||
                (!skills && row['configured'] is! bool),
          )) {
        throw const FormatException('Invalid capability list');
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _rows = data
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(),
      );
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _error =
            'Could not load ${skills ? 'skills' : 'tools'} from this profile. Check the connection and retry.',
      );
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggle(Map<String, dynamic> row, bool enabled) async {
    if (_saving || _loading) return;
    final name = row['name'] as String;
    if (!_skills && enabled && row['configured'] != true) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Enable ${row['label'] ?? name}?'),
          content: const Text(
            'This toolset still needs setup. Hermes may start its existing setup process on the server. Enabling it does not guarantee it is ready.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await _gateway.requireProfile();
      final result = await _gateway.put(
        _skills
            ? 'skills/toggle'
            : 'tools/toolsets/${Uri.encodeComponent(name)}',
        {if (_skills) 'name': name, 'enabled': enabled},
      );
      if (result['ok'] != true ||
          result['name'] != name ||
          result['enabled'] != enabled) {
        throw const FormatException('The change was not acknowledged');
      }
      if (!mounted) return;
      setState(() {
        row['enabled'] = enabled;
        _notice = result['post_setup_started'] != null
            ? 'Saved. Hermes started server setup; refresh to check readiness.'
            : 'Saved on the server for ${_gateway.scope.profileName}.';
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'The change could not be confirmed. Refresh to check the server before trying again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _readSkill(String name) async {
    try {
      final result = await _gateway.read('skills/content', {'name': name});
      if (result['name'] != name || result['content'] is! String) {
        throw const FormatException('Invalid skill content');
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(name)),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(result['content'] as String),
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: StudioError(
            'Could not read this skill. Check the connection and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final rows = _rows
        .where(
          (row) =>
              '${row['name']} ${row['label'] ?? ''} ${row['description'] ?? ''}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skills and tools'),
        actions: [
          IconButton(
            tooltip: 'Refresh capabilities',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${widget.connectionLabel} · ${_gateway.scope.profileName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Changes are saved on Hermes and affect other clients using this profile.',
                        style: metadataStyle,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: widget.onLibrary,
                            child: const Text('Skill library'),
                          ),
                          TextButton(
                            onPressed: widget.onHub,
                            child: const Text('Discover skills'),
                          ),
                          TextButton(
                            onPressed: widget.onPlugins,
                            child: const Text('Agent plugins'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<_CapabilityKind>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _CapabilityKind.skills,
                            label: Text('Skills'),
                          ),
                          ButtonSegment(
                            value: _CapabilityKind.tools,
                            label: Text('Tools'),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: _saving
                            ? null
                            : (value) {
                                setState(() {
                                  _kind = value.single;
                                  _rows = [];
                                  _notice = null;
                                });
                                _load();
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search capabilities',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ],
                  ),
                ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_notice!),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        StudioError(_error!),
                        TextButton(
                          onPressed: _loading || _saving ? null : _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if (_loading || _saving) const LinearProgressIndicator(),
              ],
            ),
          ),
          if (!_loading && rows.isEmpty && _error == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  _query.isEmpty
                      ? 'No ${_skills ? 'skills' : 'tools'} returned by this profile.'
                      : 'No matching capabilities.',
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final name = row['name'] as String;
                final title = row['label']?.toString() ?? name;
                final tools = row['tools'];
                return ExpansionTile(
                  key: ValueKey((_kind, name)),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  minTileHeight: 56,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  title: Text(title, style: theme.textTheme.bodyLarge),
                  subtitle: Text(
                    _skills
                        ? '${row['category'] ?? 'Skill'} · ${row['provenance'] ?? 'Installed'}'
                        : '${row['configured'] is! bool
                              ? 'Setup status unavailable'
                              : row['configured'] == true
                              ? 'Configured'
                              : 'Setup needed'}${row['platform_label'] == null ? '' : ' · ${row['platform_label']}'}',
                    style: metadataStyle,
                  ),
                  trailing: CompactSwitch(
                    semanticLabel: 'Enable $title',
                    value: row['enabled'] == true,
                    onChanged: _loading || _saving || row['enabled'] is! bool
                        ? null
                        : (value) => _toggle(row, value),
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row['description']?.toString() ?? ''),
                    if (_skills)
                      TextButton(
                        onPressed: () => _readSkill(name),
                        child: const Text('Read instructions'),
                      ),
                    if (!_skills)
                      TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                await widget.onToolSetup(name);
                                if (mounted) await _load();
                              },
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Setup and providers'),
                      ),
                    if (!_skills && tools is List) ...[
                      const SizedBox(height: 8),
                      SelectableText(tools.join(', ')),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
