import 'package:flutter/material.dart';

import '../../services/doctor_diagnostic.dart';
import '../../theme/wing_theme.dart';
import 'admin_widgets.dart';

/// Findings are the main content; process completion is secondary metadata.
class AdminDoctorDiagnosis extends StatelessWidget {
  const AdminDoctorDiagnosis({
    super.key,
    required this.diagnosis,
    required this.checkedAt,
  });

  final DoctorDiagnostic diagnosis;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = WingTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: WingSpacing.xs),
              child: Icon(
                diagnosis.hasIssues
                    ? Icons.error_outline
                    : Icons.health_and_safety_outlined,
                size: 24,
                color: diagnosis.hasIssues ? tokens.warning : tokens.success,
              ),
            ),
            const SizedBox(width: WingSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      diagnosis.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (checkedAt != null) ...[
                    const SizedBox(height: WingSpacing.xs),
                    Text(
                      'Checked ${TimeOfDay.fromDateTime(checkedAt!).format(context)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: WingSpacing.xl),
        if (diagnosis.hasIssues)
          AdminGroup(
            children: [
              for (final finding in diagnosis.findings)
                Padding(
                  padding: const EdgeInsets.all(WingSpacing.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          finding.title,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (finding.detail != null) ...[
                          const SizedBox(height: WingSpacing.sm),
                          SelectableText(
                            finding.detail!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tokens.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          )
        else
          Text('All Doctor checks passed.', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
