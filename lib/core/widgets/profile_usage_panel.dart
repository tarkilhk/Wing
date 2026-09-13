import 'package:flutter/material.dart';
import 'anchored_expansion_tile.dart';

import '../services/profile_gateway.dart';

/// Small, server-backed usage view for one captured profile connection.
/// Values are displayed as returned by Hermes; the phone does not estimate cost.
class ProfileUsagePanel extends StatefulWidget {
  final ProfileGateway capturedProfileGateway;
  final String? connectionLabel;

  const ProfileUsagePanel({
    super.key,
    required this.capturedProfileGateway,
    this.connectionLabel,
  });

  @override
  State<ProfileUsagePanel> createState() => _ProfileUsagePanelState();
}

class _ProfileUsagePanelState extends State<ProfileUsagePanel> {
  Map<String, dynamic>? _usage;
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void didUpdateWidget(ProfileUsagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.capturedProfileGateway,
      widget.capturedProfileGateway,
    )) {
      _request++;
      _loading = false;
      _usage = null;
      _error = null;
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.capturedProfileGateway.read(
        'analytics/usage',
        {'days': '30'},
      );
      final totals = response['totals'];
      if (response['period_days'] != 30 || !_UsageDetails.isStringMap(totals)) {
        throw const FormatException('Invalid analytics usage response');
      }
      if (!mounted || request != _request) {
        return;
      }
      setState(() => _usage = response);
    } catch (error) {
      if (!mounted || request != _request) {
        return;
      }
      setState(() => _error = error);
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.connectionLabel == null
        ? 'Session usage · last 30 days'
        : 'Session usage · last 30 days · ${widget.connectionLabel}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh usage',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              const Text('Usage could not be loaded.'),
              TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Retry'),
              ),
            ] else if (!_loading && _usage == null) ...[
              const Text('Load server-recorded usage for this profile.'),
            ],
            if (_usage case final usage?) _UsageDetails(data: usage),
            if (_usage == null && _error == null && !_loading)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.download),
                  label: const Text('Load usage'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UsageDetails extends StatelessWidget {
  final Map<String, dynamic> data;

  const _UsageDetails({required this.data});

  @override
  Widget build(BuildContext context) {
    final totals = _map(data['totals']);
    final rows = <Widget>[
      _Stat('Sessions', _value(totals['total_sessions'])),
      _Stat('API calls', _value(totals['total_api_calls'])),
      _Stat('Input tokens', _value(totals['total_input'])),
      _Stat('Output tokens', _value(totals['total_output'])),
      _Stat('Estimated cost', _money(totals['total_estimated_cost'])),
      _Stat(
        'Reported cost (where available)',
        _money(totals['total_actual_cost']),
      ),
    ];
    final models = data['by_model'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        const Text('Unreported costs are not included.'),
        if (models is List && models.whereType<Map>().isNotEmpty)
          AnchoredExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Models (includes auxiliary calls)'),
            children: [
              for (final raw in models.take(100))
                if (raw is Map && raw.keys.every((key) => key is String)) ...[
                  _ModelRow(data: Map<String, dynamic>.from(raw)),
                ],
            ],
          ),
      ],
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map && value.keys.every((key) => key is String)
      ? Map<String, dynamic>.from(value)
      : const {};

  static bool isStringMap(Object? value) =>
      value is Map && value.keys.every((key) => key is String);

  static String _value(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.round()) {
      return 'Unknown';
    }
    return _groupWhole(value.round().toString());
  }

  static String _money(Object? value) {
    if (value is! num || !value.isFinite || value < 0) {
      return 'Unknown';
    }
    final fixed = value.toStringAsFixed(2);
    final decimal = fixed.indexOf('.');
    if (decimal < 0) {
      return '\$$fixed';
    }
    return '\$${_groupWhole(fixed.substring(0, decimal))}${fixed.substring(decimal)}';
  }

  static String _groupWhole(String digits) {
    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(digits[index]);
    }
    return grouped.toString();
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Wrap(
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _ModelRow extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ModelRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final model = data['model'];
    if (model is! String || model.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(model),
      subtitle: Text(
        'Tokens: ${_UsageDetails._value(data['input_tokens'])} in / '
        '${_UsageDetails._value(data['output_tokens'])} out · '
        'Estimated: ${_UsageDetails._money(data['estimated_cost'])}',
      ),
    );
  }
}
