import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_connection_identity.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profile_gateway.dart';

/// Production read-only acceptance. No session.resume, prompts, or mutations.
/// Display metadata and message bodies are never printed to logs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const label = String.fromEnvironment('PAGING_CONNECTION_LABEL');
  const host = String.fromEnvironment('PAGING_EXPECTED_HOST');
  testWidgets(
    'production history beyond 500 and whole-profile search',
    (tester) async {
      expect(label, isNotEmpty);
      expect(host, isNotEmpty);
      final preferences = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(preferences);
      final connection = (await manager.loadConnectionsWithSecrets())
          .singleWhere((c) => c.label == label && c.host == host);
      // Use the saved secret only for transport. Never restore pending runtimes
      // or overwrite the owner's selected profile/preferences in a read test.
      SharedPreferences.setMockInitialValues({});
      final controller = ProfileWorkspaceController(
        connection: connection,
        connectionIdentity: await ProfileConnectionIdentity().resolve(
          connection,
        ),
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
                  endpoint != 'sessions/search' &&
                  !RegExp(r'^sessions/[^/]+/messages$').hasMatch(endpoint)) {
                throw StateError('Read-only test blocked an unexpected route');
              }
              return live.read(endpoint, query);
            },
            rpc: (method, params) {
              if (method != 'projects.tree') {
                throw StateError(
                  'Read-only test blocked a non-allowlisted RPC',
                );
              }
              return live.call(method, params);
            },
          );
        },
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.error, isNull);
      final names = controller.discovery!.profiles.map((p) => p.name).toList();
      var longHistories = 0;
      var remoteMatches = 0;
      for (var index = 0; index < names.length; index++) {
        await controller.navigateProfile(names[index]);
        expect(controller.error, isNull);
        final data = controller.current!;
        final firstIds = data.sessions.map((s) => s['id']).toSet();
        var pages = 1;
        while (data.nextSessionOffset != null && pages < 40) {
          await controller.loadMoreSessions();
          expect(data.sessionsPageError, isNull);
          pages++;
        }
        if (data.sessions.isEmpty) continue;
        final outside = data.sessions
            .where((s) => !firstIds.contains(s['id']))
            .firstOrNull;
        if (outside != null) {
          final id = outside['id'] as String;
          await controller.searchChats(id);
          expect(data.searchError, isNull);
          expect(data.searchResults.any((s) => s['id'] == id), isTrue);
          expect(
            data.searchResults.every((s) => s['profile'] == names[index]),
            isTrue,
          );
          remoteMatches++;
        }
        await controller.searchChats('hermes');
        expect(data.searchError, isNull);
        expect(data.searchResults.length, lessThanOrEqualTo(100));
        debugPrint(
          '[history-search-readonly] profile ${index + 1}: content_matches=${data.searchResults.length} outside_first_page=${outside != null}',
        );
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
          title: 'Read-only history verification',
        );
        data.chats[id] = chat;
        data.selectedSession = id;
        await controller.refreshHistory(chat);
        expect(chat.historyError, isNull);
        final tail = chat.messages.map((m) => m['id']).toSet();
        var historyPages = 1;
        while (chat.nextHistoryOffset != null &&
            chat.messages.length <= 550 &&
            historyPages < 15) {
          await controller.loadOlderMessages(chat);
          expect(chat.historyError, isNull);
          historyPages++;
        }
        expect(
          chat.messages.map((m) => m['id']).toSet().length,
          chat.messages.length,
        );
        expect(
          chat.messages.map((m) => m['id']).toSet().containsAll(tail),
          isTrue,
        );
        if (chat.messages.length > 500) longHistories++;
        debugPrint(
          '[history-search-readonly] profile ${index + 1}: history_pages=$historyPages messages=${chat.messages.length} older_available=${chat.nextHistoryOffset != null}',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => ProfileTranscript(
                  key: ValueKey(chat.key),
                  chat: chat,
                  controller: controller,
                  messageBuilder: (m) => ProfileMessage(message: m),
                  tail: const [],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('profile-transcript')),
          const Offset(0, 400),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final candidatesOnScreen = find.byType(ProfileMessage).evaluate().where(
          (element) {
            final rect = tester.getRect(find.byWidget(element.widget));
            return rect.top >= 40 && rect.top < 300;
          },
        ).toList();
        if (candidatesOnScreen.isNotEmpty) {
          final anchorId =
              (candidatesOnScreen.first.widget as ProfileMessage).message['id'];
          final anchor = find.byWidgetPredicate(
            (w) => w is ProfileMessage && w.message['id'] == anchorId,
          );
          final before = tester.getTopLeft(anchor).dy;
          if (chat.nextHistoryOffset != null) {
            await controller.loadOlderMessages(chat);
            expect(chat.historyError, isNull);
            await tester.pumpAndSettle();
            expect(anchor.evaluate().length == 1, isTrue);
            expect(tester.getTopLeft(anchor).dy, closeTo(before, 2));
          }
          expect(find.byKey(const ValueKey('jump-to-latest')), findsOneWidget);
          final count = chat.messages.length;
          await tester.tap(find.byKey(const ValueKey('jump-to-latest')));
          await tester.pumpAndSettle();
          expect(chat.historyScrollOffset, closeTo(0, 1));
          expect(chat.messages.length, count);
        }
        // Refresh keeps the older prefix when the server's newest page overlaps.
        final oldest = chat.messages.firstOrNull?['id'];
        await controller.refreshHistory(chat);
        expect(chat.historyError, isNull);
        expect(chat.messages.firstOrNull?['id'] == oldest, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.showList();
        data.chats.remove(
          id,
        ); // Test-only read view, never a runtime attachment.
      }
      expect(remoteMatches, greaterThan(0));
      expect(
        longHistories,
        greaterThan(0),
        reason: 'No real history over 500 rows was available.',
      );
      debugPrint(
        '[history-search-readonly] PASS: profiles=${names.length} histories_over_500=$longHistories remote_searches=$remoteMatches; no resume, mutations, or model calls.',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
