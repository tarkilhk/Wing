import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/usage_cost.dart';

String _usageNumber(BuildContext context, Object? value) {
  final count = usageTokenCount(value);
  return count == null
      ? 'Unavailable'
      : MaterialLocalizations.of(context).formatDecimal(count);
}

String _usageRate(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

class _UsageValue extends StatelessWidget {
  final String label;
  final String value;
  const _UsageValue({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: 12,
    runSpacing: 4,
    children: [Text(label), Text(value)],
  );
}

class UsageModelDetails extends StatelessWidget {
  final ModelUsageCost model;
  final double? total;
  final PageStorageKey<String> storageKey;
  const UsageModelDetails({
    super.key,
    required this.model,
    required this.total,
    required this.storageKey,
  });

  String get _costLabel => switch (model.unavailable) {
    UsageCostUnavailable.price => 'Price unavailable',
    UsageCostUnavailable.tokens => 'Token counts unavailable',
    _ => formatUsageUsd(model.amount),
  };

  @override
  Widget build(BuildContext context) {
    final usage = model.usage;
    final amount = model.amount;
    final totalAmount = total;
    return ExpansionTile(
      key: storageKey,
      initiallyExpanded: true,
      title: Text(
        model.model,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${usage['provider'] ?? 'Provider unavailable'}${model.isApiEquivalent ? ' · API equivalent' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${_usageNumber(context, usage['api_calls'])} calls · $_costLabel',
            ),
            if (amount != null && totalAmount != null && totalAmount > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (amount / totalAmount).clamp(0, 1),
                semanticsLabel: '${model.model} share of displayed estimates',
                semanticsValue:
                    '${(amount / totalAmount * 100).toStringAsFixed(1)}%',
              ),
            ],
          ],
        ),
      ),
      children: [
        for (final (key, label) in [
          ('sessions', 'Sessions'),
          ('api_calls', 'Calls'),
        ])
          ListTile(
            dense: true,
            title: Text(label),
            subtitle: Text(_usageNumber(context, usage[key])),
          ),
        if (model.isApiEquivalent)
          _SubscriptionCostDetails(model: model)
        else
          for (final (key, label) in [
            ('input_tokens', 'Input tokens'),
            ('cache_read_tokens', 'Cached input'),
            ('output_tokens', 'Output tokens'),
            ('estimated_cost', 'Estimated cost'),
          ])
            ListTile(
              dense: true,
              title: Text(label),
              subtitle: Text(
                key == 'estimated_cost'
                    ? _costLabel
                    : _usageNumber(context, usage[key]),
              ),
            ),
      ],
    );
  }
}

class _SubscriptionCostDetails extends StatefulWidget {
  final ModelUsageCost model;
  const _SubscriptionCostDetails({required this.model});
  @override
  State<_SubscriptionCostDetails> createState() =>
      _SubscriptionCostDetailsState();
}

class _SubscriptionCostDetailsState extends State<_SubscriptionCostDetails> {
  bool _sourceFailed = false;

  Future<void> _openSource() async {
    var opened = false;
    try {
      opened = await launchUrl(
        widget.model.price!.source,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Keep the source visible for copying when no browser can handle it.
    }
    if (mounted) setState(() => _sourceFailed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final price = model.price;
    final locale = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, label, rate, cost) in [
            ('input_tokens', 'Uncached input', price?.input, model.inputCost),
            (
              'cache_read_tokens',
              'Cached input',
              price?.cachedInput,
              model.cachedInputCost,
            ),
            ('output_tokens', 'Output', price?.output, model.outputCost),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _UsageValue(label: label, value: formatUsageUsd(cost)),
                  const SizedBox(height: 4),
                  Text(
                    '${_usageNumber(context, model.usage[key])} tokens${rate == null ? '' : ' · USD ${_usageRate(rate)} / 1M tokens'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (model.unavailable == UsageCostUnavailable.price)
            const Text('No verified API price for this model.')
          else if (model.unavailable == UsageCostUnavailable.tokens)
            const Text(
              'All three token counts are needed to estimate this model.',
            ),
          if (price != null) ...[
            const SizedBox(height: 8),
            Text(
              'Prices checked ${locale.formatShortDate(price.verifiedOn)}. Applied to the selected history.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openSource,
                child: const Text('OpenAI pricing source'),
              ),
            ),
            if (_sourceFailed) ...[
              const Text('Could not open the browser. Copy this pricing link:'),
              SelectionArea(child: Text(price.source.toString())),
            ],
          ],
        ],
      ),
    );
  }
}
