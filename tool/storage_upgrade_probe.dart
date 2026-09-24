import 'package:flutter/material.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/gateway_turn_journal.dart';

const _mode = String.fromEnvironment('WING_UPGRADE_PROBE');
const _credentialKey = 'wing_storage_upgrade_probe';
const _expected = 'saved-before-upgrade';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String status;
  try {
    final credentials = FlutterSecureCredentialStore();
    final journal = FlutterSecureGatewayTurnJournalStore();
    if (_mode == 'seed') {
      await credentials.write(_credentialKey, _expected);
      await journal.write(_expected);
      status = 'UPGRADE_CHECK_SEEDED';
    } else if (_mode == 'verify') {
      final credential = await credentials.read(_credentialKey);
      final recovery = await journal.read();
      status = credential == _expected && recovery == _expected
          ? 'UPGRADE_CHECK_PASSED'
          : 'UPGRADE_CHECK_FAILED';
    } else {
      status = 'UPGRADE_CHECK_INVALID_MODE';
    }
  } catch (error) {
    status = 'UPGRADE_CHECK_ERROR';
    debugPrint('Storage upgrade probe failed: $error');
  }
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(status)))));
}
