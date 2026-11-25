import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/chat_account_usage.dart';
import 'package:wing/core/models/chat_intelligence.dart';
import 'package:wing/core/models/model_choice.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/services/ws_client.dart';

import 'support/chat_account_usage_fixture.dart';
import 'support/composer_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stock report retains lines verbatim and keeps Nous route explicit', () {
    final report = ChatAccountUsage.fromJson(accountUsageReport);
    expect(report.lines, accountUsageReport['lines']);
    expect(report.nousLines, accountUsageReport['nous_lines']);
    expect(report.nousRoute, isFalse);
    expect(() => report.lines.add('injected'), throwsUnsupportedError);
    final empty = ChatAccountUsage.fromJson({
      'lines': <String>[],
      'nous_lines': <String>[],
      'nous_route': true,
      'nous_usage': {'available': true, 'total_spendable_usd': 12.5},
    });
    expect(empty.lines, isEmpty);
    expect(empty.nousLines, isEmpty);
    expect(empty.nousRoute, isTrue);
  });

  test(
    'malformed report is unavailable rather than fabricated empty limits',
    () {
      for (final invalid in [
        <String, dynamic>{},
        {...accountUsageReport, 'lines': '42%'},
        {
          ...accountUsageReport,
          'nous_lines': [12],
        },
        {...accountUsageReport, 'nous_route': 'false'},
      ]) {
        expect(() => ChatAccountUsage.fromJson(invalid), throwsFormatException);
      }
    },
  );

  group('captured workspace account read', () {
    late AccountUsageHarness harness;
    setUp(() async => harness = await AccountUsageHarness.create());
    tearDown(() => harness.dispose());

    test(
      'deduplicates held reads and retains report through failed refresh',
      () async {
        final controller = harness.controller;
        final chat = controller.current!.chat!;
        final session = controller.openAccountUsage(chat);
        addTearDown(session.dispose);
        final gate = harness.fixture.accountGate = Completer();
        final first = session.refresh();
        expect(session.refresh(), same(first));
        expect(session.loading, isTrue);
        expect(harness.fixture.accountRequests, [
          {
            'profile': chat.key.workspace.profileName,
            'session_id': chat.runtime.runtimeId,
          },
        ]);
        gate.complete(accountUsageReport);
        await first;
        final report = session.report;
        harness.fixture.accountGate = null;
        harness.fixture.failAccount = true;
        await session.refresh();
        expect(session.report, same(report));
        expect(session.error, contains('last received report'));
        expect(session.loading, isFalse);
        harness.fixture.failAccount = false;
        await session.refresh();
        expect(session.error, isNull);
        expect(session.report!.lines, accountUsageReport['lines']);
      },
    );

    for (final fail in [false, true]) {
      test(
        'profile departure rejects late ${fail ? 'error' : 'success'} for same session ID',
        () async {
          final controller = harness.controller;
          final personal = controller.current!;
          final chat = await controller.openSession(
            ProfileSessionKey(personal.scope, 'newest'),
          );
          final session = controller.openAccountUsage(chat!);
          addTearDown(session.dispose);
          final gate = harness.fixture.accountGate = Completer();
          final pending = session.refresh();
          await controller.switchProfile('work');
          final work = await controller.openSession(
            ProfileSessionKey(controller.current!.scope, 'newest'),
          );
          expect(work!.key.sessionId, chat.key.sessionId);
          expect(session.retired, isTrue);
          expect(session.loading, isFalse);
          harness.fixture.accountGate = null;
          final next = controller.openAccountUsage(work);
          addTearDown(next.dispose);
          harness.fixture.accountReport = {
            ...accountUsageReport,
            'lines': ['Work account'],
          };
          await next.refresh();
          if (fail) {
            gate.completeError(StateError('Old profile failure'));
          } else {
            gate.complete(accountUsageReport);
          }
          await pending;
          expect(session.report, isNull);
          expect(session.error, isNull);
          expect(next.report!.lines, ['Work account']);
          expect(harness.fixture.accountRequests.last['profile'], 'work');
        },
      );
    }

    test(
      'deferred Next turn survives until its route becomes effective',
      () async {
        final controller = harness.controller;
        final chat = controller.current!.chat!;
        final session = controller.openAccountUsage(chat);
        addTearDown(session.dispose);
        final gate = harness.fixture.accountGate = Completer();
        final pending = session.refresh();
        harness.fixture.deferMutation = true;
        const selection = ChatIntelligenceSelection(
          choice: ModelChoice(provider: 'openai-codex', model: 'gpt-5.6-sol'),
          reasoningEffort: 'high',
          fastMode: ChatFastMode.normal,
        );
        await controller.setIntelligence(
          chat,
          selection,
          confirmModelChange: (_) async => true,
        );
        expect(chat.pendingIntelligence, isNotNull);
        expect(chat.model, 'gpt-6-astra');
        expect(session.retired, isFalse);
        gate.complete(accountUsageReport);
        await pending;
        expect(session.report, isNotNull);
        final second = harness.fixture.accountGate = Completer();
        final refresh = session.refresh();
        emitChatEvent(controller, chat, 'session.updated', {
          'model': 'gpt-5.6-sol',
          'provider': 'openai-codex',
          'status': 'applied',
        });
        expect(session.retired, isTrue);
        expect(session.report, isNull);
        second.complete(accountUsageReport);
        await refresh;
        expect(session.report, isNull);
      },
    );

    test(
      'same runtime effective provider change clears a retained report',
      () async {
        final controller = harness.controller;
        final chat = controller.current!.chat!;
        final session = controller.openAccountUsage(chat);
        addTearDown(session.dispose);
        await session.refresh();
        emitChatEvent(controller, chat, 'session.info', {'provider': 'nous'});
        expect(session.retired, isTrue);
        expect(session.report, isNull);
        final count = harness.fixture.accountRequests.length;
        await session.refresh();
        expect(harness.fixture.accountRequests, hasLength(count));
      },
    );

    for (final change in ['runtime', 'generation', 'authority', 'replay']) {
      test('$change replacement retires a held report', () async {
        final controller = harness.controller;
        final chat = controller.current!.chat!;
        final session = controller.openAccountUsage(chat);
        addTearDown(session.dispose);
        final gate = harness.fixture.accountGate = Completer();
        final pending = session.refresh();
        if (change == 'runtime') {
          harness.fixture.resumedRuntimeId = 'replacement';
        }
        if (change == 'generation') harness.fixture.executionGeneration++;
        if (change == 'authority') harness.fixture.authorityEpoch++;
        if (change == 'replay') {
          harness.fixture.replayEpoch = 'replacement-epoch';
        }
        await controller.reconnect(chat.key.workspace);
        expect(session.retired, isTrue);
        expect(session.loading, isFalse);
        gate.complete(accountUsageReport);
        await pending;
        expect(session.report, isNull);
      });
    }

    test(
      'a replay gap retires existing data before held recovery and old account completion',
      () async {
        final controller = harness.controller;
        final chat = controller.current!.chat!;
        final gateway = controller.current!.gateway;
        final session = controller.openAccountUsage(chat);
        addTearDown(session.dispose);
        await session.refresh();
        final account = harness.fixture.accountGate = Completer();
        final pending = session.refresh();
        final recovery = harness.fixture.resumeGate = Completer();
        gateway.onEvent!(
          StreamEvent(
            type: 'session.info',
            sessionId: chat.runtime.runtimeId,
            data: const {},
            envelope: const {'replay_epoch': 'new-epoch', 'seq': 1},
          ),
        );
        expect(gateway.canonical.needsSnapshot(chat.runtime.runtimeId), isTrue);
        expect(session.retired, isTrue);
        expect(session.report, isNull);
        expect(session.loading, isFalse);
        account.complete(accountUsageReport);
        await pending;
        expect(session.report, isNull);
        harness.fixture.replayEpoch = 'new-epoch';
        recovery.complete();
        await Future<void>.delayed(Duration.zero);
        expect(session.retired, isTrue);
      },
    );

    test(
      'closing the page suppresses a held failure and further notifications',
      () async {
        final session = harness.controller.openAccountUsage(
          harness.controller.current!.chat!,
        );
        var notices = 0;
        session.addListener(() => notices++);
        final gate = harness.fixture.accountGate = Completer();
        final pending = session.refresh();
        session.dispose();
        final before = notices;
        gate.completeError(StateError('Late provider failure'));
        await pending;
        expect(notices, before);
        expect(session.error, isNull);
        expect(session.report, isNull);
      },
    );
  });
}
