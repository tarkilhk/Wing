/// Standalone emulator probe for environments where the VM test service cannot
/// attach. Build as a debug entry point, launch normally, then restore main.dart.
/// It prints counts only and cannot resume a runtime or write server data.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = ValueNotifier(
    'Read-only production history check is running.',
  );
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<String>(
              valueListenable: report,
              builder: (_, text, _) => Text(text),
            ),
          ),
        ),
      ),
    ),
  );
  ProfileWorkspaceController? controller;
  try {
    const label = String.fromEnvironment('PAGING_CONNECTION_LABEL');
    const host = String.fromEnvironment('PAGING_EXPECTED_HOST');
    if (label.isEmpty || host.isEmpty) throw StateError('Missing test target');
    final manager = await ConnectionManager.create(
      await SharedPreferences.getInstance(),
    );
    final connection = (await manager.loadConnectionsWithSecrets()).singleWhere(
      (c) => c.label == label && c.host == host,
    );
    SharedPreferences.setMockInitialValues({});
    controller = ProfileWorkspaceController(
      connection: connection,
      connectionIdentity: 'read-only-probe',
      preferences: await SharedPreferences.getInstance(),
      gatewayFactory: (scope) {
        final live = ProfileGateway.forConnection(connection, scope);
        return ProfileGateway(
          scope: scope,
          discover: live.discover,
          connect: live.connect,
          close: live.close,
          get: (endpoint, query) {
            if (endpoint != 'sessions' &&
                !RegExp(r'^sessions/[^/]+/messages$').hasMatch(endpoint)) {
              throw StateError('Non-allowlisted read');
            }
            return live.read(endpoint, query);
          },
          rpc: (method, params) {
            if (method != 'projects.tree') {
              throw StateError('Non-allowlisted RPC');
            }
            return live.call(method, params);
          },
        );
      },
    );
    await controller.initialize();
    if (controller.error != null) {
      throw StateError('Discovery or initial list failed');
    }
    final names = controller.discovery!.profiles.map((p) => p.name).toList();
    var longHistories = 0;
    final counts = <int>[];
    for (var index = 0; index < names.length; index++) {
      await controller.navigateProfile(names[index]);
      if (controller.error != null) throw StateError('Profile list failed');
      final data = controller.current!;
      for (var page = 1; data.nextSessionOffset != null && page < 40; page++) {
        await controller.loadMoreSessions();
        if (data.sessionsPageError != null) {
          throw StateError('Session page failed');
        }
      }
      if (data.sessions.isEmpty) continue;
      final candidates = data.sessions.toList()
        ..sort(
          (a, b) => ((b['message_count'] as num?) ?? 0).compareTo(
            (a['message_count'] as num?) ?? 0,
          ),
        );
      final id = candidates.first['id'] as String;
      final chat = ProfileChat(
        key: ProfileSessionKey(data.scope, id),
        runtimeId: '',
        title: 'Read-only check',
      );
      data.chats[id] = chat;
      data.selectedSession = id;
      await controller.refreshHistory(chat);
      if (chat.historyError != null) throw StateError('Latest history failed');
      final latestIds = chat.messages.map((m) => m['id']).toSet();
      for (
        var page = 1;
        chat.nextHistoryOffset != null &&
            chat.messages.length <= 550 &&
            page < 15;
        page++
      ) {
        await controller.loadOlderMessages(chat);
        if (chat.historyError != null) throw StateError('Older history failed');
      }
      final ids = chat.messages.map((m) => m['id']).toSet();
      if (ids.length != chat.messages.length || !ids.containsAll(latestIds)) {
        throw StateError('History identity check failed');
      }
      final oldest = chat.messages.firstOrNull?['id'];
      final before = chat.messages.length;
      await controller.refreshHistory(chat);
      if (chat.historyError != null ||
          chat.messages.firstOrNull?['id'] != oldest) {
        throw StateError('History refresh lost the older prefix');
      }
      if (before > 500) longHistories++;
      counts.add(before);
      debugPrint(
        '[readonly-history-probe] profile ${index + 1}: rows=$before unique=true prefix_retained=true',
      );
      report.value =
          'Read-only history checks completed for ${index + 1}/${names.length} profiles.';
      controller.showList();
      data.chats.remove(id);
    }
    if (longHistories == 0) {
      throw StateError('No history over 500 rows was available');
    }
    report.value =
        'PASS: ${counts.length} histories, rows=$counts. Unique IDs, newest page and older prefix retained. No runtime resume, prompts or server mutations.';
    debugPrint('[readonly-history-probe] ${report.value}');
  } catch (_) {
    // Do not print exception text, which may contain a private endpoint or data.
    report.value =
        'FAIL: read-only history verification could not finish. No server mutations were allowed.';
    debugPrint('[readonly-history-probe] ${report.value}');
  } finally {
    controller?.dispose();
  }
}
