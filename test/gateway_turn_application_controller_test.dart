import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/connection.dart';
import 'package:wing/core/services/gateway_turn_application_controller.dart';
import 'package:wing/core/services/gateway_turn_coordinator.dart';
import 'package:wing/core/services/gateway_turn_recovery.dart';

void main() {
  test('retains one session across screen remounts until app close', () async {
    final created = <_FakeApplicationSession>[];
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) {
        final session = _FakeApplicationSession();
        created.add(session);
        return session;
      },
    );
    final connection = _connection();

    final firstScreenLease = controller.sessionFor(connection);
    final remountedScreenLease = controller.sessionFor(_connection());

    expect(identical(firstScreenLease, remountedScreenLease), isTrue);
    expect(controller.retainedSessionCount, 1);
    expect(created, hasLength(1));
    expect(created.single.closeCount, 0);

    await controller.close();
    await controller.close();
    expect(created.single.closeCount, 1);
    expect(controller.retainedSessionCount, 0);
    expect(() => controller.sessionFor(connection), throwsStateError);
  });

  test('changed credentials create a distinct application scope', () async {
    final created = <_FakeApplicationSession>[];
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) {
        final session = _FakeApplicationSession();
        created.add(session);
        return session;
      },
    );

    final original = controller.sessionFor(_connection());
    final changed = controller.sessionFor(_connection(apiKey: 'rotated-key'));

    expect(identical(original, changed), isFalse);
    expect(controller.retainedSessionCount, 2);
    await controller.close();
    expect(created.map((session) => session.closeCount), everyElement(1));
  });

  test('gateway headers partition application scopes canonically', () async {
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => _FakeApplicationSession(),
    );
    final first = controller.sessionFor(
      _connection().copyWith(
        gatewayHeaders: const {
          'X-Access-Client': 'mobile',
          'X-Access-Secret': 'secret',
        },
      ),
    );
    final same = controller.sessionFor(
      _connection().copyWith(
        gatewayHeaders: const {
          'x-access-secret': 'secret',
          'x-access-client': 'mobile',
        },
      ),
    );
    final changed = controller.sessionFor(
      _connection().copyWith(
        gatewayHeaders: const {
          'X-Access-Client': 'mobile',
          'X-Access-Secret': 'rotated',
        },
      ),
    );

    expect(identical(first, same), isTrue);
    expect(identical(first, changed), isFalse);
    await controller.close();
  });
}

SavedConnection _connection({String apiKey = 'secret'}) => SavedConnection(
  id: 'remote-profile',
  label: 'Remote',
  host: '127.0.0.1',
  port: 8642,
  apiKey: apiKey,
  desktopGatewayUrl: 'ws://127.0.0.1:8643/ws',
  dashboardUsername: 'operator',
  dashboardPassword: 'dashboard-secret',
);

class _FakeApplicationSession implements GatewayTurnApplicationSession {
  int closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  set onTurnSettled(GatewayTurnSettledCallback? callback) {}

  @override
  set onSessionBound(GatewayTurnSessionBoundCallback? callback) {}

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) => throw UnimplementedError();

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();
}
