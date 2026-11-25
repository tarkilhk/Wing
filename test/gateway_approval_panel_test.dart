import 'support/wing_client_identity_fixture.dart';
import 'package:wing/core/models/gateway_approval.dart';
import 'support/bots_fixture.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/widgets/gateway_approval_panel.dart';
import 'support/composer_fixture.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/connection_access.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';

import 'profile_workspace_controller_test.dart' show Host;

const _capture = bool.fromEnvironment('CAPTURE_APPROVALS');

class _ApprovalHost extends Host {
  bool rejectDecision = false;

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    late final ProfileGateway gateway;
    gateway = ProfileGateway(
      loadClientIdentity: loadTestWingClientIdentity,
      scope: scope,
      discover: base.discover,
      connect: () async {
        await base.connect();
        if (gateway.onEvent != null) gateways[scope.profileName] = gateway;
      },
      close: base.close,
      get: (path, query) async {
        if (path == 'model/info') {
          return {'provider': 'fixture', 'model': 'fixture/model'};
        }
        if (path == 'model/options') {
          return {
            'providers': [
              {
                'slug': 'fixture',
                'name': 'Fixture',
                'models': ['fixture/model'],
              },
            ],
          };
        }
        return base.read(path, query);
      },
      rpc: (method, params) async {
        if (method == 'approval.respond' && rejectDecision) {
          calls.add((scope.profileName, method, params));
          await approvalDelay?.future;
          throw StateError('Decision was rejected. Try again.');
        }
        return base.call(method, params);
      },
    );
    return gateway;
  }
}

class _ApprovalBots extends BotsSession {
  _ApprovalBots(this.bot) : super((_) async => const []);
  final BotRecord? bot;
  final _fixture = BotsFixture();

  @override
  BotsRepository repository(String identity) => _fixture.repository;

  @override
  BotRecord? cachedAppearance(ProfileSessionKey key) => bot;

  @override
  Future<BotRecord?> botForConversation(ProfileSessionKey key) async => bot;
}

Finder _decisionButton(String label) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == label,
);

void main() {
  setUpAll(() async {
    if (!_capture) return;
    const directory = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      WingTypography.sans: 'Roboto-Regular.ttf',
      'monospace': 'RobotoMono-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              '$directory/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  testWidgets('typed denial footer fits the short keyboard conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411.4, 731.4);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final host = _ApprovalHost();
    late ProfileWorkspaceController controller;
    await tester.runAsync(() async {
      controller = ProfileWorkspaceController(
        connectionIdentity: 'fixture',
        access: ConnectionAccess(
          connection: SavedConnection(
            id: 'host',
            label: 'Home',
            host: 'localhost',
            port: 1,
            apiKey: '',
          ),
          dashboardOAuth: null,
        ),
        preferences: preferences,
        appPreferences: appPreferences,
        gatewayFactory: host.gateway,
      );
      await controller.initialize();
      await controller.createChat(canDispatch: () => true);
      host.event('a', 'approval', {
        'request_id': 'site',
        'server_request_id': 'srq-site',
        'kind': 'network',
        'host': 'docs.example.org',
        'label': 'Reference website',
        'risk': 'Connects to an external website.',
        'choices': ['once', 'always', 'deny'],
      });
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: ProfileWorkspaceScreen(
          controller: controller,
          createBotsSession: () => _ApprovalBots(null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(_decisionButton('Reject'));
    await tester.tap(_decisionButton('Reject'));
    await tester.pumpAndSettle();
    final reason = find.widgetWithText(TextField, 'Reason (optional)');
    await tester.enterText(reason, 'Keep this work offline');
    tester.view.viewInsets = const FakeViewPadding(bottom: 332.19);
    await tester.pumpAndSettle();
    final latest = find.byKey(const ValueKey('jump-to-latest'));
    if (latest.hitTestable().evaluate().isNotEmpty) {
      await tester.tap(latest);
      await tester.pumpAndSettle();
    }
    // Refocusing after a user scroll must not reveal the caret by pushing the
    // action row underneath the composer again.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(reason);
    await tester.pumpAndSettle();
    final editableFinder = find.descendant(
      of: reason,
      matching: find.byType(EditableText),
    );
    final editable = tester.widget<EditableText>(editableFinder);
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.view.viewInsets.bottom, 332.19);
    final decision = _decisionButton('Reject request');
    final viewport = tester.getRect(
      find.byKey(const ValueKey('profile-transcript')),
    );
    final renderEditable = tester
        .state<EditableTextState>(editableFinder)
        .renderEditable;
    final caret = renderEditable
        .getLocalRectForCaret(editable.controller.selection.extent)
        .shift(renderEditable.localToGlobal(Offset.zero));
    expect(viewport.contains(caret.topLeft), isTrue);
    expect(viewport.contains(caret.bottomRight - const Offset(.1, .1)), isTrue);
    final bounds = tester.getRect(decision);
    expect(bounds.size, const Size(48, 48));
    expect(tester.widget<IconButton>(decision).onPressed, isNotNull);
    expect(
      viewport.contains(bounds.topLeft),
      isTrue,
      reason: '$viewport contains $bounds',
    );
    expect(
      viewport.contains(bounds.bottomRight - const Offset(.1, .1)),
      isTrue,
      reason: '$viewport contains $bounds',
    );
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'typed denial retains keyboard draft and disables duplicate submission $brightness/$scale',
        (tester) async {
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final request = GatewayApprovalRequest.fromEventData({
            'kind': 'network',
            'host': ' exact.example.org/private/long-target ',
            'label': 'Reference website',
            'risk': 'External connection',
            'choices': ['once', 'always', 'deny'],
          });
          var busy = false;
          String? error;
          String? receivedReason;
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return SingleChildScrollView(
                      child: GatewayApprovalPanel(
                        request: request,
                        enabled: !busy,
                        busy: busy,
                        error: error,
                        onRespond: (choice, reason) {
                          receivedReason = reason;
                          setState(() => busy = true);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          expect(find.text('Review website access'), findsOneWidget);
          expect(
            find.text('␣exact.example.org/private/long-target␣'),
            findsOneWidget,
          );
          expect(
            find.text('Access lasts until the sandbox is switched off.'),
            findsOneWidget,
          );
          expect(find.byTooltip('Approve once'), findsNothing);
          await tester.tap(find.byTooltip('Reject'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Keep private');
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byTooltip('Reject request'));
          await tester.pumpAndSettle();
          expect(
            find.byTooltip('Reject request').hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('Reject request'));
          await tester.pump();
          expect(receivedReason, 'Keep private');
          expect(
            tester
                .widget<IconButton>(_decisionButton('Reject request'))
                .onPressed,
            isNull,
          );
          update(() {
            busy = false;
            error = 'Decision not confirmed. Retry.';
          });
          await tester.pumpAndSettle();
          expect(find.text('Keep private'), findsOneWidget);
          expect(find.text('Decision not confirmed. Retry.'), findsOneWidget);
          final retry = _decisionButton('Reject request');
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          expect(retry.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(retry);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.bottom, lessThanOrEqualTo(844 - 300));
          expect(tester.widget<IconButton>(retry).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final (botChat, brightness) in [
    for (final botChat in [false, true])
      for (final brightness in Brightness.values) (botChat, brightness),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final fails in [false, true]) {
        testWidgets(
          '${botChat ? 'bot' : 'normal'} approval decision ${fails ? 'failure and retry' : 'success'} retains feedback: $brightness/$scale',
          (tester) async {
            tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            SharedPreferences.setMockInitialValues({});
            final preferences = await SharedPreferences.getInstance();
            final appPreferences = AppPreferences(preferences);
            addTearDown(appPreferences.dispose);
            final host = _ApprovalHost();
            late ProfileWorkspaceController controller;
            await tester.runAsync(() async {
              controller = ProfileWorkspaceController(
                connectionIdentity: 'fixture',
                access: ConnectionAccess(
                  connection: SavedConnection(
                    id: 'host',
                    label: 'Home',
                    host: 'localhost',
                    port: 1,
                    apiKey: '',
                  ),
                  dashboardOAuth: null,
                ),
                preferences: preferences,
                appPreferences: appPreferences,
                gatewayFactory: host.gateway,
              );
              await controller.initialize();
              final chat = await controller.createChat(canDispatch: () => true);
              emitChatEvent(controller, chat, 'session.title', {
                'session_id': chat.key.sessionId,
                'title': 'Review source verification',
              });
              final records = List.generate(
                80,
                (i) => "records.append({'source': $i, 'verified': True})",
              ).join('\n');
              host.pendingApprovals = [];
              for (final id in ['one', 'two']) {
                final approval = <String, dynamic>{
                  'request_id': id,
                  'command':
                      "execute_code <<'PY'\n# Write the source-verification artifact\nimport json, os\n$records\nPY",
                  'choices': ['once', 'session', 'always', 'deny'],
                };
                host.pendingApprovals!.add(approval);
                host.event('a', 'approval', approval);
              }
            });
            addTearDown(controller.dispose);
            final chat = controller.current!.chat!;
            final bot = botChat
                ? BotRecord(
    installationId: 'install:install-1',
                    scope: chat.key.workspace,
                    instance: 'Home',
                    profile: HermesProfile(
                      name: chat.key.workspace.profileName,
                    ),
                    title: 'Pace',
                    shape: 'hexagon',
                    color: '#f6b26b',
                    pinned: false,
                    hidden: false,
                    hasAvatar: false,
                    revision: 1,
                    metadata: const {},
                    chat: chat.key,
                    resolvedChat: chat.key,
                  )
                : null;
            final frame = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: wingTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: scale == 2,
                  ),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: frame,
                  child: ProfileWorkspaceScreen(
                    controller: controller,
                    createBotsSession: () => _ApprovalBots(bot),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byType(BotConversationScope),
              botChat ? findsOneWidget : findsNothing,
            );
            expect(find.text('Review command'), findsOneWidget);
            expect(find.byType(ApprovalRequestDetails), findsOneWidget);
            expect(find.text('Asking a question'), findsNothing);
            final command = find.byWidgetPredicate(
              (widget) =>
                  widget is SelectableText &&
                  widget.data?.contains('records.append') == true,
            );
            expect(command, findsOneWidget);
            expect(
              tester.widget<SelectableText>(command).data,
              chat.runtime.approval!.request.command,
            );
            for (final label in [
              'Approve once',
              'Approve for session',
              'Always approve',
              'Reject',
            ]) {
              await tester.ensureVisible(find.byTooltip(label));
              await tester.pumpAndSettle();
              expect(find.byTooltip(label).hitTestable(), findsOneWidget);
              expect(find.text(label), findsNothing);
            }
            expect(tester.takeException(), isNull);
            // Responding disables every scope, including denial.
            host.approvalDelay = Completer<void>();
            addTearDown(() {
              final pending = host.approvalDelay;
              if (pending != null && !pending.isCompleted) pending.complete();
            });
            host.rejectDecision = fails;
            await tester.ensureVisible(_decisionButton('Approve once'));
            await tester.pumpAndSettle();
            final decisionBounds = tester.getRect(
              _decisionButton('Approve once'),
            );
            final headerSlot = find.byKey(
              const ValueKey('studio-loading-slot'),
            );
            final headerBounds = tester.getRect(headerSlot);
            await tester.tap(_decisionButton('Approve once'));
            await tester.pump();
            expect(
              tester
                  .widgetList<StudioPageLoading>(find.byType(StudioPageLoading))
                  .where((region) => region.active)
                  .map((region) => region.label),
              contains('Sending approval decision'),
            );
            // The shared owner publishes sibling header/body changes after
            // build; this is the first frame drawing the elected header mark.
            await tester.pump();
            expect(
              find.bySemanticsLabel('Sending approval decision'),
              findsOneWidget,
            );
            final progress = find.descendant(
              of: headerSlot,
              matching: find.byType(StudioLoading),
            );
            expect(progress, findsOneWidget);
            expect(
              headerBounds.contains(tester.getRect(progress).center),
              isTrue,
            );
            expect(tester.getSize(progress).shortestSide, greaterThan(0));
            expect(
              tester.getRect(_decisionButton('Approve once')),
              decisionBounds,
            );
            expect(tester.getRect(headerSlot), headerBounds);
            if (_capture && !fails) {
              await tester.runAsync(() async {
                final render =
                    frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await render.toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'build/design-previews/approval-review/${botChat ? 'bot' : 'normal'}-${brightness.name}-$scale-held.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.runAsync(
              () => controller.updateDraft(
                controller.current!.chat!,
                'Draft while reviewing',
              ),
            );
            await tester.pump();
            for (final tooltip in [
              'Approve once',
              'Approve for session',
              'Always approve',
              'Reject',
            ]) {
              expect(
                tester.widget<IconButton>(_decisionButton(tooltip)).onPressed,
                isNull,
              );
            }
            await tester.tap(_decisionButton('Approve once'));
            await tester.pump();
            expect(
              host.calls.where((call) => call.$2 == 'approval.respond'),
              hasLength(1),
            );
            host.approvalDelay!.complete();
            await tester.pumpAndSettle();
            expect(
              find.bySemanticsLabel('Sending approval decision'),
              findsNothing,
            );
            expect(
              host.calls.where((call) => call.$2 == 'approval.respond'),
              hasLength(1),
            );
            if (fails) {
              expect(find.text('1/2'), findsOneWidget);
              expect(
                find.text('Decision was rejected. Try again.'),
                findsOneWidget,
              );
              host.rejectDecision = false;
              host.approvalDelay = null;
              await tester.pump(const Duration(seconds: 5));
              await tester.pumpAndSettle();
              await tester.ensureVisible(_decisionButton('Approve once'));
              await tester.tap(_decisionButton('Approve once'));
              await tester.pumpAndSettle();
              expect(
                host.calls.where((call) => call.$2 == 'approval.respond'),
                hasLength(2),
              );
            }
            expect(
              controller.current!.chat!.composer.observation.text,
              'Draft while reviewing',
            );
            expect(find.text('1/2'), findsNothing);
            expect(find.text('2/2'), findsOneWidget);
            expect(
              controller.current!.chat!.runtime.approval?.requestId,
              'two',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  testWidgets('leaving during an approval does not send a second decision', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences(preferences);
    addTearDown(appPreferences.dispose);
    final host = _ApprovalHost();
    final controller = ProfileWorkspaceController(
      connectionIdentity: 'approval-departure',
      access: ConnectionAccess(
        connection: SavedConnection(
          id: 'host',
          label: 'Home',
          host: 'localhost',
          port: 1,
          apiKey: '',
        ),
        dashboardOAuth: null,
      ),
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: host.gateway,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final chat = await controller.createChat(canDispatch: () => true);
    host.event('a', 'approval', {
      'request_id': 'departure',
      'command': 'echo review',
      'choices': ['once', 'session', 'always', 'deny'],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileWorkspaceScreen(
          controller: controller,
          createBotsSession: () => BotsSession((_) async => []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pending = Completer<void>();
    host.approvalDelay = pending;
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    await tester.tap(_decisionButton('Approve once'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(StudioLoading), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Elsewhere'))),
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Elsewhere'), findsOneWidget);
    expect(find.bySemanticsLabel('Sending approval decision'), findsNothing);
    expect(
      host.calls.where((call) => call.$2 == 'approval.respond'),
      hasLength(1),
    );
    expect(chat.runtime.approvalResponding, isFalse);
    expect(tester.takeException(), isNull);
  });
}
