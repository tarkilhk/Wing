import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../widgets/chat_intelligence_picker.dart';
import '../../widgets/model_chooser.dart';
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
  final _pendingAux = <String, ModelSelection>{};
  Future<void> _aux(
    String task,
    List<ModelChoice> choices,
    VoidCallback refresh, {
    ModelSelection? initialSelection,
  }) async {
    final selection = task == '__reset__'
        ? const ModelSelection.special(ModelSpecialChoice.automatic)
        : await chooseAdminModel(
            context,
            choices,
            scopeLabel: 'Helper model for ${task.replaceAll('_', ' ')}',
            onRefresh: () async => ModelChoice.fromOptions(
              await _profile.read('model/options', {
                'explicit_only': '1',
                'refresh': '1',
              }),
            ),
            initialSelection: _pendingAux[task] ?? initialSelection,
            allowAuto: true,
            actionLabel: 'Set helper model',
          );
    if (selection == null || !mounted) return;
    if (task == '__reset__' &&
        !await adminConfirm(
          context,
          'Reset all helper models?',
          'All helper tasks will choose automatically. Their saved endpoint credentials will be cleared.',
          action: 'Reset all',
        )) {
      return;
    }
    await _saveAux(task, selection, refresh);
  }

  Future<void> _saveAux(
    String task,
    ModelSelection selection,
    VoidCallback refresh,
  ) async {
    final choice = selection.choice;
    final provider = selection.special == ModelSpecialChoice.automatic
        ? 'auto'
        : choice!.provider;
    final model = selection.special == ModelSpecialChoice.automatic
        ? ''
        : choice!.model;
    setState(() {
      _busy = true;
      _error = null;
      if (task != '__reset__') _pendingAux[task] = selection;
    });
    try {
      final body = {
        'scope': 'auxiliary',
        'task': task,
        'provider': provider,
        'model': model,
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
            (r) => r['provider'] != provider || r['model'] != model,
          )) {
        throw const AdministrationFailure(
          'Helper model save could not be confirmed.',
        );
      }
      refresh();
      if (mounted) {
        setState(() => _pendingAux.remove(task));
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

  String _auxSummary(Map<String, dynamic> task, List<ModelChoice> choices) {
    final pending = _pendingAux[task['task']];
    if (pending != null) {
      final choice = pending.choice;
      return choice == null
          ? 'Pending: Automatic'
          : 'Pending: ${choice.provider} / ${choice.model}';
    }
    if (task['provider'] == 'auto') return 'Automatic';
    final listed = choices.any(
      (choice) =>
          choice.provider == task['provider'] && choice.model == task['model'],
    );
    return '${task['provider']} / ${task['model']}${listed ? '' : ' · Not in the available model list'}';
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
        final choices = ModelChoice.fromOptions(options);
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
                            AdminProvidersPage(profile: profile),
                      );
                    } else {
                      await adminPushProfile(
                        context,
                        _profile,
                        (context, profile) => AdminProviderDetail(
                          profile: profile,
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
                    subtitle: Text(_auxSummary(task, choices)),
                    trailing: _pendingAux.containsKey(task['task'])
                        ? TextButton(
                            onPressed: _busy
                                ? null
                                : () => _saveAux(
                                    task['task'] as String,
                                    _pendingAux[task['task']]!,
                                    refresh,
                                  ),
                            child: const Text('Retry'),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () => _aux(
                            task['task'] as String,
                            choices,
                            refresh,
                            initialSelection: task['provider'] == 'auto'
                                ? const ModelSelection.special(
                                    ModelSpecialChoice.automatic,
                                  )
                                : ModelSelection.model(
                                    ModelChoice(
                                      provider: task['provider'] as String,
                                      model: task['model'] as String,
                                    ),
                                  ),
                          ),
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

Future<ModelSelection?> chooseAdminModel(
  BuildContext context,
  List<ModelChoice> choices, {
  required String scopeLabel,
  required Future<List<ModelChoice>> Function() onRefresh,
  ModelSelection? initialSelection,
  bool allowAuto = false,
  String actionLabel = 'Use model',
}) {
  ModelSelection? selected = initialSelection;
  return showModalBottomSheet<ModelSelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, update) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final height = (MediaQuery.sizeOf(context).height - keyboard - 24)
            .clamp(0.0, MediaQuery.sizeOf(context).height * .82);
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Choose model'),
                  trailing: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Expanded(
                  child: ModelChooser(
                    choices: choices,
                    selected: selected,
                    onSelected: (value) => update(() => selected = value),
                    onRefresh: onRefresh,
                    specialOptions: allowAuto
                        ? const [
                            ModelSpecialOption(
                              ModelSpecialChoice.automatic,
                              'Automatic',
                              description:
                                  'Hermes chooses for this helper task',
                            ),
                          ]
                        : const [],
                    scopeLabel: scopeLabel,
                    keyPrefix: 'admin-model',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed:
                            selected == null || selected == initialSelection
                            ? null
                            : () => Navigator.pop(sheetContext, selected),
                        child: Text(actionLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class AdminFallbackPage extends StatefulWidget {
  final ProfileAdministration profile;
  final List<ModelChoice> choices;
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
  List<Map<String, dynamic>>? _pendingRows;
  Object? _loadedValue;
  bool _busy = false;
  bool _conflict = false;
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
      // Match desktop FallbackModelsField normalization. Keep draft rows local;
      // only complete provider/model pairs are emitted when the user edits.
      final rows = value is List
          ? value.map<Map<String, dynamic>>((item) {
              if (item is Map) {
                return {
                  ...Map<String, dynamic>.from(item),
                  'provider': '${item['provider'] ?? ''}',
                  'model': '${item['model'] ?? ''}',
                };
              }
              if (item is String) {
                final slash = item.indexOf('/');
                return {
                  'provider': slash > 0 ? item.substring(0, slash) : '',
                  'model': slash > 0 ? item.substring(slash + 1) : item,
                };
              }
              return {'provider': '', 'model': ''};
            }).toList()
          : <Map<String, dynamic>>[];
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
    final complete = next
        .where(
          (row) =>
              (row['provider'] as String).isNotEmpty &&
              (row['model'] as String).isNotEmpty,
        )
        .toList();
    setState(() {
      _busy = true;
      _error = null;
      _pendingRows = next;
    });
    try {
      final latest = await widget.profile.config();
      if (!sameSetting(latest['fallback_providers'] ?? [], _loadedValue)) {
        _conflict = true;
        throw const AdministrationFailure(
          'Fallback models changed elsewhere. Review the current and pending lists before applying.',
        );
      }
      await widget.profile.saveSettings({'fallback_providers': complete});
      if (mounted) {
        setState(() {
          _rows = next;
          _loadedValue = complete;
          _pendingRows = null;
          _conflict = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  String _summary(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? 'None'
      : rows.map((row) => '${row['provider']} / ${row['model']}').join('\n');

  Future<void> _reviewPending() async {
    final pending = _pendingRows;
    if (pending == null || _busy) return;
    await _load();
    if (!mounted || _error != null || _rows == null) return;
    final accepted = await adminConfirm(
      context,
      'Review fallback changes',
      'Current list:\n${_summary(_rows!)}\n\n'
          'Your pending list:\n${_summary(pending)}',
      action: 'Apply pending list',
    );
    if (!mounted || !accepted) return;
    await _save(pending);
  }

  Future<List<ModelChoice>> _catalog({bool refresh = false}) async =>
      ModelChoice.fromOptions(
        await widget.profile.read('model/options', {
          'explicit_only': '1',
          if (refresh) 'refresh': '1',
        }),
      );

  Future<void> _pickFallback({int? index}) async {
    List<ModelChoice> choices;
    try {
      choices = await _catalog();
    } catch (e) {
      choices = widget.choices;
      if (mounted) {
        setState(
          () => _error =
              'Current model choices could not be loaded. Previous list shown.',
        );
      }
    }
    if (!mounted) return;
    final row = index == null ? null : _rows![index];
    final selected = await chooseAdminModel(
      context,
      choices,
      scopeLabel: 'Fallback model for ${widget.profile.name}',
      onRefresh: () => _catalog(refresh: true),
      initialSelection:
          row == null || row['provider'] == '' || row['model'] == ''
          ? null
          : ModelSelection.model(
              ModelChoice(
                provider: row['provider'] as String,
                model: row['model'] as String,
              ),
            ),
      actionLabel: index == null ? 'Add fallback' : 'Save fallback',
    );
    final choice = selected?.choice;
    if (choice == null || !mounted) return;
    final next = [..._rows!];
    final value = <String, dynamic>{
      ...?row,
      'provider': choice.provider,
      'model': choice.model,
    };
    if (index == null) {
      next.add(value);
    } else {
      next[index] = value;
    }
    await _save(next);
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
        if (_pendingRows != null)
          TextButton(
            onPressed: _busy
                ? null
                : _conflict
                ? _reviewPending
                : () => _save(_pendingRows!),
            child: Text(
              _conflict
                  ? 'Review pending fallback change'
                  : 'Retry pending fallback change',
            ),
          ),
        if (_rows == null && _error == null) const LinearProgressIndicator(),
        if (_rows != null) ...[
          if (_rows!.isEmpty)
            const AdminNotice('No fallback models configured.'),
          for (final entry in _rows!.indexed)
            ListTile(
              title: Text(
                entry.$2['model'] == ''
                    ? 'Choose model'
                    : entry.$2['model'] as String,
              ),
              subtitle: Text(
                entry.$2['provider'] == ''
                    ? 'Choose provider'
                    : entry.$2['provider'] as String,
              ),
              onTap: _busy ? null : () => _pickFallback(index: entry.$1),
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
            onPressed: _busy ? null : () => _pickFallback(),
            icon: const Icon(Icons.add),
            label: const Text('Add fallback'),
          ),
        ],
      ],
    ),
  );
}
