import 'package:flutter/material.dart';

import '../../services/administration_repository.dart';

/// Inherit all Studio component states and the selected app accent.
ThemeData administrationTheme(ThemeData base) => base;

class AdminPage extends StatelessWidget {
  final String title;
  final String scope;
  final Widget child;
  final List<Widget> actions;
  const AdminPage({
    super.key,
    required this.title,
    required this.scope,
    required this.child,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => Theme(
    data: administrationTheme(Theme.of(context)),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(scope, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
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

class AdminRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const AdminRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    leading: Icon(icon, size: 22),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

class AdminNotice extends StatelessWidget {
  final String text;
  final VoidCallback? retry;
  const AdminNotice(this.text, {super.key, this.retry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminNotice(
            '${_data == null ? '' : 'Last checked ${TimeOfDay.fromDateTime(_checkedAt!).format(context)}. '}$_error',
            retry: _loading ? null : _load,
          ),
        ),
      if (_data != null)
        if (widget.expand)
          Expanded(child: _content(context))
        else
          _content(context),
    ],
  );

  Widget _content(BuildContext context) {
    try {
      return widget.builder(context, _data!, _load);
    } on FormatException {
      return AdminNotice(
        'The server returned an invalid response.',
        retry: _load,
      );
    } on TypeError {
      return AdminNotice(
        'The server returned an incomplete response.',
        retry: _load,
      );
    }
  }
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

Future<void> adminPush(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

void adminMessage(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
