import '../../services/administration_health.dart';
import '../../services/doctor_diagnostic.dart';
import '../../services/profile_workspace_controller.dart';
import '../../services/security_audit_report.dart';
import '../../theme/wing_theme.dart';
import '../../widgets/studio_select.dart';
import '../../widgets/studio_error.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../services/workspace_connection_failure.dart';
import 'admin_widgets.dart';
import 'admin_doctor_diagnosis.dart';
import 'admin_security_diagnosis.dart';

class AdminActionPage extends StatefulWidget {
  final Future<void> Function()? onRunAgain;
  final AdministrationRepository server;
  final AdministrationAction action;
  final String title;
  final String scope;
  final ValueChanged<AdminDiagnosticObservation>? onObservation;
  final AdminDiagnosticObservation? initialObservation;
  final ProfileWorkspaceController? chatController;
  final Future<void> Function(ProfileSessionKey)? onOpenSession;
  const AdminActionPage({
    super.key,
    required this.server,
    required this.action,
    required this.title,
    required this.scope,
    this.onObservation,
    this.initialObservation,
    this.onRunAgain,
    this.chatController,
    this.onOpenSession,
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
  int? _openingFinding;
  ProfileChat? _preparedChat;
  String? _preparedPrompt;

  void _chatNotice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _askHermes(int index, DoctorFinding finding) async {
    if (_openingFinding != null) return;
    final controller = widget.chatController;
    final owner = controller?.current?.scope;
    if (controller == null || widget.onOpenSession == null || owner == null) {
      return;
    }
    setState(() {
      _openingFinding = index;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      if (owner.connectionId != widget.server.connectionId ||
          owner.connectionIdentity != widget.server.connectionIdentity) {
        throw const AdministrationFailure(
          'Connection changed. Open Doctor on the selected connection.',
        );
      }
      final prompt = finding.chatPrompt(
        (_status?['lines'] as List? ?? []).join('\n'),
      );
      // A navigation failure should retry opening the saved draft, not mint
      // another chat for the same finding.
      final chat =
          _preparedChat?.key.workspace == owner && _preparedPrompt == prompt
          ? _preparedChat!
          : await controller.createDraftChat(owner: owner, text: prompt);
      _preparedChat = chat;
      _preparedPrompt = prompt;
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      if (controller.switching || controller.current?.scope != owner) {
        _chatNotice('Draft saved in ${owner.profileName}. Open it from Chats.');
        return;
      }
      await widget.onOpenSession!(chat.key);
      _preparedChat = null;
      _preparedPrompt = null;
    } catch (error) {
      if (mounted) {
        _chatNotice(
          error is AdministrationFailure
              ? error.message
              : 'Could not open the chat. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _openingFinding = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _status = widget.initialObservation?.status;
    _checkedAt = widget.initialObservation?.checkedAt;
    if (_status == null ||
        _status?['running'] != false ||
        _status?['exit_code'] is! int) {
      _check();
    }
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
        if (isTemporaryWorkspaceFailure(e)) {
          _timer = Timer(const Duration(seconds: 15), _check);
        }
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
    final isAudit = widget.action.name == 'security-audit';
    final isDiagnostic = isAudit || widget.action.name == 'doctor';
    final audit = isAudit && _status != null
        ? SecurityAuditReport.fromStatus(_status!)
        : null;
    final diagnosis =
        widget.action.name == 'doctor' && _status?['running'] == false
        ? DoctorDiagnostic.fromLines(_status?['lines'] as List? ?? [])
        : null;
    final hasSummary = diagnosis != null || audit != null;
    return AdminPage(
      title: widget.title,
      scope: widget.scope,
      actions: [
        if (isDiagnostic)
          IconButton(
            tooltip: 'Run ${widget.title} again',
            onPressed:
                !_loading &&
                    _openingFinding == null &&
                    _status?['running'] == false &&
                    _status?['exit_code'] is int
                ? widget.onRunAgain
                : null,
            icon: const Icon(Icons.play_arrow),
          )
        else
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
              _status!['exit_code'] != 0 &&
              !(isAudit && _status!['exit_code'] == 1))
            const StudioError('Failed')
          else if (!hasSummary)
            Text(
              _status == null
                  ? 'Checking operation…'
                  : _status!['running'] == true
                  ? 'Running'
                  : isAudit
                  ? 'Audit summary unavailable'
                  : _status!['exit_code'] == 0
                  ? 'Completed'
                  : _status!['exit_code'] == null
                  ? 'Outcome unavailable'
                  : 'Failed',
            ),
          if (!hasSummary &&
              _status?['running'] == false &&
              _status?['exit_code'] == 0) ...[
            const SizedBox(height: 8),
            Text(
              'Review the findings below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_checkedAt != null && !hasSummary) ...[
            const SizedBox(height: 8),
            Text(
              'Checked ${TimeOfDay.fromDateTime(_checkedAt!).format(context)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (diagnosis != null) ...[
            ListenableBuilder(
              listenable:
                  widget.chatController ?? const AlwaysStoppedAnimation(false),
              builder: (context, _) => AdminDoctorDiagnosis(
                diagnosis: diagnosis,
                checkedAt: _checkedAt,
                openingFinding: _openingFinding,
                onAskHermes:
                    widget.chatController?.current == null ||
                        widget.chatController!.switching ||
                        widget.onOpenSession == null
                    ? null
                    : (index) => _askHermes(index, diagnosis.findings[index]),
              ),
            ),
            const SizedBox(height: WingSpacing.lg),
          ],
          if (audit != null) ...[
            AdminSecurityDiagnosis(report: audit, checkedAt: _checkedAt),
            const SizedBox(height: WingSpacing.lg),
          ],
          const SizedBox(height: 12),
          AdminGroup(
            children: [
              ExpansionTile(
                key: ValueKey(hasSummary),
                shape: const Border(),
                collapsedShape: const Border(),
                initiallyExpanded: !hasSummary && !isAudit,
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
          if (!isDiagnostic &&
              widget.onRunAgain != null &&
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
  String title, {
  bool confirm = true,
  bool Function()? isActive,
  VoidCallback? onStarting,
}) async {
  if (confirm) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text('Run this diagnostic on ${server.connectionLabel}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return null;
  }
  try {
    onStarting?.call();
    final result = await server.startDiagnostic(
      path,
      isActive: isActive ?? () => context.mounted,
    );
    return AdministrationAction.fromJson(result);
  } catch (e) {
    if (context.mounted) {
      final detail = e is AdministrationFailure
          ? e.message
          : 'Could not confirm the diagnostic started. Check the connection.';
      adminMessage(context, '$title: $detail', isError: true);
    }
  }
  return null;
}

class AdminLogsPage extends StatefulWidget {
  final AdministrationRepository server;
  const AdminLogsPage({super.key, required this.server});
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
