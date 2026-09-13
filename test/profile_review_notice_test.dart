import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';
import 'package:hermes_android/core/models/review_notice.dart';
import 'package:hermes_android/core/screens/profile_workspace_screen.dart';
import 'package:hermes_android/core/services/profile_gateway.dart';
import 'package:hermes_android/core/services/profile_workspace_controller.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/profile_review_notice_card.dart';
import 'package:hermes_android/core/widgets/profile_tool_activity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_history_fixture.dart';

class _ReviewFixture extends ProfileHistoryFixture {
  final gateways = <String, ProfileGateway>{};
  final runtimeOverrides = <String, String>{};

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    final gateway = ProfileGateway(
      scope: scope,
      discover: base.discover,
      connect: base.connect,
      close: base.close,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'session.resume') {
          final sessionId = params['session_id'] as String;
          return {
            'session_id': runtimeOverrides[sessionId] ?? '$sessionId-runtime',
            'stored_session_id': sessionId,
            'messages': const [],
            'info': {'profile_name': scope.profileName},
          };
        }
        return base.call(method, params);
      },
    );
    gateways[scope.profileName] = gateway;
    return gateway;
  }

  void event(String profile, String sessionId, Map<String, dynamic> data) {
    gateways[profile]!.onEvent!(
      StreamEvent(type: 'review.summary', data: data, sessionId: sessionId),
    );
  }
}

void main() {
  late _ReviewFixture fixture;
  late SharedPreferences preferences;
  late ProfileWorkspaceController controller;

  Future<ProfileWorkspaceController> makeController() async {
    final next = ProfileWorkspaceController(
      connection: identityTestConnection(),
      connectionIdentity: 'review-notices',
      preferences: preferences,
      gatewayFactory: fixture.gateway,
    );
    await next.initialize();
    return next;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    fixture = _ReviewFixture()..messageCount = 0;
    controller = await makeController();
  });

  tearDown(() => controller.dispose());

  testWidgets(
    'review stays before later messages instead of following the chat',
    (tester) async {
      final scope = controller.current!.scope;
      await controller.openSession(ProfileSessionKey(scope, 'chat-0'));
      final chat = controller.current!.chat!;
      fixture.event('personal', chat.runtimeId, {
        'text': '💾 Self-improvement review: Changes await approval.',
        'timestamp': 401.625,
      });
      expect(chat.messages.single['role'], 'system');
      expect(chat.messages.single['timestamp'], 401.625);
      await tester.pumpWidget(
        MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hermes review'), findsOneWidget);
      chat.messages.add({
        'id': 1,
        'role': 'user',
        'content': 'Continue the conversation',
      });
      fixture.event('personal', chat.runtimeId, const {});
      await tester.pumpAndSettle();

      expect(find.text('Hermes review'), findsNothing);
      expect(find.textContaining('Changes await approval.'), findsNothing);
      final activity = find.text('Activity');
      expect(activity, findsOneWidget);
      expect(
        tester.getTopLeft(activity).dy,
        lessThan(tester.getTopLeft(find.text('Continue the conversation')).dy),
      );
      await tester.tap(activity);
      await tester.pumpAndSettle();
      expect(find.text('Hermes review'), findsOneWidget);
      expect(find.textContaining('Changes await approval.'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(ProfileReviewNoticeRow),
          matching: find.byIcon(Icons.psychology_outlined),
        ),
      );
      await tester.pumpAndSettle();
      final review = find.text(
        'Self-improvement review: Changes await approval.',
      );
      expect(review, findsOneWidget);
      expect(
        find.ancestor(of: review, matching: find.byType(Card)),
        findsNothing,
      );
    },
  );

  testWidgets('routes review summaries to the owning chat and opens details', (
    tester,
  ) async {
    final scope = controller.current!.scope;
    await controller.openSession(ProfileSessionKey(scope, 'chat-0'));
    final owner = controller.current!.chat!;
    await controller.openSession(ProfileSessionKey(scope, 'chat-1'));

    fixture.event('personal', owner.runtimeId, {
      'text': 'Two changes need a closer look.',
    });

    expect(owner.reviewNotices.single.text, 'Two changes need a closer look.');
    expect(controller.current!.chat!.reviewNotices, isEmpty);

    await controller.openSession(owner.key);
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProfileReviewNoticeRow), findsOneWidget);
    expect(find.text('Hermes review'), findsOneWidget);
    expect(find.text('Two changes need a closer look.'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(ProfileReviewNoticeRow),
        matching: find.byIcon(Icons.psychology_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Two changes need a closer look.'), findsOneWidget);
  });

  test(
    'ignores malformed summaries and keeps only the newest bounded set',
    () async {
      final scope = controller.current!.scope;
      await controller.openSession(ProfileSessionKey(scope, 'chat-0'));
      final chat = controller.current!.chat!;

      fixture.event('personal', chat.runtimeId, const {});
      fixture.event('personal', chat.runtimeId, {'text': '   '});
      fixture.event('personal', chat.runtimeId, {'text': 7});
      fixture.event('personal', chat.runtimeId, {
        'text': ['review'],
      });
      fixture.event('personal', chat.runtimeId, {
        'text': {'summary': 'review'},
      });
      fixture.event('personal', chat.runtimeId, {'text': 'Review 0'});
      for (var i = 0; i <= 20; i++) {
        fixture.event('personal', chat.runtimeId, {'text': 'Review $i'});
      }

      expect(chat.reviewNotices, hasLength(20));
      expect(chat.reviewNotices.first.text, 'Review 1');
      expect(chat.reviewNotices.last.text, 'Review 20');
      expect(chat.messages.where(isLocalReviewMessage), hasLength(20));
    },
  );

  test(
    'refresh retains review position and excludes it from history offsets',
    () async {
      fixture.messageCount = 220;
      final scope = controller.current!.scope;
      await controller.openSession(ProfileSessionKey(scope, 'chat-0'));
      final chat = controller.current!.chat!;
      final offset = chat.nextHistoryOffset;
      fixture.event('personal', chat.runtimeId, {'text': 'First review'});
      fixture.event('personal', chat.runtimeId, {'text': 'Second review'});
      fixture.messageCount = 222;
      await controller.refreshHistory(chat);

      final first = chat.messages.indexWhere(
        (row) => reviewMessageText(row) == 'First review',
      );
      expect(chat.messages[first - 1]['id'], 220);
      expect(reviewMessageText(chat.messages[first + 1]), 'Second review');
      expect(chat.messages[first + 2]['id'], 221);
      expect(chat.nextHistoryOffset, offset! + 2);
      while (chat.nextHistoryOffset != null) {
        final before = chat.nextHistoryOffset;
        await controller.loadOlderMessages(chat);
        expect(chat.historyError, isNull);
        expect(chat.nextHistoryOffset, isNot(before));
      }
      expect(chat.messages.where((row) => row['id'] is int), hasLength(222));
      expect(chat.messages.where(isLocalReviewMessage), hasLength(2));
      expect(chat.messages.first['id'], 1);
    },
  );

  test(
    'reviews join tool activity without swallowing ordinary system text',
    () {
      final sections = groupTranscriptSections([
        {'id': 1, 'role': 'tool', 'content': 'Skill updated'},
        {'id': 2, 'role': 'system', 'content': 'review:Skill update details'},
        {'id': 3, 'role': 'tool', 'content': 'Verified'},
        {'id': 4, 'role': 'system', 'content': 'Ordinary notice'},
        {'id': 5, 'role': 'assistant', 'content': 'review:Quoted example'},
      ]);
      expect(sections, hasLength(3));
      expect(sections.first.isActivity, isTrue);
      expect(sections.first.messages, hasLength(3));
      expect(sections[1].isActivity, isFalse);
      expect(sections[2].isActivity, isFalse);
    },
  );

  test(
    'a stored review replaces its local copy without reordering reviews',
    () {
      final before = {'id': 1, 'role': 'user', 'content': 'Earlier prompt'};
      final first = {
        'id': 'local-first',
        'role': 'system',
        'content': 'review:First',
        '_review_notice': 'first',
      };
      final second = {
        'id': 'local-second',
        'role': 'system',
        'content': 'review:Second',
        '_review_notice': 'second',
      };
      final merged = retainReviewMessages(
        [before, first, second],
        [
          before,
          {'id': 2, 'role': 'system', 'content': 'review:First'},
          {'id': 3, 'role': 'assistant', 'content': 'Later answer'},
        ],
      );
      expect(merged.map((row) => row['id']), [1, 2, 'local-second', 3]);
    },
  );

  testWidgets('long review details scroll on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text =
        '${List.filled(30, 'Skill update details.').join('\n')}\nLast detail';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: ProfileReviewNoticeRow(text: text)),
      ),
    );
    await tester.tap(find.byIcon(Icons.psychology_outlined));
    await tester.pumpAndSettle();
    expect(find.text(text), findsOneWidget);
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test(
    'review summaries have no durability across a runtime or controller reset',
    () async {
      final scope = controller.current!.scope;
      await controller.openSession(ProfileSessionKey(scope, 'chat-0'));
      final chat = controller.current!.chat!;
      fixture.event('personal', chat.runtimeId, {'text': 'Transient review'});

      await controller.reconnect(scope);
      expect(chat.reviewNotices.single.text, 'Transient review');
      expect(chat.messages.where(isLocalReviewMessage), hasLength(1));

      fixture.runtimeOverrides['chat-0'] = 'chat-0-replaced-runtime';
      await controller.reconnect(scope);
      expect(chat.reviewNotices, isEmpty);
      expect(chat.messages.where(isLocalReviewMessage), isEmpty);

      fixture.event('personal', chat.runtimeId, {'text': 'Another review'});
      controller.dispose();
      controller = await makeController();
      await controller.openSession(ProfileSessionKey(scope, 'chat-0'));
      expect(controller.current!.chat!.reviewNotices, isEmpty);
    },
  );
}
