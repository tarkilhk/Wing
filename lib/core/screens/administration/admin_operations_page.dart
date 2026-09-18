import '../../services/administration_health.dart';
import '../../services/doctor_diagnostic.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/studio_select.dart';
import '../../widgets/studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';
import 'admin_doctor_diagnosis.dart';

class AdminActionPage extends StatefulWidget {
  final Future<void> Function()? onRunAgain;
  final AdministrationRepository server;
  final AdministrationAction action;
  final String title;
  final String scope;
  final ValueChanged<AdminDiagnosticObservation>? onObservation;
  final AdminDiagnosticObservation? initialObservation;
  const AdminActionPage({
    super.key,
    required this.server,
    required this.action,
    required this.title,
    required this.scope,
    this.onObservation,
    this.initialObservation,
    this.onRunAgain,
  });
  @override
  State<AdminActionPage> createState() => _AdminActionPageState();
}

class _AdminActionPageState extends State<AdminActionPage> {
  Map<String, dynamic>? _status;
  String? _error;
  Timer? _timer;
  bool _loading = false;
  DateTime? _checkedAt;
  @override
  void initState() {
    super.initState();
    _status = widget.initialObservation?.status;
    _checkedAt = widget.initialObservation?.checkedAt;
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_loading) return;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.action.status(widget.server);
      if (!mounted) return;
      setState(() {
        _status = status;
        _checkedAt = DateTime.now();
      });
      if (status['running'] == true) {
        _timer = Timer(const Duration(seconds: 3), _check);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        widget.onObservation?.call(
          AdminDiagnosticObservation(
            widget.action,
            _status ?? const {},
            _checkedAt,
            readError: _error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis =
        widget.action.name == 'doctor' && _status?['running'] == false
        ? DoctorDiagnostic.fromLines(_status?['lines'] as List? ?? [])
        : null;
    return AdminPage(
      title: widget.title,
      scope: widget.scope,
      actions: [
        IconButton(
          tooltip: 'Refresh result',
          onPressed: _loading ? null : _check,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) AdminNotice.error(_error!),
          if (_status?['running'] != true &&
              _status?['exit_code'] != null &&
              _status!['exit_code'] != 0)
            const StudioError('Failed')
          else if (diagnosis == null)
            Text(
              _status == null
                  ? 'Checking operation…'
                  : _status!['running'] == true
                  ? 'Running'
                  : _status!['exit_code'] == 0
                  ? 'Completed'
                  : _status!['exit_code'] == null
                  ? 'Outcome unavailable'
                  : 'Failed',
            ),
          if (diagnosis == null &&
              _status?['running'] == false &&
              _status?['exit_code'] == 0) ...[
            const SizedBox(height: 8),
            Text(
              'Review the findings below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_checkedAt != null && diagnosis == null) ...[
            const SizedBox(height: 8),
            Text(
              'Checked ${TimeOfDay.fromDateTime(_checkedAt!).format(context)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (diagnosis != null) ...[
            AdminDoctorDiagnosis(diagnosis: diagnosis, checkedAt: _checkedAt),
            const SizedBox(height: WingSpacing.lg),
          ],
          const SizedBox(height: 12),
          AdminGroup(
            children: [
              ExpansionTile(
                key: ValueKey(diagnosis != null),
                shape: const Border(),
                collapsedShape: const Border(),
                initiallyExpanded: diagnosis == null,
                title: const Text('Diagnostic output'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      (_status?['lines'] as List? ?? []).isEmpty
                          ? 'No output yet.'
                          : (_status!['lines'] as List).join('\n'),
                      style: WingTokens.of(context).typography.mono,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (widget.onRunAgain != null &&
              _status?['running'] == false &&
              _status?['exit_code'] is int) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onRunAgain,
              icon: const Icon(Icons.play_arrow),
              label: Text('Run ${widget.title} again'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<AdministrationAction?> startAdminOperation(
  BuildContext context,
  AdministrationRepository server,
  String path,
  String title,
  String scope,
) async {
  if (!await adminConfirm(
    context,
    title,
    'Run this diagnostic on $scope? The result may include backend log details.',
    action: 'Run',
  )) {
    return null;
  }
  try {
    final result = await server.write('POST', path);
    return AdministrationAction.fromJson(result);
  } catch (e) {
    if (context.mounted) {
      adminMessage(
        context,
        administrationError(e, writing: true),
        isError: true,
      );
    }
  }
  return null;
}

class AdminLogsPage extends StatefulWidget {
  final AdministrationRepository server;
  final String runtimeLabel;
  const AdminLogsPage({
    super.key,
    required this.server,
    required this.runtimeLabel,
  });
  @override
  State<AdminLogsPage> createState() => _AdminLogsPageState();
}

class _AdminLogsPageState extends State<AdminLogsPage> {
  String _file = 'agent';
  String _level = '';
  String _search = '';
  int _version = 0;
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Logs',
    scope: widget.server.connectionLabel,
    actions: [
      IconButton(
        tooltip: 'Refresh logs',
        onPressed: () => setState(() => _version++),
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final scaledWidth =
                      constraints.maxWidth /
                      (MediaQuery.textScalerOf(context).scale(16) / 16);
                  final width = scaledWidth < 340
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: width,
                        child: StudioSelect<String>(
                          value: _file,
                          label: 'Log',
                          options: [
                            for (final v in ['agent', 'errors', 'gateway'])
                              (value: v, label: v),
                          ],
                          onChanged: (v) => setState(() {
                            _file = v!;
                            _version++;
                          }),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: StudioSelect<String>(
                          value: _level,
                          label: 'Severity',
                          options: [
                            for (final v in [
                              '',
                              'DEBUG',
                              'INFO',
                              'WARNING',
                              'ERROR',
                            ])
                              (value: v, label: v.isEmpty ? 'All' : v),
                          ],
                          onChanged: (v) => setState(() {
                            _level = v!;
                            _version++;
                          }),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search logs',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => setState(() {
                  _search = v;
                  _version++;
                }),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: AdminLoad(
            expand: false,
            key: ValueKey(_version),
            load: () => widget.server.read('logs', {
              'file': _file,
              'lines': '100',
              if (_level.isNotEmpty) 'level': _level,
              if (_search.isNotEmpty) 'search': _search,
            }),
            builder: (context, data, refresh) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Latest ${(data['lines'] as List? ?? []).length} matching lines · Up to 100',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                AdminGroup(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          (data['lines'] as List? ?? []).isEmpty
                              ? 'No matching log entries.'
                              : (data['lines'] as List).join('\n'),
                          style: WingTokens.of(context).typography.mono,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
