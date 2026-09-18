import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../widgets/chat_intelligence_picker.dart';
import '../../widgets/profile_default_model_sheet.dart';
import 'admin_widgets.dart';
import 'admin_settings_page.dart';
import 'admin_providers_page.dart';
import '../../models/provider_access.dart';

class AdminDefaultsPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminDefaultsPage({super.key, required this.profile});
  @override
  State<AdminDefaultsPage> createState() => _AdminDefaultsPageState();
}

class _AdminDefaultsPageState extends State<AdminDefaultsPage> {
  late final _profile = widget.profile;
  bool _busy = false;
  String? _error;
  Future<void> _aux(
    String task,
    List<ChatModelChoice> choices,
    VoidCallback refresh,
  ) async {
    final choice = task == '__reset__'
        ? const ChatModelChoice(provider: 'auto', model: '')
        : await chooseAdminModel(context, choices, allowAuto: true);
    if (choice == null || !mounted) return;
    if (task == '__reset__' &&
        !await adminConfirm(
          context,
          'Reset all helper models?',
          'All helper tasks will choose automatically. Their saved endpoint credentials will be cleared.',
          action: 'Reset all',
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {
        'scope': 'auxiliary',
        'task': task,
        'provider': choice.provider,
        'model': choice.model,
      };
      var result = await _profile.write('POST', 'model/set', body);
      if (result['confirm_required'] == true) {
        if (!mounted ||
            !await adminConfirm(
              context,
              'Confirm model change',
              '${result['confirm_message'] ?? 'This model may increase cost.'}',
              action: 'Use model',
            )) {
          return;
        }
        result = await _profile.write('POST', 'model/set', {
          ...body,
          'confirm_expensive_model': true,
        });
      }
      if (result['ok'] != true) {
        throw const AdministrationFailure('Model change was not acknowledged.');
      }
      final after = administrationRows(
        (await _profile.read('model/auxiliary'))['tasks'],
      );
      final targets = after.where(
        (r) => task == '__reset__' || r['task'] == task,
      );
      if (targets.isEmpty ||
          targets.any(
            (r) =>
                r['provider'] != choice.provider || r['model'] != choice.model,
          )) {
        throw const AdministrationFailure(
          'Helper model save could not be confirmed.',
        );
      }
      refresh();
      if (mounted) {
        adminMessage(context, 'Helper defaults saved for ${_profile.name}.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Models and reasoning',
    scope: _profile.label,
    child: AdminLoad(
      load: () async {
        final data = await Future.wait([
          _profile.read('model/info'),
          _profile.read('model/options', {'explicit_only': '1'}),
          _profile.read('model/auxiliary'),
        ]);
        return {'info': data[0], 'options': data[1], 'aux': data[2]};
      },
      builder: (context, data, refresh) {
        final info = data['info'] as Map;
        final options = Map<String, dynamic>.from(data['options'] as Map);
        final choices = ChatModelChoice.fromOptions(options);
        final provider = administrationRows(
          options['providers'],
        ).where((r) => (r['slug'] ?? r['id']) == info['provider']).firstOrNull;
        final caps =
            (provider?['capabilities'] as Map?)?[info['model']] as Map? ?? {};
        final fields = <AdminField>[
          if (caps['reasoning'] == true)
            AdminField(
              'agent.reasoning_effort',
              'Reasoning effort',
              AdminFieldKind.choice,
              choices: ['', ...chatReasoningEffortLabels.keys],
            ),
          if (caps['fast'] == true)
            const AdminField(
              'agent.service_tier',
              'Service tier',
              AdminFieldKind.choice,
              choices: ['', 'normal', 'fast'],
            ),
        ];
        final tasks = administrationRows((data['aux'] as Map)['tasks']);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) AdminNotice.error(_error!),
            Text(
              'New-chat defaults · Existing chats keep their model choices.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            AdminGroup(
              children: [
                AdminRow(
                  title: 'Default model',
                  subtitle: '${info['provider']} / ${info['model']}',
                  icon: Icons.auto_awesome_outlined,
                  onTap: _busy
                      ? null
                      : () async {
                          await showProfileDefaultModelSheet(
                            context,
                            gateway: _profile.gateway,
                            connectionLabel: _profile.server.connectionLabel,
                          );
                          refresh();
                        },
                ),
                if (fields.isNotEmpty)
                  AdminRow(
                    title: 'Reasoning and speed',
                    subtitle: 'Defaults supported by this model',
                    icon: Icons.speed,
                    onTap: () => adminPushProfile(
                      context,
                      _profile,
                      (context, profile) => AdminSettingsPage(
                        profile: profile,
                        title: 'Reasoning and speed',
                        fields: fields,
                        beforeSave: () async {
                          final latest = await profile.read('model/info');
                          if (latest['provider'] != info['provider'] ||
                              latest['model'] != info['model']) {
                            throw const AdministrationFailure(
                              'The default model changed elsewhere. Reopen its reasoning and speed settings. Your edits are kept.',
                            );
                          }
                        },
                      ),
                    ),
                  ),
                AdminRow(
                  title: 'Fallback models',
                  subtitle: 'Ordered alternatives when a model is unavailable',
                  icon: Icons.alt_route,
                  onTap: () => adminPushProfile(
                    context,
                    _profile,
                    (context, profile) =>
                        AdminFallbackPage(profile: profile, choices: choices),
                  ),
                ),
              ],
            ),
            AdminLoad(
              expand: false,
              load: () => _profile.read('providers/oauth'),
              builder: (context, accessData, refreshAccess) {
                final providerRow = administrationRows(
                  accessData['providers'],
                ).where((row) => row['id'] == info['provider']).firstOrNull;
                return AdminRow(
                  title: 'Account access',
                  icon: Icons.key_outlined,
                  subtitle: providerRow == null
                      ? 'Source unavailable · Review provider access'
                      : '${providerInventoryStatus(ProviderAccess(providerRow))} · ${(providerRow['status'] as Map?)?['source_label'] ?? 'Source unavailable'}',
                  onTap: () async {
                    if (providerRow == null) {
                      await adminPushProfile(
                        context,
                        _profile,
                        (context, profile) =>
                            AdminProvidersPage(profile: profile, shared: false),
                      );
                    } else {
                      await adminPushProfile(
                        context,
                        _profile,
                        (context, profile) => AdminProviderDetail(
                          profile: profile,
                          shared: false,
                          providerId: providerRow['id'] as String,
                        ),
                      );
                    }
                    refreshAccess();
                  },
                );
              },
            ),
            if (fields.isEmpty)
              const AdminNotice(
                'Reasoning and speed capabilities were not reported for this model.',
              ),
            const SizedBox(height: 24),
            Text(
              'Helper models',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const AdminNotice(
              'Automatic tasks choose through Hermes. Named assignments keep their own provider.',
            ),
            AdminGroup(
              children: [
                for (final task in tasks)
                  ListTile(
                    title: Text('${task['task']}'.replaceAll('_', ' ')),
                    subtitle: Text(
                      task['provider'] == 'auto'
                          ? 'Automatic'
                          : '${task['provider']} / ${task['model']}${choices.any((c) => c.provider == task['provider'] && c.model == task['model']) ? '' : ' · Not in the available model list'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () => _aux(task['task'] as String, choices, refresh),
                  ),
              ],
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _aux('__reset__', choices, refresh),
              child: const Text('Reset all helper models'),
            ),
          ],
        );
      },
    ),
  );
}

Future<ChatModelChoice?> chooseAdminModel(
  BuildContext context,
  List<ChatModelChoice> choices, {
  bool allowAuto = false,
}) => showDialog<ChatModelChoice>(
  context: context,
  builder: (_) => _AdminModelPicker(choices: choices, allowAuto: allowAuto),
);

class _AdminModelPicker extends StatefulWidget {
  final List<ChatModelChoice> choices;
  final bool allowAuto;
  const _AdminModelPicker({required this.choices, required this.allowAuto});
  @override
  State<_AdminModelPicker> createState() => _AdminModelPickerState();
}

class _AdminModelPickerState extends State<_AdminModelPicker> {
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Choose model'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(labelText: 'Search models'),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.choices.any(
                (c) =>
                    '${c.provider} ${c.model}'.toLowerCase().contains(_query),
              )) ...[
                AdminNotice(
                  _query.isEmpty
                      ? 'No models are available from this provider.'
                      : 'No models match this search.',
                ),
                if (_query.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    child: const Text('Clear search'),
                  ),
              ],
              if (widget.allowAuto)
                ListTile(
                  title: const Text('Automatic'),
                  onTap: () => Navigator.pop(
                    context,
                    const ChatModelChoice(provider: 'auto', model: ''),
                  ),
                ),
              for (final choice in widget.choices.where(
                (c) =>
                    '${c.provider} ${c.model}'.toLowerCase().contains(_query),
              ))
                ListTile(
                  title: Text(choice.model),
                  subtitle: Text(choice.routeLabel),
                  onTap: () => Navigator.pop(context, choice),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class AdminFallbackPage extends StatefulWidget {
  final ProfileAdministration profile;
  final List<ChatModelChoice> choices;
  const AdminFallbackPage({
    super.key,
    required this.profile,
    required this.choices,
  });
  @override
  State<AdminFallbackPage> createState() => _AdminFallbackPageState();
}

class _AdminFallbackPageState extends State<AdminFallbackPage> {
  List<Map<String, dynamic>>? _rows;
  Object? _loadedValue;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cfg = await widget.profile.config();
      final value = cfg['fallback_providers'] ?? [];
      // Stock Hermes accepts one entry as a map as well as an ordered list.
      // Keep the wire value separately for the pre-save conflict check.
      final rows = administrationRows(value is Map ? [value] : value);
      if (mounted) {
        setState(() {
          _rows = rows;
          _loadedValue = value;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = administrationError(e));
    }
  }

  Future<void> _save(List<Map<String, dynamic>> next) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final latest = await widget.profile.config();
      if (!sameSetting(latest['fallback_providers'] ?? [], _loadedValue)) {
        throw const AdministrationFailure(
          'Fallback models changed elsewhere. Refresh before applying this change.',
        );
      }
      await widget.profile.saveSettings({'fallback_providers': next});
      if (mounted) {
        setState(() {
          _rows = next;
          _loadedValue = next;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Fallback models',
    scope: widget.profile.label,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const AdminNotice(
          'Hermes tries these models in order. Changes are saved individually.',
        ),
        if (_error != null) AdminNotice.error(_error!, retry: _load),
        if (_rows == null && _error == null) const LinearProgressIndicator(),
        if (_rows != null) ...[
          for (final entry in _rows!.indexed)
            ListTile(
              title: Text('${entry.$2['model'] ?? ''}'),
              subtitle: Text('${entry.$2['provider'] ?? ''}'),
              trailing: PopupMenuButton<String>(
                tooltip: 'Manage fallback ${entry.$1 + 1}',
                enabled: !_busy,
                itemBuilder: (_) => [
                  if (entry.$1 > 0)
                    const PopupMenuItem(value: 'up', child: Text('Move up')),
                  if (entry.$1 < _rows!.length - 1)
                    const PopupMenuItem(
                      value: 'down',
                      child: Text('Move down'),
                    ),
                  const PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
                onSelected: (action) {
                  final next = [..._rows!];
                  final row = next.removeAt(entry.$1);
                  if (action != 'remove') {
                    next.insert(entry.$1 + (action == 'up' ? -1 : 1), row);
                  }
                  _save(next);
                },
              ),
            ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final choice = await chooseAdminModel(
                      context,
                      widget.choices,
                    );
                    if (choice != null && mounted) {
                      await _save([
                        ..._rows!,
                        {'provider': choice.provider, 'model': choice.model},
                      ]);
                    }
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add fallback'),
          ),
        ],
      ],
    ),
  );
}
