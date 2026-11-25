import 'support/wing_client_identity_fixture.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:wing/core/widgets/source_code_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/bot_deliveries_panel.dart';
import 'package:wing/core/widgets/compact_activity_row.dart';
import 'package:wing/core/widgets/studio_loading.dart';
import 'package:wing/core/widgets/studio_error.dart';
import 'package:wing/core/widgets/profile_background_work_panel.dart';
import 'package:wing/core/widgets/profile_live_work_dock.dart';
import 'support/bots_fixture.dart';
import 'support/form_family_capture.dart';
import 'support/profile_browser_fixture.dart';
import 'helpers/pump_markdown_widget.dart';
import 'bot_deliveries_test.dart' show deliveryRow;

class _Browser extends ProfileBrowserFixture {
  Completer<void>? processGate;
  bool processFailure = false;
  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) => [
    {'id': 1, 'role': 'user', 'content': 'Review the release'},
    {
      'id': 2,
      'role': 'assistant',
      'content': 'Saved $profile teammate conversation',
    },
  ];
  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      loadClientIdentity: loadTestWingClientIdentity,
      scope: scope,
      discover: base.discover,
      get: base.read,
      rpc: (method, params) async {
        if (method == 'process.list') {
          calls.add((scope.profileName, method, params));
          await processGate?.future;
          if (processFailure) throw StateError('Process read failed');
          return {
            'processes': [
              {
                'session_id': 'build-process',
                'command': 'dart run release.dart',
                'status': 'running',
                'pid': 4242,
              },
            ],
          };
        }
        return base.call(method, params);
      },
    );
  }
}

void main() {
  setUpAll(() async {
    await loadFormFamilyFonts();
    const mono = String.fromEnvironment('CAPTURE_MONO_FONT');
    if (mono.isNotEmpty) {
      await (FontLoader(
        'monospace',
      )..addFont(File(mono).readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'teammate Background keeps quiet polls, combined pending and exact target ${brightness.name} $scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({});
          final preferences = await SharedPreferences.getInstance();
          final app = AppPreferences(preferences);
          final browser = _Browser();
          for (final name in ['personal', 'work']) {
            browser.hiddenSessions[name] = [
              {
                'id': '$name-root',
                'title': 'Bot Chat',
                'profile': name,
                'hidden': true,
                'last_active': browser.now,
              },
              {
                'id': '$name-tip',
                'title': 'Compressed teammate',
                'profile': name,
                'hidden': true,
                'last_active': browser.now,
              },
              {
                'id': '$name-twin',
                'title': 'Bot Chat',
                'profile': name,
                'last_active': browser.now,
              },
            ];
            browser.compressionTips['$name-root'] = '$name-tip';
          }
          final controller = ProfileWorkspaceController(
            connectionIdentity: 'instance-1',
            access: ConnectionAccess(
              connection: SavedConnection(
                id: 'host',
                label: 'Home server',
                host: 'localhost',
                port: 1,
                apiKey: '',
              ),
              dashboardOAuth: null,
            ),
            preferences: preferences,
            appPreferences: app,
            gatewayFactory: browser.gateway,
          );
          await controller.initialize();
          await controller.openSession(
            ProfileSessionKey(controller.current!.scope, 'personal-tip'),
          );
          final fixture = BotsFixture();
          fixture.profiles
            ..clear()
            ..addAll([
              for (final name in ['personal', 'work'])
                {
                  ...BotsFixture.profile(
                    name,
                    name == 'personal' ? 'Release lead' : 'Release reviewer',
                  ),
                  'canonical_session': {
                    'id': '$name-root',
                    'resolved_id': '$name-tip',
                  },
                },
            ]);
          var deliveryReads = 0;
          var fail = false;
          var recipientRows = <Map<String, dynamic>>[];
          var rows = [deliveryRow(target: 'work')];
          Completer<Map<String, dynamic>?>? deliveryGate, rosterGate;
          fixture.readHook = (profile, method, params) async {
            if (method == 'profiles.list' && rosterGate != null) {
              return rosterGate.future;
            }
            if (method != 'bot_delivery.list') return null;
            deliveryReads++;
            if (deliveryGate != null) return deliveryGate.future;
            if (fail) throw StateError('Storage unavailable');
            return {
              'sender': profile,
              'deliveries': profile == 'personal' ? rows : recipientRows,
            };
          };
          var sources = [fixture.repository];
          var failSources = false;
          var rosterClock = DateTime(2026, 11, 25);
          final bots = BotsSession((_) async {
            if (failSources) throw StateError('Source refresh failed');
            return sources;
          }, now: () => rosterClock);
          await tester.pumpWidget(
            RepaintBoundary(
              key: formFamilyCapture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ProfileWorkspaceScreen(
                  controller: controller,
                  createBotsSession: () => bots,
                ),
              ),
            ),
          );
          await tester.settleTranscript();
          await tester.pump(const Duration(milliseconds: 400));
          final composer = find.byKey(const Key('profile-message-composer'));
          await tester.enterText(composer, 'Keep this release draft');
          tester.binding.focusManager.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          expect(deliveryReads, greaterThan(0));
          expect(
            find.text('Saved personal teammate conversation'),
            findsOneWidget,
          );
          // Retained appearance must not become authority for a missing source.
          final retiredRead = deliveryGate = Completer();
          await tester.pump(const Duration(seconds: 5));
          failSources = true;
          await bots.refresh();
          expect(
            bots.cachedAppearance(controller.current!.chat!.key),
            isNotNull,
          );
          failSources = false;
          rosterClock = rosterClock.add(const Duration(seconds: 31));
          sources = [];
          await bots.identitiesForProfiles([
            controller.current!.scope,
          ], canRead: () => true);
          await tester.pump();
          expect(
            bots.cachedAppearance(controller.current!.chat!.key),
            isNotNull,
          );
          expect(bots.availableRepository(controller.current!.scope), isNull);
          expect(tester.takeException(), isNull);
          expect(find.byTooltip('Rename chat'), findsNothing);
          expect(find.byTooltip('Bot settings'), findsNothing);
          final retiredCount = deliveryReads;
          await tester.pump(const Duration(seconds: 6));
          expect(deliveryReads, retiredCount);
          await tester.settleTranscript();
          expect(
            find.text('Saved personal teammate conversation'),
            findsOneWidget,
          );
          deliveryGate = null;
          rows = [deliveryRow(target: 'work', state: 'working')];
          sources = [
            BotsRepository(
              scope: fixture.repository.scope,
              instance: fixture.repository.instance,
              groupObservations: fixture.repository.groupObservations,
              read: fixture.read,
              command: fixture.command,
              ownership: fixture.ownership,
            ),
          ];
          await bots.refresh();
          await tester.pump(const Duration(milliseconds: 100));
          retiredRead.complete({
            'sender': 'personal',
            'deliveries': [deliveryRow(target: 'obsolete')],
          });
          await tester.pumpAndSettle();
          final composedPanel =
              (tester
                          .widget<ProfileLiveWorkDock>(
                            find.byType(ProfileLiveWorkDock),
                          )
                          .processes!
                      as Column)
                  .children
                  .whereType<BotDeliveriesPanel>()
                  .single;
          expect(composedPanel.session.state.deliveries.single.target, 'work');
          expect(
            composedPanel.session.state.deliveries.single.status,
            'Working',
          );
          expect(
            composedPanel.session.state.deliveries.any(
              (row) => row.target == 'obsolete',
            ),
            isFalse,
          );
          rows = [deliveryRow(target: 'work')];
          final composerRect = tester.getRect(composer);
          final closedTab = find.byKey(
            const ValueKey(('live-work-tab', 2, false)),
          );
          expect(closedTab, findsOneWidget);
          deliveryGate = Completer();
          await tester.pump(const Duration(seconds: 5));
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.getRect(composer), composerRect);
          browser.processGate = Completer();
          await tester.tap(closedTab);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final pending = find.descendant(
            of: find.byKey(const ValueKey(('live-work-tab', 2, true))),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CircularProgressIndicator &&
                  widget.semanticsLabel == 'Refreshing background work',
            ),
          );
          expect(pending, findsOneWidget);
          expect(find.text('dart run release.dart'), findsOneWidget);
          expect(find.text('@work'), findsOneWidget);
          expect(tester.getRect(composer), composerRect);
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-pending',
          );
          deliveryGate.complete({'sender': 'personal', 'deliveries': rows});
          deliveryGate = null;
          await tester.pump(const Duration(milliseconds: 100));
          expect(pending, findsOneWidget);
          browser.processGate!.complete();
          browser.processGate = null;
          await tester.pumpAndSettle();
          expect(pending, findsNothing);
          final peerRows = tester
              .widgetList<CompactActivityRow>(find.byType(CompactActivityRow))
              .toList();
          expect(peerRows.length, greaterThanOrEqualTo(2));
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-collapsed',
          );
          browser.processFailure = true;
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(controller.current!.chat!.processesError, isNotNull);
          expect(find.text('dart run release.dart'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey(('live-work-tab', 2, true))),
          );
          await tester.pumpAndSettle();
          await tester.tap(closedTab);
          await tester.pumpAndSettle();
          browser.processFailure = false;
          browser.processGate = Completer();
          final processRetry = find.descendant(
            of: find.byType(ProfileProcessPanel),
            matching: find.byTooltip('Retry'),
          );
          await tester.ensureVisible(processRetry);
          await tester.tap(processRetry);
          await tester.pump();
          expect(
            find.descendant(
              of: processRetry,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          browser.processGate!.complete();
          browser.processGate = null;
          await tester.pumpAndSettle();
          expect(controller.current!.chat!.processesError, isNull);
          expect(find.text('dart run release.dart'), findsOneWidget);
          fail = true;
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Teammate deliveries could not be refreshed'),
            findsOneWidget,
          );
          expect(find.text('dart run release.dart'), findsOneWidget);
          expect(find.text('Last received: Needs approval'), findsOneWidget);
          deliveryGate = Completer();
          final retry = find.descendant(
            of: find.byType(BotDeliveriesPanel),
            matching: find.byTooltip('Retry'),
          );
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pump();
          expect(
            tester
                .widget<StudioRetryNotice>(
                  find.descendant(
                    of: find.byType(BotDeliveriesPanel),
                    matching: find.byType(StudioRetryNotice),
                  ),
                )
                .busy,
            isTrue,
          );
          expect(
            find.descendant(
              of: retry,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          fail = false;
          rows = [
            deliveryRow(target: 'work'),
            {
              ...deliveryRow(
                target: 'archive',
                state: 'failed',
                reason: 'unknown_outcome',
              ),
              'delivery_id': 'unknown-delivery',
              'error':
                  'The recipient disconnected after accepting the request. Its outcome could not be confirmed. Inspect the conversation before deciding what to do next. ' *
                  3,
            },
          ];
          deliveryGate.complete({'sender': 'personal', 'deliveries': rows});
          deliveryGate = null;
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Teammate deliveries could not be refreshed'),
            findsNothing,
          );
          expect(
            find.text('The teammate may already have acted. Do not resend.'),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('live-work-handle')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('@archive'));
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-unknown',
          );
          await tester.tap(find.text('@archive'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Error'));
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-error',
          );
          await tester.ensureVisible(find.byTooltip('Expand Raw details'));
          await tester.tap(find.byTooltip('Expand Raw details'));
          await tester.pumpAndSettle();
          final raw = find.byWidgetPredicate(
            (widget) =>
                widget is SourceCodeText &&
                widget.text.contains('unknown-delivery'),
          );
          expect(raw, findsOneWidget);
          await tester.ensureVisible(raw);
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-raw',
          );
          await tester.ensureVisible(find.text('@archive'));
          await tester.tap(find.text('@archive'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('@work'));
          await tester.tap(find.text('@work'));
          await tester.pumpAndSettle();
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-details',
          );
          rosterGate = Completer();
          final open = find.byTooltip('Open teammate chat');
          await tester.ensureVisible(open);
          await tester.tap(open);
          await tester.pump();
          expect(find.byType(BotDeliveriesPanel), findsNothing);
          expect(find.text('@work'), findsOneWidget);
          await tester.pump();
          expect(
            tester
                .widgetList<StudioPageLoading>(find.byType(StudioPageLoading))
                .any(
                  (widget) =>
                      widget.active && widget.label == 'Opening teammate chat',
                ),
            isTrue,
          );
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-opening',
          );
          rosterGate.complete({
            'bot_mode_protocol': true,
            'install_id': 'install-1',
            'profiles': [fixture.profiles.first],
          });
          rosterGate = null;
          await tester.pumpAndSettle();
          expect(
            find.textContaining('no available Bot Chat on Home server'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('@work'), findsOneWidget);
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-target-error',
          );
          expect(
            controller.current!.chat!.key.workspace.profileName,
            'personal',
          );
          rosterGate = Completer();
          await tester.tap(find.byTooltip('Retry'));
          await tester.pump();
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-target-retry',
          );
          final longOpeningError =
              '${'The teammate connection could not be read. ' * 48}'
              'Check the connection before opening this teammate again.';
          rosterGate.completeError(StateError(longOpeningError));
          rosterGate = null;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final errorCopy = find.text(longOpeningError);
          expect(errorCopy, findsOneWidget);
          final errorScroll = find.ancestor(
            of: errorCopy,
            matching: find.byType(Scrollable),
          );
          final scrollState = tester.state<ScrollableState>(errorScroll);
          expect(scrollState.position.maxScrollExtent, greaterThan(0));
          final viewport = tester.getRect(errorScroll);
          scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
          await tester.pump();
          expect(
            tester.getBottomLeft(errorCopy).dy,
            lessThanOrEqualTo(viewport.bottom),
          );
          expect(tester.getBottomLeft(errorCopy).dy, greaterThan(viewport.top));
          await captureFormFamily(
            tester,
            'teammates-${brightness.name}-$scale-long-error-end',
          );
          final targetRetry = find.byTooltip('Retry');
          await tester.ensureVisible(targetRetry);
          await tester.pumpAndSettle();
          final retryBounds = tester.getRect(targetRetry);
          expect(viewport.contains(retryBounds.topLeft), isTrue);
          expect(viewport.contains(retryBounds.bottomRight), isTrue);
          expect(targetRetry.hitTestable(), findsOneWidget);
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          rosterGate = Completer();
          await tester.tap(targetRetry);
          await tester.pump();
          expect(
            tester
                .widgetList<StudioPageLoading>(find.byType(StudioPageLoading))
                .any(
                  (widget) =>
                      widget.active && widget.label == 'Opening teammate chat',
                ),
            isTrue,
          );
          rosterGate.complete({
            'bot_mode_protocol': true,
            'install_id': 'install-1',
            'profiles': fixture.profiles,
          });
          rosterGate = null;
          await tester.settleTranscript();
          await tester.pumpAndSettle();
          expect(controller.current!.chat!.key.workspace.profileName, 'work');
          expect(controller.current!.chat!.key.sessionId, 'work-tip');
          expect(find.text('Saved work teammate conversation'), findsOneWidget);
          expect(fixture.commands, isEmpty);
          expect(
            browser.calls.where(
              (call) => {'session.create', 'prompt.submit'}.contains(call.$2),
            ),
            isEmpty,
          );
          recipientRows = [deliveryRow(target: 'personal')];
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await tester.tap(closedTab);
          await tester.pumpAndSettle();
          await tester.tap(find.text('@personal'));
          await tester.pumpAndSettle();
          rosterGate = Completer();
          await tester.ensureVisible(find.byTooltip('Open teammate chat'));
          await tester.tap(find.byTooltip('Open teammate chat'));
          await tester.pump();
          expect(find.text('@personal'), findsOneWidget);
          await tester.tap(find.byTooltip('Back'));
          await tester.pump();
          rosterGate.complete({
            'bot_mode_protocol': true,
            'install_id': 'install-1',
            'profiles': fixture.profiles,
          });
          rosterGate = null;
          await tester.pumpAndSettle();
          expect(controller.current?.chat, isNull);
          expect(find.text('@personal'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          app.dispose();
        },
      );
    }
  }
}
