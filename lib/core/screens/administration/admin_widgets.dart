import 'dart:async';
import '../../widgets/server_connection_label.dart';
import 'package:flutter/material.dart';

import '../../services/administration_repository.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/studio_action_label.dart';

/// Inherit all Studio component states and the selected app accent.
ThemeData administrationTheme(ThemeData base) => base;

class AdminPage extends StatelessWidget {
  final String title;
  final String scope;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;
  const AdminPage({
    super.key,
    required this.title,
    required this.scope,
    required this.child,
    this.actions = const [],
    this.bottomNavigationBar,
  });
  @override
  Widget build(BuildContext context) => Theme(
    data: administrationTheme(Theme.of(context)),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: adminToolbarHeight(
            context,
            title,
            actions: actions.length,
          ),
          title: Text(title, maxLines: 6, softWrap: true),
          actions: actions,
        ),
        bottomNavigationBar: bottomNavigationBar == null
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: bottomNavigationBar,
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ServerConnectionScope.of(context) == null
                  ? Text(scope, style: Theme.of(context).textTheme.bodySmall)
                  : ServerConnectionLabel(
                      label: scope,
                      status: ServerConnectionScope.of(context),
                    ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

/// Let long page titles grow at large text sizes instead of silently truncating.
double adminToolbarHeight(
  BuildContext context,
  String title, {
  int actions = 0,
}) {
  final theme = Theme.of(context);
  final painter =
      TextPainter(
        text: TextSpan(
          text: title,
          style: theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 6,
      )..layout(
        maxWidth: (MediaQuery.sizeOf(context).width - 88 - actions * 48).clamp(
          80,
          double.infinity,
        ),
      );
  final height = (painter.height + 16).clamp(kToolbarHeight, double.infinity);
  painter.dispose();
  return height;
}

class AdminGroup extends StatelessWidget {
  final List<Widget> children;
  const AdminGroup({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          children[i],
        ],
      ],
    ),
  );
}

class AdminSectionLabel extends StatelessWidget {
  const AdminSectionLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class AdminEditorActions extends StatelessWidget {
  const AdminEditorActions({
    super.key,
    required this.dirtyCount,
    required this.saving,
    required this.onClose,
    required this.onSave,
  });
  final int dirtyCount;
  final bool saving;
  final VoidCallback onClose;
  final VoidCallback? onSave;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            dirtyCount == 0
                ? 'No unsaved changes'
                : '$dirtyCount unsaved ${dirtyCount == 1 ? 'change' : 'changes'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: saving ? null : onClose,
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: saving ? null : onSave,
                  child: StudioActionLabel('Save', busy: saving),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AdminRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool emphasizeChanges;
  final IconData icon;
  final VoidCallback? onTap;
  const AdminRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.emphasizeChanges = false,
    required this.icon,
    this.onTap,
  });
  @override
  State<AdminRow> createState() => _AdminRowState();
}

class _AdminRowState extends State<AdminRow> {
  Timer? _timer;
  bool _changed = false;
  @override
  void didUpdateWidget(AdminRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.emphasizeChanges &&
        oldWidget.subtitle != widget.subtitle &&
        !oldWidget.subtitle.toLowerCase().contains('loading') &&
        !oldWidget.subtitle.contains('Schedules unavailable') &&
        !MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _changed = true;
      _timer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _changed = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    color: _changed
        ? Theme.of(context).colorScheme.primaryContainer
        : Colors.transparent,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minTileHeight: 64,
      minVerticalPadding: 8,
      leading: Icon(widget.icon, size: 22),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        widget.subtitle,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: widget.onTap == null
          ? null
          : const Icon(Icons.chevron_right, size: 20),
      onTap: widget.onTap,
    ),
  );
}

class AdminNotice extends StatelessWidget {
  final String text;
  final VoidCallback? retry;
  final bool isError;
  const AdminNotice(this.text, {super.key, this.retry, this.isError = false});
  const AdminNotice.error(this.text, {super.key, this.retry}) : isError = true;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isError)
          StudioError(text)
        else
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        if (retry != null)
          TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}

/// Retains the last observation on refresh failure and never renders failure as empty.
class AdminLoad extends StatefulWidget {
  final bool expand;
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback)
  builder;
  const AdminLoad({
    super.key,
    required this.load,
    required this.builder,
    this.expand = true,
  });
  @override
  State<AdminLoad> createState() => _AdminLoadState();
}

class _AdminLoadState extends State<AdminLoad> {
  Map<String, dynamic>? _data;
  DateTime? _checkedAt;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load();
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
          _checkedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = administrationError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        if (widget.expand)
          Flexible(child: SingleChildScrollView(child: _failure(context)))
        else
          _failure(context),
      if (_data != null)
        if (widget.expand)
          Expanded(child: _content(context))
        else
          _content(context),
    ],
  );

  Widget _failure(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: AdminNotice.error(
      '${_data == null ? '' : 'Last checked ${TimeOfDay.fromDateTime(_checkedAt!).format(context)}. '}$_error',
      retry: _loading ? null : _load,
    ),
  );

  Widget _content(BuildContext context) {
    try {
      return widget.builder(context, _data!, _load);
    } on FormatException {
      return AdminNotice.error(
        'The server returned an invalid response.',
        retry: _load,
      );
    } on TypeError {
      return AdminNotice.error(
        'The server returned an incomplete response.',
        retry: _load,
      );
    }
  }
}

/// Bring a failed/partial save into view without moving focus into an input.
void revealAdminNotice(BuildContext context, GlobalKey anchor) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = anchor.currentContext;
    if (!context.mounted || target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
    );
  });
}

Future<bool> adminConfirm(
  BuildContext context,
  String title,
  String detail, {
  String action = 'Continue',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> adminPush(BuildContext context, Widget page) {
  final status = ServerConnectionScope.of(context);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => status == null
          ? page
          : ServerConnectionScope(status: status, child: page),
    ),
  );
}

void adminMessage(
  BuildContext context,
  String message, {
  bool isError = false,
}) => ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: isError ? StudioError(message) : Text(message)),
);
