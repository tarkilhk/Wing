import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/models/chat_runtime.dart';
import 'package:wing/core/models/context_occupancy.dart';
import 'package:wing/core/models/deleted_draft_cleanup.dart';
import 'package:wing/core/screens/chat_account_usage_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/subagent_timeline.dart';

import '../test/helpers/journey_controls.dart';
import 'hermes_next_conversation_prod_test.dart'
    show
        ownedProductionJourney,
        productionWorkspace,
        sendProductionText,
        showProductionWorkspace,
        waitForProductionState;
import 'support/journey_capture.dart';

const _nonce = String.fromEnvironment('WING_QA_NONCE');
const _profile = String.fromEnvironment('WING_QA_PROFILE');

Future<ProfileWorkspaceController> _workspace(
  WidgetTester tester,
  String kind,
) async {
  expect(_profile, _nonce);
  expect(_profile, isNot('default'));
  final owner = await productionWorkspace(
    'wing-prod-$kind-$_nonce',
    profile: _profile,
  );
  await showProductionWorkspace(tester, owner);
  await waitForProductionState(tester, () {
    final button = find.byKey(const ValueKey('workspace-new-chat'));
    return button.evaluate().length == 1 &&
        tester.widget<FloatingActionButton>(button).onPressed != null;
  }, 'The isolated profile enables New chat');
  return owner;
}

Future<void> _reply(
  WidgetTester tester,
  ProfileChat chat,
  String marker,
) async {
  await sendProductionText(
    tester,
    'Isolated Wing acceptance $_nonce. Reply exactly $marker. '
    'Do not call tools, delegate, browse, or read/change files.',
  );
  await waitForProductionState(
    tester,
    () =>
        !chat.runtime.blocksTurnAdmission &&
        chat.runtime.execution == ChatExecution.completed &&
        chat.reading.messages.any(
          (row) =>
              row['role'] == 'assistant' &&
              answerMessageText(row).contains(marker),
        ),
    'The owned chat persists its real provider reply',
  );
  expect(chat.runtime.error, isNull);
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await waitForProductionState(
    tester,
    () => tester.view.viewInsets.bottom == 0,
    'The native keyboard closes before opening details',
    seconds: 15,
  );
}

Map<String, Object?> _cacheFacts(PromptCacheWindow cache) => {
  'guaranteed_until': cache.guaranteedUntil?.toIso8601String(),
  'estimated_until': cache.estimatedUntil?.toIso8601String(),
  'refreshed_at': cache.refreshedAt?.toIso8601String(),
  'confidence': cache.confidence.name,
  'tier': cache.tier,
  'reason': cache.reason,
  'coverage': {
    for (final entry in cache.coverage.entries)
      entry.key: entry.value.toIso8601String(),
  },
  'warming_off': cache.warmingOff,
  'tier_pending': cache.tierPending,
  'learned': cache.learned,
};

/// The parent journey owns its chat; this receipt extends ownership only to
/// exact child IDs returned by the parent's stock transcript authorization.
class _ChildOwnership {
  _ChildOwnership(this.owner, this.parent);

  final ProfileWorkspaceController owner;
  final ProfileChat parent;
  final ids = <String>{};
  final agents = <String>{};
  final file = File(
    '${Directory.systemTemp.path}/wing-prod-owned-$_nonce-child-descendants.json',
  );
  String cleanup = 'not started';
  String outcome = 'incomplete';
  Map<String, Object?> settlement = const {};
  final parentReadbacks = <String, Map<String, Object?>>{};

  Map<String, Object?> rowFacts(Map<String, dynamic> row) => {
    for (final key in [
      'id',
      'role',
      'display_kind',
      'message_class',
      'source',
      'notification_category',
      '_reply_turn',
      '_reply_segment',
      '_turn_generation',
      'turn_id',
      'admission_id',
    ])
      if (row.containsKey(key)) key: row[key],
    'has_final_marker': answerMessageText(row).contains('WING_PARENT_$_nonce'),
    if (row['display_metadata'] case final Map metadata)
      'display_metadata': {
        'keys': metadata.keys.toList(),
        for (final key in [
          'kind',
          'source',
          'notification_category',
          'message_class',
        ])
          if (metadata.containsKey(key)) key: metadata[key],
      },
  };

  Future<void> inspectParent(String phase) async {
    final gateway = owner.current!.gateway;
    final authority = gateway.canonical.session(parent.runtime.runtimeId);
    final saved = await gateway.history(parent.key.sessionId);
    final evidence = <String, Object?>{
      'runtime_id': parent.runtime.runtimeId,
      'client_sequence': authority?.sequence,
      'client_generation': authority?.generation,
      'client_needs_snapshot': gateway.canonical.needsSnapshot(
        parent.runtime.runtimeId,
      ),
      'runtime_execution': parent.runtime.execution.name,
      'runtime_recovery': parent.runtime.recovery.name,
      'reading_history_loading': parent.reading.historyLoading,
      'reading_history_error': parent.reading.historyError,
      'visible_rows': parent.reading.messages.map(rowFacts).toList(),
      'saved_rows': saved.rows.map(rowFacts).toList(),
    };
    if (authority != null) {
      // Same read-only replay contract as ProfileGateway.completedToolActivities.
      // Inspecting this response does not apply events or repair local state.
      final replay = await gateway.call('session.events.since', {
        'session_id': parent.runtime.runtimeId,
        'replay_epoch': authority.replayEpoch,
        'last_sequence': 0,
      });
      evidence['replay'] = {
        for (final key in [
          'latest_seq',
          'snapshot_required',
          'truncated',
          'replay_epoch',
        ])
          key: replay[key],
        'events': [
          for (final event in (replay['events'] as List? ?? const []))
            if (event is Map &&
                const {
                  'message.start',
                  'message.complete',
                  'turn.end',
                  'turn.error',
                  'error',
                  'session.info',
                  'subagent.complete',
                  'session.updated',
                }.contains(event['type']))
              {
                for (final key in [
                  'session_id',
                  'seq',
                  'type',
                  'admission_id',
                  'execution_generation',
                ])
                  key: event[key],
                if (event['payload'] case final Map payload) ...{
                  'payload_keys': payload.keys.toList(),
                  for (final key in [
                    'turn_id',
                    'status',
                    'running',
                    'display_kind',
                    'notification_category',
                  ])
                    if (payload.containsKey(key)) key: payload[key],
                  'text_length': payload['text'] is String
                      ? (payload['text'] as String).length
                      : null,
                  'has_final_marker':
                      payload['text'] is String &&
                      (payload['text'] as String).contains(
                        'WING_PARENT_$_nonce',
                      ),
                },
              },
        ],
      };
    }
    parentReadbacks[phase] = evidence;
    await checkpoint();
    debugPrint(
      'WING_PROD_PARENT_READBACK ${jsonEncode({'phase': phase, ...evidence})}',
    );
  }

  Future<void> checkpoint() async {
    final pending = File('${file.path}.pending');
    await pending.writeAsString(
      jsonEncode({
        'nonce': _nonce,
        'origin': const String.fromEnvironment('WING_HERMES_URL'),
        'profile': _profile,
        'kind': 'child-descendants',
        'parent_session_id': parent.key.sessionId,
        'parent_runtime_id': parent.runtime.runtimeId,
        'subagent_ids': agents.toList(),
        'session_ids': ids.toList(),
        'outcome': outcome,
        'cleanup': cleanup,
        'settlement': settlement,
        'parent_readbacks': parentReadbacks,
      }),
      flush: true,
    );
    await pending.rename(file.path);
  }

  Future<Map<String, dynamic>> read(String agent) async {
    agents.add(agent);
    await checkpoint();
    final result = await owner.current!.gateway.call('session.transcript', {
      'session_id': parent.runtime.runtimeId,
      'subagent_id': agent,
      'order': 'latest',
      'limit': 100,
    });
    expect(result['session_id'], parent.runtime.runtimeId);
    expect(result['subagent_id'], agent);
    if (result['available'] == true) {
      final id = result['child_session_id'];
      expect(id, isA<String>());
      expect(id, isNotEmpty);
      expect(id, isNot(parent.key.sessionId));
      ids.add(id as String);
      await checkpoint();
    }
    return result;
  }

  Future<void> settle(
    WidgetTester tester, {
    bool requireParentReceipt = false,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 300));
    var settled = false;
    var savedReceipt = false;
    String? lastDiagnostic;
    var lastReported = DateTime.fromMillisecondsSinceEpoch(0);
    while (!settled && DateTime.now().isBefore(deadline)) {
      await owner.refreshSubagents(parent);
      expect(parent.subagentsError, isNull);
      for (final agent in parent.subagents) {
        await read(agent.id);
      }
      final childrenTerminal = parent.subagents.every(
        (agent) => agent.isTerminal,
      );
      final visibleReceipt = parent.reading.messages.any(
        (row) =>
            row['role'] == 'assistant' &&
            answerMessageText(row).contains('WING_PARENT_$_nonce'),
      );
      if (requireParentReceipt && childrenTerminal && !savedReceipt) {
        final saved = await owner.current!.gateway.history(
          parent.key.sessionId,
        );
        savedReceipt = saved.rows.any(
          (row) =>
              row['role'] == 'assistant' &&
              answerMessageText(row).contains('WING_PARENT_$_nonce'),
        );
      }
      settlement = {
        'children': [
          for (final child in parent.subagents)
            {'id': child.id, 'status': child.status.name},
        ],
        'children_terminal': childrenTerminal,
        'parent_execution': parent.runtime.execution.name,
        'parent_recovery': parent.runtime.recovery.name,
        'parent_blocks_admission': parent.runtime.blocksTurnAdmission,
        'parent_command_running': parent.runtime.commandRunning,
        'parent_error_present': parent.runtime.error != null,
        'parent_visible_receipt': visibleReceipt,
        'parent_saved_receipt': savedReceipt,
        'parent_reading_rows': parent.reading.messages.length,
      };
      final diagnostic = jsonEncode(settlement);
      final now = DateTime.now();
      if (diagnostic != lastDiagnostic ||
          now.difference(lastReported) >= const Duration(seconds: 10)) {
        debugPrint('WING_PROD_CHILD_SETTLE $diagnostic');
        await checkpoint();
        lastDiagnostic = diagnostic;
        lastReported = now;
      }
      settled =
          childrenTerminal &&
          !parent.runtime.blocksTurnAdmission &&
          !parent.runtime.commandRunning &&
          (!requireParentReceipt || savedReceipt);
      if (!settled) await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      settled,
      isTrue,
      reason:
          'The owned child and its parent completion must both settle: '
          '${jsonEncode(settlement)}',
    );
  }

  Future<void> clean(WidgetTester tester) async {
    cleanup = 'settling owned children and parent';
    await checkpoint();
    await settle(tester);
    // Read once more after completion, when a child can first acquire its
    // persisted identity or rotate to a final storage segment.
    for (final agent in agents.toList()) {
      await read(agent);
    }
    final gateway = owner.current!.gateway;
    for (final id in ids) {
      final metadata = await gateway.sessionMetadata(id);
      if (metadata != null) {
        expect(metadata['id'], id);
        expect(metadata['profile'], _profile);
        cleanup = 'delete requested; result unconfirmed';
        await checkpoint();
        await gateway.deleteSession(id, canDispatch: () => true);
      }
      expect(await gateway.verifyDeletedSession(id), SessionPresence.absent);
    }
    cleanup = 'confirmed absent';
    await checkpoint();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  WidgetController.hitTestWarningShouldBeFatal = true;

  testJourney(
    'Production current chat account usage reads and refreshes the real provider report',
    (tester) async {
      final owner = await _workspace(tester, 'account-usage');
      await ownedProductionJourney(
        tester,
        owner,
        'account-usage',
        'Wing account usage QA $_nonce',
        (chat, checkpoint) async {
          await _reply(tester, chat, 'WING_ACCOUNT_$_nonce');
          await checkpoint();
          await tapJourneyControl(tester, find.byTooltip('Chat actions'));
          await tapJourneyControl(tester, find.text('Account usage'));
          await waitForProductionState(
            tester,
            () => find.byType(ChatAccountUsageScreen).evaluate().isNotEmpty,
            'The actual Chat actions control opens Account usage',
          );
          final page = tester.widget<ChatAccountUsageScreen>(
            find.byType(ChatAccountUsageScreen),
          );
          final visit = page.session;
          await waitForProductionState(
            tester,
            () => !visit.loading,
            'The real session account report settles',
          );
          expect(visit.error, isNull);
          expect(visit.retired, isFalse);
          final first = visit.report;
          expect(first, isNotNull);
          expect(
            first!.lines.isNotEmpty || first.nousLines.isNotEmpty,
            isTrue,
            reason: 'This production proof requires a supplied account report',
          );
          void visibleReport() {
            final report = visit.report!;
            if (report.lines.isNotEmpty) {
              expect(find.text(report.lines.join('\n')), findsOneWidget);
            }
            if (report.nousLines.isNotEmpty) {
              expect(find.text(report.nousLines.join('\n')), findsOneWidget);
              expect(
                find.text(
                  report.nousRoute ? 'Nous account' : 'Separate Nous account',
                ),
                findsOneWidget,
              );
            }
          }

          visibleReport();
          await captureJourney(tester, 'prod-account-usage-report');
          await tapJourneyControl(
            tester,
            find.byTooltip('Refresh account usage'),
          );
          await waitForProductionState(
            tester,
            () => !visit.loading && !identical(visit.report, first),
            'The actual Refresh control publishes a new provider report',
          );
          expect(visit.error, isNull);
          expect(visit.retired, isFalse);
          visibleReport();
          await captureJourney(tester, 'prod-account-usage-refreshed');
          debugPrint(
            'WING_PROD_ACCOUNT ${jsonEncode({'provider': chat.provider, 'model': chat.model, 'chat_lines': visit.report!.lines.length, 'nous_lines': visit.report!.nousLines.length, 'nous_route': visit.report!.nousRoute})}',
          );
          await tapJourneyControl(tester, find.byTooltip('Back'));
          await checkpoint();
        },
      );
    },
  );

  testJourney(
    'Production prompt cache details preserve server reported lifecycle facts',
    (tester) async {
      final owner = await _workspace(tester, 'prompt-cache');
      await ownedProductionJourney(
        tester,
        owner,
        'prompt-cache',
        'Wing prompt cache QA $_nonce',
        (chat, checkpoint) async {
          final gateway = owner.current!.gateway;
          var populatedReports = 0;
          for (var turn = 1; turn <= 2; turn++) {
            await _reply(tester, chat, 'WING_CACHE_${_nonce}_$turn');
            await checkpoint();
            await tapJourneyControl(
              tester,
              find.byKey(const ValueKey('context-ring-details')),
            );
            await waitForProductionState(
              tester,
              () => !chat.contextLoading,
              'Opening the actual context ring reads live cache facts',
            );
            expect(chat.contextError, isNull);
            final cache = chat.promptCache;
            final response = await gateway.call('session.context_breakdown', {
              'session_id': chat.runtime.runtimeId,
            });
            final reported = PromptCacheWindow.fromJson(
              response['prompt_cache'],
            );
            debugPrint(
              'WING_PROD_CACHE_RAW ${jsonEncode({'turn': turn, 'provider': chat.provider, 'model': chat.model, 'prompt_cache': response['prompt_cache']})}',
            );
            if (reported == null) {
              expect(cache, isNull);
              expect(find.text('Prompt cache'), findsNothing);
              await captureJourney(
                tester,
                'prod-cache-not-reported-turn-$turn',
              );
              await tapJourneyControl(
                tester,
                find.byTooltip('Close context window'),
              );
              continue;
            }
            expect(cache, isNotNull);
            populatedReports++;
            expect(_cacheFacts(cache!), _cacheFacts(reported));
            await revealJourneyControl(tester, find.text('Prompt cache'));
            expect(find.text('Confidence'), findsOneWidget);
            expect(
              find.text(switch (cache.confidence) {
                PromptCacheConfidence.proven => 'Proven',
                PromptCacheConfidence.declared => 'Declared',
                PromptCacheConfidence.assumed => 'Assumed',
                PromptCacheConfidence.unknown => 'Unknown',
              }),
              findsWidgets,
            );
            final locale = MaterialLocalizations.of(
              tester.element(find.text('Prompt cache')),
            );
            String date(DateTime value) {
              String two(int part) => part.toString().padLeft(2, '0');
              return '${locale.formatCompactDate(value)} '
                  '${two(value.hour)}:${two(value.minute)}:${two(value.second)} UTC';
            }

            for (final value in [
              cache.guaranteedUntil,
              cache.estimatedUntil,
              cache.refreshedAt,
              ...cache.coverage.values,
            ].whereType<DateTime>()) {
              expect(find.text(date(value)), findsWidgets);
            }
            if (cache.guaranteedUntil == null || cache.estimatedUntil == null) {
              expect(find.text('Not reported'), findsWidgets);
            }
            if (cache.tier case final tier?) {
              expect(find.text(tier), findsOneWidget);
            }
            await captureJourney(tester, 'prod-cache-report-turn-$turn');
            await revealJourneyControl(
              tester,
              find.text('Retention upper bound'),
            );
            if (cache.warmingOff == true) {
              expect(
                find.text('Cache warming is off for this session.'),
                findsOneWidget,
              );
            }
            await captureJourney(tester, 'prod-cache-lifecycle-turn-$turn');
            debugPrint(
              'WING_PROD_CACHE ${jsonEncode({'turn': turn, 'provider': chat.provider, 'model': chat.model, ..._cacheFacts(cache)})}',
            );
            await tapJourneyControl(
              tester,
              find.byTooltip('Close context window'),
            );
          }
          expect(
            populatedReports,
            greaterThan(0),
            reason:
                'Cache lifecycle proof requires a server report after either '
                'real turn; this provider did not supply one',
          );
          await checkpoint();
        },
      );
    },
  );

  testJourney(
    'Production child transcript reads durable history through its parent authority',
    (tester) async {
      final owner = await _workspace(tester, 'child-transcript');
      await ownedProductionJourney(
        tester,
        owner,
        'child-transcript',
        'Wing child transcript QA $_nonce',
        (chat, checkpoint) async {
          final children = _ChildOwnership(owner, chat);
          expect(await children.file.exists(), isFalse);
          await children.checkpoint();
          Object? primaryFailure;
          StackTrace? primaryStack;
          try {
            final marker = 'WING_CHILD_$_nonce';
            await sendProductionText(
              tester,
              'Isolated authorized Wing acceptance $_nonce. Delegate exactly '
              'one child. Its complete task is: use terminal '
              'exactly once to run Python with constant memory, initialize x '
              'to b"wing-qa", repeat x=hashlib.sha256(x).digest() exactly '
              '12000000 times in an ordinary for loop, and print x.hex(). '
              'Then reply exactly $marker. The child must not read or write '
              'files, access the network, sleep, delegate, or use any other '
              'tools. After dispatch, reply WING_DISPATCH_$_nonce. When its '
              'completion arrives, reply WING_PARENT_$_nonce without further '
              'tools or delegation. Do not issue that final marker before '
              'receiving the child completion.',
            );
            await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
            await waitForProductionState(
              tester,
              () => chat.subagents.isNotEmpty,
              'A real delegated child appears in the parent activity',
            );
            await checkpoint();
            expect(chat.subagents, hasLength(1));
            final agent = chat.subagents.single.id;
            await children.read(agent);
            final tab = find.byKey(const ValueKey(('live-work-tab', 0, false)));
            await tapJourneyControl(tester, tab);
            final row = find.byKey(ValueKey(('subagent', chat.key, agent)));
            await tapJourneyControl(
              tester,
              find.descendant(
                of: row,
                matching: find.byIcon(Icons.chevron_right),
              ),
            );
            await waitForProductionState(
              tester,
              () => find.byType(SubagentTimeline).evaluate().isNotEmpty,
              'The real child row opens its transcript',
            );
            final timeline = tester
                .widget<SubagentTimeline>(find.byType(SubagentTimeline))
                .session;
            await children.settle(tester, requireParentReceipt: true);
            expect(chat.runtime.error, isNull);
            final saved = await children.read(agent);
            expect(saved['available'], isTrue);
            final rows = saved['rows'] as List;
            expect(
              rows.any((row) => row['role'] == 'tool'),
              isTrue,
              reason: 'The child must persist its requested finite tool task',
            );
            expect(
              rows.any(
                (row) =>
                    row['role'] == 'assistant' &&
                    (row['text'] as String? ?? '').contains(marker),
              ),
              isTrue,
              reason:
                  'Child evidence must exist in durable parent-authorized rows',
            );
            await tapJourneyControl(
              tester,
              find.byTooltip('Refresh subagent activity'),
            );
            await waitForProductionState(
              tester,
              () =>
                  !timeline.historyLoading &&
                  timeline.messages.any(
                    (row) =>
                        row['role'] == 'assistant' &&
                        answerMessageText(row).contains(marker),
                  ),
              'Refreshing after completion displays durable child output',
            );
            expect(timeline.historyError, isNull);
            expect(timeline.historyAvailable, isTrue);
            expect(timeline.resourceKey?.sessionId, saved['child_session_id']);
            expect(timeline.resourceKey?.workspace.profileName, _profile);
            final result = find.descendant(
              of: find.byType(SubagentTimeline),
              matching: find.text(marker, findRichText: true),
            );
            await revealJourneyControl(tester, result);
            await captureJourney(tester, 'prod-child-durable-transcript');
            debugPrint(
              'WING_PROD_CHILD ${jsonEncode({'durable_rows': rows.length, 'parent_authorized': true, 'live_error': timeline.liveError, 'child_count': children.ids.length})}',
            );
            await children.inspectParent('sheet-open');
            await tapJourneyControl(
              tester,
              find.byTooltip('Close subagent activity'),
            );
            await waitForProductionState(
              tester,
              () => find.byType(SubagentTimeline).evaluate().isEmpty,
              'Closing child details reveals the retained parent',
            );
            await waitForProductionState(
              tester,
              () =>
                  chat.reading.streaming.isEmpty &&
                  chat.reading.messages.any(
                    (row) =>
                        row['role'] == 'assistant' &&
                        answerMessageText(row).contains('WING_PARENT_$_nonce'),
                  ),
              'The parent completion settles into saved history without refresh',
              seconds: 20,
            );
            final parentResult = find.text(
              'WING_PARENT_$_nonce',
              findRichText: true,
            );
            await revealJourneyControl(tester, parentResult);
            expect(parentResult.hitTestable(), findsOneWidget);
            await captureJourney(
              tester,
              'prod-parent-after-child-before-refresh',
            );
            await children.inspectParent('sheet-closed-before-refresh');
            // The parent's final answer must already be present before any refresh.
            debugPrint(
              'WING_PROD_PARENT_PRESENTATION ${jsonEncode({'reading_has_final_marker': chat.reading.messages.any((row) => row['role'] == 'assistant' && answerMessageText(row).contains('WING_PARENT_$_nonce')), 'rendered_final_marker': find.text('WING_PARENT_$_nonce', findRichText: true).hitTestable().evaluate().isNotEmpty})}',
            );
            children.outcome = 'passed';
          } catch (error, stack) {
            primaryFailure = error;
            primaryStack = stack;
            children.outcome = 'failed';
            try {
              await captureJourney(
                tester,
                'prod-child-transcript-before-cleanup-failure',
                failure: true,
              );
            } catch (_) {
              // Preserve the original verdict if capture is unavailable.
            }
          } finally {
            try {
              await children.clean(tester);
            } catch (error, stack) {
              children.cleanup = 'unconfirmed; retained for operator recovery';
              await children.checkpoint();
              primaryFailure ??= error;
              primaryStack ??= stack;
            }
          }
          if (primaryFailure != null) {
            Error.throwWithStackTrace(primaryFailure, primaryStack!);
          }
          await checkpoint();
        },
      );
    },
  );
}
