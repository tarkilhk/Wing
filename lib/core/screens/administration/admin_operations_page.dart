import '../../theme/wing_theme.dart';
import '../../widgets/studio_select.dart';
import '../../widgets/studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import 'admin_widgets.dart';

class AdminActionPage extends StatefulWidget {
  final AdministrationRepository server;
  final AdministrationAction action;
  final String title;
  final String scope;
  const AdminActionPage({
    super.key,
    required this.server,
    required this.action,
    required this.title,
    required this.scope,
  });
  @override
  State<AdminActionPage> createState() => _AdminActionPageState();
}

class _AdminActionPageState extends State<AdminActionPage> {
  Map<String, dynamic>? _status;
  String? _error;
  Timer? _timer;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.action.status(widget.server);
      if (!mounted) return;
      setState(() => _status = status);
      if (status['running'] == true) {
        _timer = Timer(const Duration(seconds: 3), _check);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = administrationError(e, writing: true));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: widget.title,
    scope: widget.scope,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) AdminNotice.error(_error!),
        if (_status?['running'] != true &&
            _status?['exit_code'] != null &&
            _status!['exit_code'] != 0)
          const StudioError('Failed')
        else
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
        const SizedBox(height: 16),
        const Text(
          'This result describes the diagnostic operation. Review its output for findings.',
        ),
        ExpansionTile(
          title: const Text('Diagnostic output'),
          children: [
            SelectableText(
              (_status?['lines'] as List? ?? []).join('\n'),
              style: WingTokens.of(context).typography.mono,
            ),
          ],
        ),
        TextButton(
          onPressed: _loading ? null : _check,
          child: const Text('Check progress'),
        ),
      ],
    ),
  );
}

Future<void> startAdminOperation(
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
    return;
  }
  try {
    final result = await server.write('POST', path);
    final action = AdministrationAction.fromJson(result);
    if (context.mounted) {
      await adminPush(
        context,
        AdminActionPage(
          server: server,
          action: action,
          title: title,
          scope: scope,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      adminMessage(
        context,
        administrationError(e, writing: true),
        isError: true,
      );
    }
  }
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
    scope: '${widget.server.connectionLabel} / ${widget.runtimeLabel}',
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
                  final width = scaledWidth < 480
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
                  labelText: 'Search logs',
                  helperMaxLines: 4,
                  helperText: 'Last 100 matching lines. Submit to search.',
                ),
                onSubmitted: (v) => setState(() {
                  _search = v;
                  _version++;
                }),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
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
                TextButton(onPressed: refresh, child: const Text('Refresh')),
                SelectableText(
                  (data['lines'] as List? ?? data['logs'] as List? ?? []).join(
                    '\n',
                  ),
                  style: WingTokens.of(context).typography.mono,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
