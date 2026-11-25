import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/profile_skills.dart';
import 'package:wing/core/screens/administration/admin_skills_page.dart';
import 'package:wing/core/services/profile_skills_session.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/screens/administration/admin_operations_page.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';
import 'package:wing/core/widgets/studio_error.dart';

import 'support/administration_fixture.dart';

const _update = {
  'name': 'Research notes',
  'identifier': 'official/research',
  'source': 'official',
};

void main() {
  test(
    'update decoding distinguishes reported updates, empty and malformed',
    () {
      final rows = HubSkillUpdate.decode({
        'updates': [_update],
      });
      expect(rows.single.name, 'Research notes');
      expect(rows.single.identifier, 'official/research');
      expect(() => rows.clear(), throwsUnsupportedError);
      expect(HubSkillUpdate.decode({'updates': []}), isEmpty);
      for (final response in <Map<String, dynamic>>[
        {},
        {'updates': null},
        {
          'updates': [null],
        },
        {
          'updates': [
            {'name': 'Research'},
          ],
        },
        {
          'updates': [
            {..._update, 'source': 5},
          ],
        },
      ]) {
        expect(() => HubSkillUpdate.decode(response), throwsFormatException);
      }
    },
  );

  test(
    'quiet held check coalesces and explicit join leaves catalog usable',
    () async {
      final fixture = AdministrationFixture()..hubUpdates = [_update];
      final gate = fixture.hubUpdatesGate = Completer<void>();
      final session = ProfileSkillsSession.hub(
        fixture.server.profile('personal'),
      );
      addTearDown(() {
        session.dispose();
        fixture.server.close();
      });
      await session.refresh();
      final automatic = session.checkUpdates(automatic: true);
      expect(session.state.hubUpdates.pending, isTrue);
      expect(session.state.hubUpdates.showingProgress, isFalse);
      expect(session.state.canMutate, isTrue);
      final explicit = session.checkUpdates();
      expect(explicit, same(automatic));
      expect(session.checkUpdates(), same(explicit));
      expect(session.state.hubUpdates.showingProgress, isTrue);
      await session.refresh(query: 'research');
      expect(session.state.catalog.single.name, 'Research catalog skill');
      expect(session.state.canMutate, isTrue);
      gate.complete();
      await explicit;
      expect(fixture.hubUpdateChecks, 1);
      expect(session.state.hubUpdates.updates!.single.source, 'official');
      expect(session.state.hubUpdates.showingProgress, isFalse);
      expect(
        fixture.requests.where((r) => r.$2 == 'skills/hub/updates').single.$3,
        {'profile': 'personal'},
      );
    },
  );

  test(
    'availability failure and recovery do not change catalog admission',
    () async {
      final fixture = AdministrationFixture()..failHubUpdates = true;
      final session = ProfileSkillsSession.hub(
        fixture.server.profile('personal'),
      );
      addTearDown(() {
        session.dispose();
        fixture.server.close();
      });
      await session.refresh();
      await session.checkUpdates();
      expect(session.state.error, isNull);
      expect(
        session.state.hubUpdates.error,
        contains('Hub update check failed'),
      );
      expect(session.state.canMutate, isTrue);
      fixture.failHubUpdates = false;
      await session.checkUpdates();
      expect(session.state.hubUpdates.error, isNull);
      expect(session.state.hubUpdates.updates, isEmpty);
      fixture.failHubCatalog = true;
      await session.refresh();
      fixture.hubUpdates = [_update];
      await session.checkUpdates();
      expect(session.state.error, isNotNull);
      expect(session.state.hubUpdates.updates!.single.name, 'Research notes');
    },
  );

  test(
    'retired same-profile connection cannot replace a new observation',
    () async {
      final old = AdministrationFixture('old connection')
        ..hubUpdates = [_update];
      final gate = old.hubUpdatesGate = Completer<void>();
      final replacement = AdministrationFixture('new connection');
      final first = ProfileSkillsSession.hub(old.server.profile('personal'));
      final second = ProfileSkillsSession.hub(
        replacement.server.profile('personal'),
      );
      final pending = first.checkUpdates();
      var oldNotifications = 0;
      first.addListener(() => oldNotifications++);
      first.dispose();
      await second.checkUpdates();
      gate.complete();
      await pending;
      expect(second.state.hubUpdates.updates, isEmpty);
      expect(first.state.hubUpdates.updates, isNull);
      expect(oldNotifications, 0);
      second.dispose();
      old.server.close();
      replacement.server.close();
    },
  );

  test(
    'cancel preserves pending and known availability without dispatch',
    () async {
      final fixture = AdministrationFixture()..hubUpdates = [_update];
      final session = ProfileSkillsSession.hub(
        fixture.server.profile('personal'),
      );
      addTearDown(() {
        session.dispose();
        fixture.server.close();
      });
      await session.refresh();
      await session.checkUpdates();
      final gate = fixture.hubUpdatesGate = Completer<void>();
      final pending = session.checkUpdates();
      await session.update(
        confirm: () async => false,
        showResult: (_) async => fail('No result'),
      );
      expect(session.state.hubUpdates.updates!.single.name, 'Research notes');
      expect(session.state.hubUpdates.pending, isTrue);
      expect(fixture.hubUpdatePosts, isEmpty);
      gate.complete();
      await pending;
    },
  );

  test(
    'update dispatch retires old check and rechecks despite failed catalog readback',
    () async {
      final fixture = AdministrationFixture()..hubUpdates = [_update];
      final session = ProfileSkillsSession.hub(
        fixture.server.profile('personal'),
      );
      addTearDown(() {
        session.dispose();
        fixture.server.close();
      });
      await session.refresh();
      await session.checkUpdates();
      final oldResponse = Completer<Map<String, dynamic>>();
      var checks = 0;
      fixture.override = (method, path, query, body) async {
        if (path == 'skills/hub/updates') {
          checks++;
          return checks == 1 ? oldResponse.future : {'updates': []};
        }
        if (path == 'profiles/active') {
          return {'current': 'personal', 'active': 'personal'};
        }
        if (path == 'profiles') {
          return {
            'profiles': [
              {'name': 'personal'},
            ],
          };
        }
        if (path == 'skills/hub/update') {
          expect(method, 'POST');
          expect(query, {'profile': 'personal'});
          expect(body, {'profile': 'personal'});
          expect(session.state.hubUpdates.updates, isNull);
          expect(session.state.hubUpdates.pending, isFalse);
          return {'ok': true, 'name': 'skills-update', 'pid': 907};
        }
        if (path == 'skills') return {'data': []};
        if (path == 'skills/hub/official') {
          throw TimeoutException('Catalog unavailable');
        }
        throw StateError('Unexpected $path');
      };
      final oldCheck = session.checkUpdates();
      var shown = false;
      await session.update(
        confirm: () async => true,
        showResult: (result) async {
          shown = true;
          expect(result.action.name, 'skills-update');
          expect(session.state.hubUpdates.updates, isNull);
          // A receipt alone must not advertise completed updates.
        },
      );
      expect(shown, isTrue, reason: session.state.error);
      expect(session.state.error, isNotNull);
      expect(checks, 2);
      expect(session.state.hubUpdates.updates, isEmpty);
      oldResponse.complete({
        'updates': [_update],
      });
      await oldCheck;
      expect(session.state.hubUpdates.updates, isEmpty);
    },
  );

  test('profile refusal preserves availability and a pending check', () async {
    final fixture = AdministrationFixture()..hubUpdates = [_update];
    final session = ProfileSkillsSession.hub(
      fixture.server.profile('personal'),
    );
    await session.refresh();
    await session.checkUpdates();
    final gate = fixture.hubUpdatesGate = Completer<void>();
    final pending = session.checkUpdates();
    fixture.configs.remove('personal');
    await session.update(
      confirm: () async => true,
      showResult: (_) async => fail('No dispatch'),
    );
    expect(fixture.hubUpdatePosts, isEmpty);
    expect(session.state.hubUpdates.updates!.single.name, 'Research notes');
    expect(session.state.hubUpdates.pending, isTrue);
    gate.complete();
    await pending;
    session.dispose();
    fixture.server.close();
  });

  test(
    'held availability retains the connection lease after route departure',
    () async {
      final fixture = AdministrationFixture();
      final gate = fixture.hubUpdatesGate = Completer<void>();
      var closed = false;
      final server = AdministrationRepository(
        connectionId: 'lease',
        connectionIdentity: 'lease-endpoint',
        connectionLabel: 'Lease',
        request: fixture.send,
        gateway: fixture.server.gateway,
        ownedMutation: fixture.server.ownedMutation,
        settingsWrite: fixture.server.settingsWrite,
        close: () => closed = true,
      );
      final session = ProfileSkillsSession.hub(server.profile('personal'));
      final pending = session.checkUpdates();
      session.dispose();
      server.close();
      expect(closed, isFalse);
      gate.complete();
      await pending;
      expect(closed, isTrue);
      fixture.server.close();
    },
  );

  test('departing during update result prevents follow-up checks', () async {
    final fixture = AdministrationFixture()..hubUpdates = [_update];
    final session = ProfileSkillsSession.hub(
      fixture.server.profile('personal'),
    );
    await session.refresh();
    await session.checkUpdates();
    final entered = Completer<void>(), leave = Completer<void>();
    final update = session.update(
      confirm: () async => true,
      showResult: (_) async {
        entered.complete();
        await leave.future;
      },
    );
    await entered.future;
    session.dispose();
    leave.complete();
    await update;
    expect(fixture.hubUpdateChecks, 1);
    expect(fixture.hubUpdatePosts, [
      {'profile': 'personal'},
    ]);
    fixture.server.close();
  });

  test(
    'queued automatic refresh retains quiet intent after confirmation',
    () async {
      final fixture = AdministrationFixture();
      final session = ProfileSkillsSession.hub(
        fixture.server.profile('personal'),
      );
      await session.refresh();
      final observed = <bool>[];
      session.addListener(() {
        if (session.state.phase == SkillsPhase.reading) {
          observed.add(session.state.showingReadProgress);
        }
      });
      await session.update(
        confirm: () async {
          await session.refresh(automatic: true);
          return false;
        },
        showResult: (_) async => fail('No update'),
      );
      expect(observed, [false]);
      expect(fixture.hubUpdatePosts, isEmpty);
      session.dispose();
      fixture.server.close();
    },
  );

  testWidgets(
    'automatic catalog refresh is quiet while explicit search responds immediately',
    (tester) async {
      final fixture = AdministrationFixture();
      late ProfileSkillsSession session;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSkillHubPage(
            createSession: () => session = ProfileSkillsSession.hub(
              fixture.server.profile('personal'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var gate = fixture.hubCatalogGate = Completer<void>();
      final automatic = session.refresh(automatic: true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(StudioLoading), findsNothing);
      expect(find.text('Research catalog skill'), findsOneWidget);
      gate.complete();
      await automatic;
      await tester.pumpAndSettle();
      gate = fixture.hubCatalogGate = Completer<void>();
      await tester.enterText(find.byType(TextField), 'research');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(find.byType(StudioLoading), findsOneWidget);
      expect(find.text('Research catalog skill'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(StudioLoading), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.server.close();
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Hub check feedback and retry preserve catalog $brightness $scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = AdministrationFixture()..hubUpdates = [_update];
          var gate = fixture.hubUpdatesGate = Completer<void>();
          late ProfileSkillsSession session;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: AdminSkillHubPage(
                createSession: () => session = ProfileSkillsSession.hub(
                  fixture.server.profile('personal'),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(StudioLoading), findsNothing);
          final frame = tester.getRect(
            find.byKey(const ValueKey('hub-update-status')),
          );
          final catalog = tester.getRect(
            find.byKey(const ValueKey('hub-catalog')),
          );
          expect(find.text('Research catalog skill'), findsOneWidget);
          expect(
            tester
                .widget<ListTile>(
                  find.widgetWithText(ListTile, 'Research catalog skill'),
                )
                .onTap,
            isNotNull,
          );
          await tester.tap(find.byTooltip('Check Hub skill updates'));
          await tester.pump();
          await tester.pump();
          expect(find.byType(StudioLoading), findsOneWidget);
          expect(session.state.canMutate, isTrue);
          expect(
            tester.getRect(find.byKey(const ValueKey('hub-update-status'))),
            frame,
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('hub-catalog'))),
            catalog,
          );
          fixture.failHubUpdates = true;
          gate.complete();
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(seconds: 1));
          }
          await tester.pumpAndSettle();
          expect(find.byType(StudioLoading), findsNothing);
          expect(
            find.textContaining('Hub update check failed'),
            findsOneWidget,
          );
          final errorFrame = tester.getRect(
            find.byKey(const ValueKey('hub-update-status')),
          );
          final errorCard = tester.getRect(
            find.descendant(
              of: find.byKey(const ValueKey('hub-update-status')),
              matching: find.byType(StudioError),
            ),
          );
          expect(errorFrame.contains(errorCard.topLeft), isTrue);
          expect(
            errorFrame.contains(errorCard.bottomRight - const Offset(.1, .1)),
            isTrue,
            reason:
                'The complete shared error card must fit; a found text node can still be clipped.',
          );
          // The outer page can reveal the complete error even with the host's
          // unusually wide Ahem font at 200%; the status itself must not clip it.
          if (errorCard.bottom > 800) {
            await tester.drag(find.byType(ListView), const Offset(0, -600));
            await tester.pumpAndSettle();
            final revealed = tester.getRect(find.byType(StudioError));
            expect(revealed.bottom, lessThanOrEqualTo(800));
            await tester.drag(find.byType(ListView), const Offset(0, 1000));
            await tester.pumpAndSettle();
          }
          gate = fixture.hubUpdatesGate = Completer<void>();
          fixture.failHubUpdates = false;
          await tester.tap(find.byTooltip('Retry Hub update check'));
          await tester.pump();
          await tester.pump();
          expect(find.byType(StudioLoading), findsOneWidget);
          expect(
            tester.getRect(find.byKey(const ValueKey('hub-update-status'))),
            errorFrame,
            reason: 'Held retry retains the full error layout.',
          );
          gate.complete();
          await tester.pumpAndSettle();
          expect(find.text('Research notes'), findsOneWidget);
          fixture.hubUpdates = [
            for (var index = 0; index < 20; index++)
              {..._update, 'name': 'Reported update $index'},
          ];
          await tester.tap(find.byTooltip('Check Hub skill updates'));
          await tester.pumpAndSettle();
          final nameList = find.descendant(
            of: find.byKey(const ValueKey('hub-update-status')),
            matching: find.byType(Scrollable),
          );
          final scrollbar = tester.widget<Scrollbar>(
            find.descendant(
              of: find.byKey(const ValueKey('hub-update-status')),
              matching: find.byType(Scrollbar),
            ),
          );
          expect(scrollbar.thumbVisibility, isTrue);
          await tester.scrollUntilVisible(
            find.text('Reported update 19'),
            200,
            scrollable: nameList,
          );
          expect(find.text('Reported update 19').hitTestable(), findsOneWidget);
          fixture.hubUpdates = [];
          await tester.tap(find.byTooltip('Check Hub skill updates'));
          await tester.pumpAndSettle();
          expect(find.text('No Hub skill updates reported'), findsOneWidget);
          expect(find.textContaining('up to date'), findsNothing);
          await tester.tap(find.byTooltip('Update installed Hub skills'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.byTooltip('Update skills').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Cancel'));
          await tester.pumpAndSettle();
          expect(fixture.hubUpdatePosts, isEmpty);
          // A visible search input stays usable when the native keyboard shrinks
          // the page; the Android journey establishes a real positive IME inset.
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(TextField));
          await tester.enterText(find.byType(TextField), 'research');
          await tester.pump();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding();
          tester.binding.focusManager.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          final dispatch = fixture.hubUpdateGate = Completer<void>();
          await tester.ensureVisible(
            find.byTooltip('Update installed Hub skills'),
          );
          await tester.tap(find.byTooltip('Update installed Hub skills'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Update skills'));
          await tester.pumpAndSettle();
          expect(fixture.hubUpdatePosts, [
            {'profile': 'personal'},
          ]);
          expect(find.byType(StudioLoading), findsOneWidget);
          dispatch.complete();
          await tester.pumpAndSettle();
          expect(find.byType(AdminActionPage), findsOneWidget);
          final readback = fixture.hubLibraryGate = Completer<void>();
          gate = fixture.hubUpdatesGate = Completer<void>();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(session.state.phase, SkillsPhase.result);
          expect(find.byType(StudioLoading), findsOneWidget);
          readback.complete();
          await tester.pumpAndSettle();
          expect(session.state.phase, SkillsPhase.idle);
          expect(session.state.hubUpdates.showingProgress, isTrue);
          expect(find.byType(StudioLoading), findsOneWidget);
          gate.complete();
          await tester.pumpAndSettle();
          expect(find.byType(StudioLoading), findsNothing);
          gate = fixture.hubUpdatesGate = Completer<void>();
          await tester.tap(find.byTooltip('Check Hub skill updates'));
          await tester.pump();
          await tester.pump();
          expect(find.byType(StudioLoading), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          gate.complete();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          fixture.server.close();
        },
      );
    }
  }
}
