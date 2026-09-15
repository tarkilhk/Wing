import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/gateway_process.dart';

void main() {
  test('parses a real running process row and ignores extra fields', () {
    final process = GatewayProcessActivity.fromJson({
      'session_id': 'proc_abc123',
      'command': 'python  -m\nhttp.server 8000',
      'cwd': '/srv/project',
      'pid': 4217,
      'owner_task_id': 'turn-9',
      'started_at': '2026-09-12T14:03:11',
      'uptime_seconds': 83,
      'status': 'running',
      'output_preview': 'Serving HTTP',
      'output_tail': 'Serving HTTP on 0.0.0.0 port 8000\n',
      'session_scoped': true,
      'notify_on_complete': true,
      'future_field': {'ignored': true},
    });

    expect(process, isNotNull);
    expect(process!.id, 'proc_abc123');
    expect(process.command, 'python -m http.server 8000');
    expect(process.cwd, '/srv/project');
    expect(process.status, GatewayProcessStatus.running);
    expect(process.isRunning, isTrue);
    expect(process.pid, 4217);
    expect(process.uptimeSeconds, 83);
    expect(process.outputTail, endsWith('port 8000\n'));
    expect(process.notifyOnComplete, isTrue);
  });

  test('parses exited metadata without deriving time on the phone', () {
    final process = GatewayProcessActivity.fromJson({
      'session_id': 'proc_done',
      'command': 'dart test',
      'cwd': null,
      'pid': null,
      'started_at': 'not used for local time calculations',
      'uptime_seconds': 12,
      'status': 'exited',
      'exit_code': 1,
      'output_preview': 'failed',
      'output_tail': 'one test failed',
      'detached': true,
    })!;

    expect(process.status, GatewayProcessStatus.exited);
    expect(process.isRunning, isFalse);
    expect(process.exitCode, 1);
    expect(process.uptimeSeconds, 12);
    expect(process.detached, isTrue);
  });

  test('rejects malformed identity and status, and bounds display data', () {
    expect(
      GatewayProcessActivity.fromJson({
        'session_id': '',
        'command': 'serve',
        'status': 'running',
      }),
      isNull,
    );
    expect(
      GatewayProcessActivity.fromJson({
        'session_id': 'proc_unknown',
        'command': 'serve',
        'status': 'stopping',
      }),
      isNull,
    );

    final process = GatewayProcessActivity.fromJson({
      'session_id': 'proc_large',
      'command': 'x' * 500,
      'cwd': 'y' * 1500,
      'status': 'running',
      'uptime_seconds': -1,
      'pid': 0,
      'output_tail': 'old${'z' * 5000}',
    })!;

    expect(process.command.length, 200);
    expect(process.command, endsWith('…'));
    expect(process.cwd?.length, 1000);
    expect(process.outputTail?.length, 4000);
    expect(process.outputTail, isNot(startsWith('old')));
    expect(process.uptimeSeconds, isNull);
    expect(process.pid, isNull);
  });
}
