import 'administration_health.dart';
import 'administration_overview.dart';

DateTime? healthSnapshotTime(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

bool healthSnapshotExpired(DateTime? at, DateTime now) =>
    at == null ||
    now.isBefore(at) ||
    now.difference(at) >= const Duration(hours: 24);

Map<String, dynamic> healthFindingSnapshot(AdministrationHealthFinding value) =>
    {
      'title': value.title,
      'detail': value.detail,
      'status': value.status.name,
      'destination': value.destination,
      'checkedAt': value.checkedAt?.toUtc().toIso8601String(),
    };

AdministrationHealthFinding? restoreHealthFinding(Object? data) {
  if (data == null) return null;
  final value = data as Map;
  return AdministrationHealthFinding(
    title: value['title'] as String,
    detail: value['detail'] as String,
    status: AdministrationHealthStatus.values.byName(value['status'] as String),
    destination: value['destination'] as String?,
    checkedAt: healthSnapshotTime(value['checkedAt']),
  );
}

Map<String, dynamic> healthObservationSnapshot(
  AdministrationObservation value,
) => {
  'data': value.data,
  'checkedAt': value.checkedAt?.toUtc().toIso8601String(),
  'error': value.error,
};

void restoreHealthObservation(AdministrationObservation target, Map value) {
  target.data = value['data'] == null
      ? null
      : Map<String, dynamic>.from(value['data'] as Map);
  target.checkedAt = healthSnapshotTime(value['checkedAt']);
  target.error = value['error'] as String?;
}
