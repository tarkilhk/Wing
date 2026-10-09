import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/notification_focus.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/recent_conversation.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/screens/workspace_overview_content.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/app_drawer.dart';
import 'package:wing/core/widgets/chat_notice_activity_scope.dart';
import 'package:wing/core/widgets/recent_conversations/conversation_gestures.dart';
import 'package:wing/core/widgets/recent_conversations/recent_conversation_switcher.dart';
import 'package:wing/core/widgets/source_code_block.dart';

import '../test/support/profile_browser_fixture.dart';

/// Only gateway responses and incoming journal projections are synthetic.
/// Android dispatches every tested touch through the installed production chat.
class _NativeChats extends ProfileBrowserFixture {
  ProfileSessionKey? failedResume;
  bool deepHistory = false, showCode = false;
  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (var index = 0; index < 3; index++)
      {
        'id': 'chat-$index',
        'title': '$profile task $index',
        'profile': profile,
        'last_active': now - index * 60,
        'unread': false,
      },
  ];
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    if (deepHistory)
      for (var i = 0; i < 20; i++)
        {
          'id': 100 + i,
          'role': i.isEven ? 'user' : 'assistant',
          'content':
              'Saved message $i. Return to this reading position after checking another task. This history belongs to $profile.',
          'timestamp': now - 1000 + i,
        },
    {
      'id': 1,
      'role': 'user',
      'content': 'Keep my normal conversation in place.',
    },
    {
      'id': 2,
      'role': 'tool',
      'tool_name': 'Read project',
      'content': 'Inspect the existing conversation controls.',
    },
    {
      'id': 3,
      'role': 'assistant',
      'timestamp': now - 20,
      'content':
          '${showCode ? '```dart\nfinal value = 42;\n```\n\n' : ''}'
          '## Your conversation\n\nMove between tasks when you need to. '
          'Your draft and reading position stay with this chat.',
    },
  ];
  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) {
        if (method == 'session.resume' &&
            scope == failedResume?.workspace &&
            params['session_id'] == failedResume?.sessionId) {
          throw StateError('Owned QA resume rejection');
        }
        return base.call(method, params);
      },
    );
  }

  int get resumes => calls.where((call) => call.$2 == 'session.resume').length;
}

/// Host receipts are unique and bounded. No gesture is synthesized by Flutter.
Future<void> _native(
  WidgetTester tester,
  String name, {
  List<Map<String, Object?>> actions = const [],
  Map<String, Object?> observation = const {},
  bool capture = true,
}) async {
  final cache = Directory.systemTemp.path;
  final token = '$name-${DateTime.now().microsecondsSinceEpoch}';
  await File('$cache/wing-recents-stage.json').writeAsString(
    jsonEncode({
      'name': name,
      'token': token,
      'actions': actions,
      'observation': observation,
      'capture': capture,
      'devicePixelRatio': tester.view.devicePixelRatio,
    }),
  );
  final ack = File('$cache/wing-recents-ack');
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 40));
    if (await ack.exists() && await ack.readAsString() == token) {
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      return;
    }
  }
  throw StateError('Native Android driver did not complete $name');
}

Map<String, Object?> _touch(
  WidgetTester tester,
  String mode,
  List<(Offset, Offset)> contacts, {
  int milliseconds = 320,
}) => {
  'type': mode,
  'contacts': [
    for (final contact in contacts)
      [contact.$1.dx, contact.$1.dy, contact.$2.dx, contact.$2.dy],
  ],
  'milliseconds': milliseconds,
};

Map<String, Object?> _tap(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsOneWidget);
  final center = tester.getCenter(finder.hitTestable());
  return {'type': 'tap', 'x': center.dx, 'y': center.dy};
}

Rect _chatRect(WidgetTester tester) =>
    tester.getRect(find.byType(RecentConversationSwitcher));

// Select a real admitted transcript row; text, controls and OS edges keep their
// production hit-test policy. Large native font settings can move these rows.
double _gestureRow(WidgetTester tester, List<double> fractions) {
  final rect = tester.getRect(find.byType(ProfileTranscript));
  for (var y = rect.top + 24; y < rect.bottom - 24; y += 12) {
    if (fractions.every(
      (fraction) => admitsConversationGesture(
        PointerDownEvent(
          position: Offset(rect.width * fraction, y),
          viewId: tester.view.viewId,
        ),
      ),
    )) {
      return y;
    }
  }
  throw StateError('No admitted transcript row');
}

Offset _blank(WidgetTester tester) {
  final rect = tester.getRect(find.byType(ProfileTranscript));
  for (var y = rect.top + 24; y < rect.bottom - 24; y += 12) {
    for (final x in [rect.width * .6, rect.width * .4, 28.0, rect.width - 28]) {
      final point = Offset(x, y);
      if (admitsConversationGesture(
        PointerDownEvent(position: point, viewId: tester.view.viewId),
        textAllowed: false,
      )) {
        return point;
      }
    }
  }
  throw StateError('No admitted blank transcript space');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const enabled = bool.fromEnvironment('RECENTS_NATIVE_INPUT');
  const codeOnly = bool.fromEnvironment('RECENTS_CODE_ONLY');
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final large in [false, true]) {
      testWidgets(
        'native Recents ${brightness.name} ${large ? 'large' : 'normal'}${codeOnly ? ' code' : ''}',
        (tester) async {
          final prefix = '${brightness.name}-${large ? 'large' : 'normal'}';
          await _native(
            tester,
            '$prefix-configure',
            actions: [
              {'type': 'configure', 'large': large},
            ],
            capture: false,
          );
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final preferences = AppPreferences(prefs);
          final host = _NativeChats()..showCode = codeOnly;
          final readReceipts = <String>[];
          final controller = ProfileWorkspaceController(
            access: ConnectionAccess(
              connection: SavedConnection(
                id: 'native-recents',
                label: 'Recents QA',
                host: 'unused',
                port: 1,
                apiKey: '',
              ),
              dashboardOAuth: null,
            ),
            connectionIdentity: 'native-recents',
            preferences: prefs,
            appPreferences: preferences,
            gatewayFactory: host.gateway,
            onNotificationRead: (_, identity) async =>
                readReceipts.add(identity),
          );
          final activity = ValueNotifier<ChatNoticeActivity?>(null);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            preferences.dispose();
            activity.dispose();
          });
          await controller.initialize();
          await controller.refreshRecents();
          bool accessible = false, reduced = false;
          late StateSetter presentation;
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => StatefulBuilder(
                builder: (context, setState) {
                  presentation = setState;
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      accessibleNavigation: accessible,
                      disableAnimations: reduced,
                    ),
                    child: ChatNoticeActivityScope(
                      activity: activity,
                      child: child!,
                    ),
                  );
                },
              ),
              home: ProfileWorkspaceScreen(
                controller: controller,
                initialDestination: AppDestination.activity,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 500));
          await _native(
            tester,
            '$prefix-enter',
            actions: [
              _tap(
                tester,
                find.byKey(const ValueKey('activity-personal-chat-0')),
              ),
            ],
          );
          expect(find.byType(RecentConversationSwitcher), findsOneWidget);
          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byType(ProfileWorkspaceScreen)),
            ).scale(16),
            large ? greaterThan(25) : closeTo(16, 1),
          );
          final first = controller.current!.chat!;
          final layer = tester.widget<RecentConversationSwitcher>(
            find.byType(RecentConversationSwitcher),
          );
          final visit = layer.session;
          final ring = visit.entries;
          final origin = visit.selectedIndex;
          final rect = _chatRect(tester);
          final w = rect.width;
          final mid = Offset(w / 2, rect.center.dy - 28);
          Future<void> closeDrawerAndReturn() async {
            final scaffold = tester.state<ScaffoldState>(
              find
                  .ancestor(
                    of: find.byType(ProfileTranscript),
                    matching: find.byType(Scaffold),
                  )
                  .first,
            );
            if (scaffold.isDrawerOpen) {
              await _native(
                tester,
                '$prefix-drawer-back',
                actions: [
                  {'type': 'back'},
                ],
              );
              expect(scaffold.isDrawerOpen, isFalse);
              expect(find.byType(RecentConversationSwitcher), findsOneWidget);
            }
            await _native(
              tester,
              '$prefix-recents-back',
              actions: [
                {'type': 'back'},
              ],
            );
            expect(find.byType(WorkspaceActivityContent), findsOneWidget);
            expect(
              tester
                  .widget<FilterChip>(find.widgetWithText(FilterChip, 'All'))
                  .selected,
              isTrue,
            );
          }

          if (codeOnly) {
            if (!large) {
              final code = tester.getRect(
                find.byType(SourceCodeBlock).hitTestable(),
              );
              await _native(
                tester,
                '$prefix-code-exclusion',
                actions: [
                  _touch(tester, 'two', [
                    (
                      Offset(code.left + 28, code.center.dy),
                      Offset(code.left + 70, code.center.dy),
                    ),
                    (
                      Offset(code.right - 28, code.center.dy),
                      Offset(code.right - 70, code.center.dy),
                    ),
                  ]),
                ],
              );
              expect(controller.current!.chat!.key, first.key);
              expect(find.text('Swipe to browse · tap to open'), findsNothing);
              await _native(
                tester,
                '$prefix-copy-code',
                actions: [_tap(tester, find.byTooltip('Copy code'))],
              );
              expect(
                (await Clipboard.getData('text/plain'))?.text,
                contains('final value = 42;'),
              );
            }
            final edgeY =
                tester.getRect(find.byType(ProfileTranscript)).top + 30;
            await _native(
              tester,
              '$prefix-code-system-edge',
              actions: [
                _touch(tester, 'two', [
                  (Offset(8, edgeY), Offset(68, edgeY)),
                  (Offset(20, edgeY), Offset(80, edgeY)),
                ]),
              ],
            );
            expect(controller.current!.chat!.key, first.key);
            expect(find.text('Swipe to browse · tap to open'), findsNothing);
            await closeDrawerAndReturn();
            expect(tester.takeException(), isNull);
            await _native(
              tester,
              '$prefix-code-complete',
              observation: {
                'scope': large
                    ? 'Android edge/drawer Back'
                    : 'code-copy/exclusion and Android edge/drawer Back',
                'modelSubmissions': 0,
              },
            );
            return;
          }
          Future<void> swipe(
            String name, {
            bool right = false,
            String type = 'two',
          }) async {
            final y = _gestureRow(tester, right ? [.16, .38] : [.62, .84]);
            final start = right ? [.16, .38] : [.62, .84];
            final dx = w * (right ? .5 : -.5);
            await _native(
              tester,
              '$prefix-$name',
              actions: [
                _touch(tester, type, [
                  for (final x in start)
                    (Offset(w * x, y), Offset(w * x + dx, y)),
                ]),
              ],
            );
          }

          Future<void> menu(String label) async {
            await _native(
              tester,
              '$prefix-menu-$label',
              actions: [_tap(tester, find.byTooltip('Chat actions'))],
              capture: false,
            );
            await _native(
              tester,
              '$prefix-action-$label',
              actions: [_tap(tester, find.text(label))],
            );
          }

          Future<void> pinch(String name) async {
            final y = _gestureRow(tester, [.24, .76]);
            await _native(
              tester,
              '$prefix-$name',
              actions: [
                _touch(tester, 'two', [
                  (Offset(w * .24, y), Offset(w * .41, y)),
                  (Offset(w * .76, y), Offset(w * .59, y)),
                ]),
              ],
            );
            expect(find.text('Swipe to browse · tap to open'), findsOneWidget);
            expect(controller.visible, isFalse);
          }

          final file = File('${Directory.systemTemp.path}/recents-qa.txt');
          await file.writeAsString(
            'Owned emulator attachment. Never submitted.',
          );
          addTearDown(() async {
            if (await file.exists()) await file.delete();
          });
          await first.composer.addFile(file.path, 'recents-qa.txt');
          await controller.updateDraft(first, 'Draft_');
          await tester.pumpAndSettle();
          await _native(
            tester,
            '$prefix-keyboard',
            actions: [
              _tap(tester, find.byKey(const Key('profile-message-composer'))),
              {'type': 'text', 'text': 'Native'},
            ],
          );
          expect(first.composer.observation.displayedText, contains('Native'));
          expect(tester.view.viewInsets.bottom, greaterThan(0));
          final draft = first.composer.observation.displayedText;
          final attachments = first.composer.observation.attachments
              .map((a) => a.id)
              .toList();
          await _native(
            tester,
            '$prefix-keyboard-back',
            actions: [
              {'type': 'back'},
            ],
          );
          expect(tester.view.viewInsets.bottom, 0);
          expect(controller.current!.chat!.key, first.key);
          await swipe('slide-next');
          expect(
            controller.current!.chat!.key,
            ring[(origin + 1) % ring.length].key,
          );
          await swipe('slide-previous', right: true);
          expect(controller.current!.chat!.key, first.key);
          expect(first.composer.observation.displayedText, draft);
          expect(
            first.composer.observation.attachments.map((a) => a.id),
            attachments,
          );
          await swipe('interrupted-return', type: 'interrupt');
          expect(
            controller.current!.chat!.key,
            ring[(origin + 1) % ring.length].key,
          );
          await swipe('return-after-interruption', right: true);
          final resumes = host.resumes;
          await pinch('pinch-persistent');
          await _native(
            tester,
            '$prefix-browse',
            actions: [
              _touch(tester, 'one', [
                (Offset(w * .8, mid.dy), Offset(w * .2, mid.dy)),
              ]),
            ],
          );
          expect(controller.current!.chat!.key, first.key);
          expect(
            host.resumes,
            resumes,
            reason: 'Browsing has no resume authority',
          );
          await _native(
            tester,
            '$prefix-open-center',
            actions: [
              {'type': 'tap', 'x': mid.dx, 'y': mid.dy},
            ],
          );
          expect(
            controller.current!.chat!.key,
            ring[(origin + 1) % ring.length].key,
          );
          expect(find.text('Swipe to browse · tap to open'), findsNothing);
          await swipe('return-from-center', right: true);
          await pinch('pinch-peek');
          await _native(
            tester,
            '$prefix-open-peek',
            actions: [
              {'type': 'tap', 'x': w - 12, 'y': mid.dy},
            ],
          );
          expect(
            controller.current!.chat!.key,
            ring[(origin + 1) % ring.length].key,
          );
          await swipe('return-from-peek', right: true);
          await pinch('circular-stack');
          final beforeLaps = host.resumes;
          await _native(
            tester,
            '$prefix-full-lap',
            actions: [
              for (var i = 0; i < ring.length; i++) ...[
                _touch(tester, 'one', [
                  (Offset(w * .8, mid.dy), Offset(w * .2, mid.dy)),
                ]),
                {'type': 'wait', 'milliseconds': 850},
              ],
            ],
          );
          expect(host.resumes, beforeLaps);
          first.reading.recordNotificationResult(
            const NotificationFocus('answer', '3'),
          );
          await controller.refreshHistory(first);
          await tester.pumpAndSettle();
          expect(
            readReceipts,
            isEmpty,
            reason: 'A hidden chat/card must not acknowledge a reply',
          );
          await _native(
            tester,
            '$prefix-stack-back',
            actions: [
              {'type': 'back'},
            ],
          );
          expect(controller.current!.chat!.key, first.key);
          expect(find.text('Swipe to browse · tap to open'), findsNothing);
          expect(controller.visible, isTrue);
          expect(
            tester.view.viewInsets.bottom,
            0,
            reason:
                'Stack Back must preserve a keyboard already hidden with Android Back',
          );
          expect(readReceipts, ['answer:3']);
          host.failedResume = ring[(origin + 1) % ring.length].key;
          await swipe('failed-selection');
          expect(controller.current!.chat!.key, first.key);
          expect(
            find.text('Could not open this conversation. Try again.'),
            findsOneWidget,
          );
          host.failedResume = null;
          ScaffoldMessenger.of(
            tester.element(find.byType(ProfileWorkspaceScreen)),
          ).hideCurrentSnackBar();
          await tester.pumpAndSettle();
          var sequence = 0;
          for (final kind in ConversationActivityKind.values) {
            activity.value = ChatNoticeActivity(
              key: ring[(origin + 1) % ring.length].key,
              kind: kind,
              identity: 'native-${kind.name}',
              sequence: ++sequence,
            );
            await tester.pump(const Duration(milliseconds: 220));
            expect(
              find.byKey(const Key('recent-conversation-nudge')),
              findsOneWidget,
            );
            await _native(
              tester,
              '$prefix-nudge-${kind.name}',
              actions: [
                {'type': 'wait', 'milliseconds': 60},
              ],
            );
            await tester.pump(const Duration(milliseconds: 800));
          }
          await _native(
            tester,
            '$prefix-edit-suppression',
            actions: [
              _tap(tester, find.byKey(const Key('profile-message-composer'))),
            ],
            capture: false,
          );
          activity.value = ChatNoticeActivity(
            key: ring[(origin + 1) % ring.length].key,
            kind: ConversationActivityKind.reply,
            identity: 'editing',
            sequence: ++sequence,
          );
          await tester.pump(const Duration(milliseconds: 350));
          expect(
            find.byKey(const Key('recent-conversation-nudge')),
            findsNothing,
          );
          await _native(
            tester,
            '$prefix-end-editing',
            actions: [
              {'type': 'back'},
            ],
          );
          final blank = _blank(tester);
          final dx = w * (blank.dx > w / 2 ? -.5 : .5);
          await _native(
            tester,
            '$prefix-scrub-commit',
            actions: [
              _touch(tester, 'scrub', [(blank, blank + Offset(dx, 0))]),
            ],
          );
          expect(controller.current!.chat!.key, isNot(first.key));
          await swipe('return-from-scrub', right: dx < 0);
          expect(controller.current!.chat!.key, first.key);
          final cancel = _blank(tester);
          await _native(
            tester,
            '$prefix-scrub-cancel',
            actions: [
              _touch(tester, 'scrub', [
                (cancel, cancel + Offset(w * .3, -100)),
              ]),
            ],
          );
          expect(controller.current!.chat!.key, first.key);
          // Composer is a excluded region even when native touches use two fingers.
          final composer = tester.getRect(
            find.byKey(const Key('profile-message-composer')),
          );
          await _native(
            tester,
            '$prefix-composer-exclusion',
            actions: [
              _touch(tester, 'two', [
                (
                  Offset(composer.left + 30, composer.center.dy),
                  Offset(composer.left + 80, composer.center.dy),
                ),
                (
                  Offset(composer.right - 30, composer.center.dy),
                  Offset(composer.right - 80, composer.center.dy),
                ),
              ]),
            ],
          );
          expect(find.text('Swipe to browse · tap to open'), findsNothing);
          expect(controller.current!.chat!.key, first.key);
          if (tester.view.viewInsets.bottom > 0) {
            await _native(
              tester,
              '$prefix-dismiss-exclusion-keyboard',
              actions: [
                {'type': 'back'},
              ],
            );
          }
          presentation(() => accessible = true);
          await tester.pumpAndSettle();
          final beforeAccessibility = controller.current!.chat!.key;
          await swipe('accessibility-exclusion');
          expect(controller.current!.chat!.key, beforeAccessibility);
          await menu('Choose recent conversation');
          expect(find.byTooltip('Next conversation'), findsOneWidget);
          expect(
            tester.view.viewInsets.bottom,
            0,
            reason:
                'Menu focus restoration must not reopen the hidden composer',
          );
          await _native(
            tester,
            '$prefix-accessible-next',
            actions: [_tap(tester, find.byTooltip('Next conversation'))],
          );
          expect(tester.view.viewInsets.bottom, 0);
          await _native(
            tester,
            '$prefix-accessible-open',
            actions: [_tap(tester, find.byTooltip('Open conversation'))],
          );
          expect(controller.current!.chat!.key, isNot(beforeAccessibility));
          presentation(() {
            accessible = false;
            reduced = true;
          });
          await tester.pumpAndSettle();
          await pinch('reduced-stack');
          await _native(
            tester,
            '$prefix-reduced-back',
            actions: [
              {'type': 'back'},
            ],
          );
          expect(find.text('Swipe to browse · tap to open'), findsNothing);
          presentation(() => reduced = false);
          await tester.pumpAndSettle();
          if (!large) {
            final target = List.generate(ring.length, (i) => i).firstWhere(
              (i) =>
                  ring[i].key.workspace !=
                  controller.current!.chat!.key.workspace,
            );
            Future<void> browseToTarget() async {
              await menu('Choose recent conversation');
              final focusedTarget = find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label ==
                        '${ring[target].title}, conversation ${target + 1} of ${ring.length}',
              );
              // Native fling velocity can browse more than one card. Observe the
              // focused card instead of assuming a fixed number of swipes.
              for (var step = 0; step < ring.length; step++) {
                if (focusedTarget.evaluate().isNotEmpty) break;
                await _native(
                  tester,
                  '$prefix-cross-profile-browse-$step',
                  actions: [
                    _touch(tester, 'one', [
                      (Offset(w * .8, mid.dy), Offset(w * .2, mid.dy)),
                    ], milliseconds: 600),
                    {'type': 'wait', 'milliseconds': 850},
                  ],
                );
              }
              expect(focusedTarget, findsOneWidget);
            }

            final beforeCrossProfile = controller.current!.chat!.key;
            host.failedResume = ring[target].key;
            await browseToTarget();
            await _native(
              tester,
              '$prefix-cross-profile-rejected',
              actions: [
                {'type': 'tap', 'x': mid.dx, 'y': mid.dy},
              ],
            );
            expect(controller.current!.chat!.key, beforeCrossProfile);
            expect(
              find.text('Could not open this conversation. Try again.'),
              findsOneWidget,
            );
            await _native(
              tester,
              '$prefix-cross-profile-recovery-back',
              actions: [
                {'type': 'back'},
              ],
            );
            host.failedResume = null;
            await browseToTarget();
            await _native(
              tester,
              '$prefix-cross-profile-open',
              actions: [
                {'type': 'tap', 'x': mid.dx, 'y': mid.dy},
              ],
            );
            expect(controller.current!.chat!.key, ring[target].key);
            await _native(tester, '$prefix-cross-profile-settled');
            for (
              var i = 0;
              i < ring.length && visit.selectedIndex != origin;
              i++
            ) {
              await swipe('cross-profile-return-$i', right: true);
            }
            expect(controller.current!.chat!.key, first.key);
            host.deepHistory = true;
            await controller.refreshHistory(first);
            await tester.pumpAndSettle();
            final transcript = tester.getRect(find.byType(ProfileTranscript));
            await _native(
              tester,
              '$prefix-ordinary-scroll',
              actions: [
                _touch(tester, 'one', [
                  (
                    Offset(w / 2, transcript.top + 60),
                    Offset(w / 2, transcript.top + 260),
                  ),
                ], milliseconds: 500),
              ],
            );
            final offset = first.reading.historyScrollOffset;
            expect(offset, greaterThan(20));
            await swipe('reading-switch');
            await swipe('reading-return', right: true);
            expect(first.reading.historyScrollOffset, closeTo(offset, 3));
            expect(first.composer.observation.displayedText, draft);
            expect(
              first.composer.observation.attachments.map((a) => a.id),
              attachments,
            );
            await _native(tester, '$prefix-reading-restored');
          }
          final beforeEdge = controller.current!.chat!.key;
          final edgeY = tester.getRect(find.byType(ProfileTranscript)).top + 30;
          await _native(
            tester,
            '$prefix-system-edge',
            actions: [
              _touch(tester, 'two', [
                (Offset(8, edgeY), Offset(68, edgeY)),
                (Offset(20, edgeY), Offset(80, edgeY)),
              ]),
            ],
          );
          expect(controller.current!.chat!.key, beforeEdge);
          expect(find.text('Swipe to browse · tap to open'), findsNothing);
          await closeDrawerAndReturn();
          expect(
            host.calls.where((call) => call.$2 == 'prompt.submit'),
            isEmpty,
          );
          await _native(
            tester,
            '$prefix-complete',
            observation: {
              'ringSize': ring.length,
              'resumes': host.resumes,
              'draftRetained':
                  first.composer.observation.displayedText == draft,
              'attachmentRetained': listEquals(
                first.composer.observation.attachments
                    .map((a) => a.id)
                    .toList(),
                attachments,
              ),
              'readReceipts': readReceipts,
              'modelSubmissions': 0,
            },
          );
          expect(tester.takeException(), isNull);
        },
        skip: !enabled,
        timeout: const Timeout(Duration(minutes: 8)),
      );
    }
  }
}
