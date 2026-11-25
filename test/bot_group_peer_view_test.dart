import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/screens/bots/bots_content.dart';
import 'package:wing/core/screens/bots/bots_create_screen.dart';
import 'package:wing/core/services/bots_preferences.dart';
import 'package:wing/core/services/bots_repository.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/services/group_observations.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_error.dart';
import 'package:wing/core/widgets/studio_form_actions.dart';
import 'package:wing/core/widgets/studio_loading.dart';

import 'support/bots_fixture.dart';
import 'support/form_family_capture.dart';

class _PeerCaptureBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

const _keptFile = BotGroupAttachment(
  id: 'att_00000000000000000000000000000001',
  kind: 'file',
  name: 'kept-notes.txt',
  mime: 'text/plain',
  size: 5,
);

/// Owned stock replies shared by the host and Android production-control path.
/// The two default profiles intentionally have different installation owners.
class _PeerWorld {
  _PeerWorld() {
    owner.profiles
      ..clear()
      ..add(BotsFixture.profile('default', 'Home default'));
    lender.profiles
      ..clear()
      ..addAll([
        BotsFixture.profile('default', 'Remote default'),
        BotsFixture.profile('reviewer', 'Remote reviewer'),
      ]);
    owner.readHook = (profile, method, params) async {
      if (method == 'groups.capabilities') {
        capabilityReads++;
        await capabilitiesHeld?.future;
        if (rejectCapabilities) {
          throw StateError('Owned member check unavailable');
        }
        return {
          'authority_gateway_id': 'install:install-1',
          'driver': true,
          'persistent_process': true,
          'features': <String>[],
          'seatable_profiles': ['default'],
          'methods': ['groups.create', 'groups.peer.register', 'groups.send'],
          'room_link': {'enabled': false, 'reason': 'api_server_required'},
        };
      }
      if (method == 'groups.list') {
        return {
          'rooms': [if (created) owner.room],
          'next_offset': null,
        };
      }
      if (method == 'session.active_list') return {'sessions': <Object>[]};
      if (method == 'groups.state') {
        return {
          'room': {...owner.room, 'latest_seq': owner.events.length},
          'context': {
            'purpose': '',
            'notes': '',
            'routing': 'everyone',
            'lead_member_id': '',
          },
          'driver_status': {
            'working': false,
            'blocked': false,
            'pending_actions': <Object>[],
            'peer_routes': [
              for (final entry in routes.entries)
                {
                  'room_id': owner.room['room_id'],
                  'member_id': entry.key,
                  'status': entry.value,
                },
            ],
          },
        };
      }
      return null;
    };
    owner.commandHook = (_, method, params) async {
      if (method == 'groups.send') await sendHeld?.future;
      if (method == 'groups.create') {
        await createHeld?.future;
        owner.room.addAll({
          'room_id': params['room_id'],
          'name': params['name'],
          'members': params['members'],
        });
        created = true;
        return {'room': owner.room};
      }
      if (method == 'groups.peer.register') {
        await registerHeld?.future;
        if (params['target_profile'] == 'reviewer' && rejectReviewer) {
          throw StateError('Owned fixture registration refused');
        }
        routes[params['member_id'] as String] = 'ready';
        return {
          'registered': true,
          'target_install_id': 'install:lender-install',
          'target_profile': params['target_profile'],
          'mode': 'direct',
        };
      }
      if (method == 'profiles.configure') {
        final meta = Map<String, dynamic>.from(params['ui_meta'] as Map);
        final expected = Map<String, dynamic>.from(
          params['ui_meta_expected_revisions'] as Map,
        );
        final row = owner.profiles.single;
        row['ui_meta'] = {...row['ui_meta'] as Map, ...meta};
        final revisions = {
          for (final key in meta.keys) key: (expected[key] as int) + 1,
        };
        row['ui_meta_revisions'] = {
          ...row['ui_meta_revisions'] as Map,
          ...revisions,
        };
        return {
          'ok': true,
          'applied': {'ui_meta': true, 'ui_meta_revisions': revisions},
        };
      }
      return null;
    };
    lender.readHook = (profile, method, _) async {
      if (method == 'profiles.list') {
        return {
          'profiles': lender.profiles,
          'bot_mode_protocol': true,
          'install_id': 'lender-install',
        };
      }
      if (method == 'session.active_list') return {'sessions': <Object>[]};
      if (method == 'groups.list') {
        return {'rooms': <Object>[], 'next_offset': null};
      }
      if (method == 'groups.capabilities') {
        return {
          'authority_gateway_id': 'install:lender-install',
          'driver': true,
          'persistent_process': true,
          'features': <String>[],
          'seatable_profiles': [profile],
          'methods': ['groups.peer.invite'],
          'room_link': {'enabled': true, 'catalog': catalog(profile)},
        };
      }
      return null;
    };
    lender.commandHook = (profile, method, _) async {
      if (method == 'groups.peer.invite') {
        await inviteHeld?.future;
        return {
          'grant': 'owned-fixture-grant-$profile',
          'target_profile': profile,
          'catalog': catalog(profile),
          'endpoint': {'url': 'https://lender.invalid/roomlink'},
        };
      }
      throw StateError('Unexpected lender command $method');
    };
    final scope = WorkspaceScope(
      connectionId: 'lender',
      connectionIdentity: 'lender-identity',
      profileName: 'default',
    );
    lenderRepository = BotsRepository(
      scope: scope,
      instance: 'Other server',
      groupObservations: GroupObservations(scope),
      read: lender.read,
      command: lender.command,
      ownership: lender.ownership,
    );
  }

  final owner = BotsFixture();
  final lender = BotsFixture();
  late final BotsRepository lenderRepository;
  bool created = false, rejectReviewer = true, rejectCapabilities = false;
  int capabilityReads = 0;
  Completer<void>? capabilitiesHeld, createHeld, inviteHeld, registerHeld;
  Completer<void>? sendHeld;
  final routes = <String, String>{};
  Map<String, dynamic> catalog(String profile) => {
    'installation_id': 'install:lender-install',
    'catalog_digest': 'a' * 64,
    'protocol_versions': [2],
    'link_modes': ['direct'],
    'persistent_process': true,
    'text': true,
    'attachments': false,
    'execution_policy': {'target_profile': profile},
    'endpoint': {'available': true, 'url': 'https://lender.invalid/roomlink'},
  };
}

class _PeerRoster extends StatefulWidget {
  const _PeerRoster(this.session);
  final BotsSession session;
  @override
  State<_PeerRoster> createState() => _PeerRosterState();
}

class _PeerRosterState extends State<_PeerRoster> {
  BotsViewState view = const BotsViewState(tab: 1);
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) => BotsContent(
      session: widget.session,
      instanceHeader: const Text('Saved instances'),
      viewState: view,
      onViewChanged: (value) => setState(() => view = value),
      onOpenMenu: () {},
      onOpenChat: (_) async {},
      onOpenGroupMemberChat: (_, _) async {},
      onOpenGroup: (group) => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BotGroupScreen(
            createSession: () => widget.session.openGroup(group),
            stopVoicePlayback: () async {},
            voiceInputSettings: () => null,
          ),
        ),
      ),
    ),
  );
}

typedef PeerNativeCheckpoint =
    Future<void> Function(
      String name, {
      String action,
      String? text,
      bool? keyboard,
    });

/// Runs the same real controls on the host and in each owned Android variant.
/// Android supplies actual IME input and window captures through its handshake.
Future<void> runPeerGroupUiJourney(
  WidgetTester tester, {
  required Brightness brightness,
  required bool large,
  PeerNativeCheckpoint? native,
  bool reducedMotion = false,
}) async {
  final label =
      '${brightness.name}-${large ? 'large' : 'normal'}${reducedMotion ? '-reduced' : ''}';
  final world = _PeerWorld();
  final preferences = await BotsPreferences.load();
  final session = BotsSession(
    (_) async => [world.owner.repository, world.lenderRepository],
    loadPreferences: () async => preferences,
  );
  await session.refresh();
  expect(session.state.errors, isEmpty);
  expect(session.state.bots, hasLength(3));
  var disposed = false;
  void disposeSession() {
    if (disposed) return;
    disposed = true;
    session.dispose();
  }

  addTearDown(disposeSession);
  if (native == null) {
    tester.view.physicalSize = Size(large ? 320 : 390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: formFamilyCapture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: native == null
                ? TextScaler.linear(large ? 2 : 1)
                : null,
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: _PeerRoster(session),
      ),
    ),
  );
  Future<void> until(bool Function() ready, String reason) async {
    for (var attempt = 0; attempt < 200; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: reason);
      if (ready()) return;
    }
    fail(
      'Timed out: $reason; visible=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}; writes=${world.owner.commands.map((call) => call.$2).toList()}',
    );
  }

  Future<void> capture(String stage, {bool? keyboard}) async {
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull, reason: stage);
    if (native != null) {
      await native('$label-$stage', keyboard: keyboard);
    } else {
      await captureFormFamily(tester, 'peer-$label-$stage');
    }
  }

  Finder icon(String tooltip) => find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == tooltip,
  );
  void visibleBusy() {
    final ring = find.descendant(
      of: find.byType(StudioFormActions),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(ring.hitTestable(), findsOneWidget);
    expect(tester.widget<IconButton>(icon('Create group')).onPressed, isNull);
    expect(find.text('Create group'), findsNothing);
  }

  world.capabilitiesHeld = Completer<void>();
  world.rejectCapabilities = native == null;
  final initialReads = world.capabilityReads;
  expect(session.state.groupHosts, contains('instance-1'));
  expect(
    tester
        .widget<FloatingActionButton>(find.byType(FloatingActionButton))
        .onPressed,
    isNotNull,
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.byTooltip('Create group'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  expect(find.byType(BotsCreateScreen), findsOneWidget);
  await until(
    () =>
        world.capabilityReads > initialReads &&
        find.byType(StudioLoading).evaluate().isNotEmpty,
    'visible preparation on the entered creation route',
  );
  final preparation = find.byType(StudioLoading);
  expect(tester.getSize(preparation), const Size(18, 18));
  expect(tester.getRect(preparation).top, greaterThanOrEqualTo(0));
  await capture('mixed-checking');
  world.capabilitiesHeld!.complete();
  world.capabilitiesHeld = null;
  if (native == null) {
    final notice = find.byType(StudioRetryNotice);
    final retryChecks = find.descendant(of: notice, matching: icon('Retry'));
    await until(
      () => retryChecks.hitTestable().evaluate().isNotEmpty,
      'failed member preparation keeps recovery on the form',
    );
    expect(find.text('Members could not be checked.'), findsOneWidget);
    expect(world.owner.commands, isEmpty);
    await capture('mixed-check-failed');
    final failureBounds = tester.getRect(notice);
    world.rejectCapabilities = false;
    world.capabilitiesHeld = Completer<void>();
    await tester.tap(retryChecks);
    await tester.pump();
    expect(find.text('Members could not be checked.'), findsOneWidget);
    final containedRing = find.descendant(
      of: notice,
      matching: find.byType(CircularProgressIndicator),
    );
    await until(
      () => containedRing.hitTestable().evaluate().isNotEmpty,
      'visible contained member-check retry retaining the failure',
    );
    expect(tester.getRect(notice), failureBounds);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(StudioLoading), findsNothing);
    expect(tester.widget<IconButton>(retryChecks).onPressed, isNull);
    if (reducedMotion) {
      expect(
        tester.widget<CircularProgressIndicator>(containedRing).value,
        .75,
      );
    }
    await capture('mixed-check-retry');
    world.capabilitiesHeld!.complete();
    world.capabilitiesHeld = null;
  }
  final formScrollable = find.descendant(
    of: find.byType(BotsCreateScreen),
    matching: find.byType(Scrollable),
  ).first;
  final bots = session.state.bots;
  for (final bot in bots) {
    final row = find.byKey(ValueKey('group-member-${bot.id}'));
    await tester.scrollUntilVisible(
      row,
      160,
      scrollable: formScrollable,
      maxScrolls: 20,
    );
    await until(
      () => row.evaluate().isNotEmpty && tester.widget<ListTile>(row).enabled,
      'eligible ${bot.title}',
    );
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(row.hitTestable());
    await tester.pump();
  }
  expect(find.byType(StudioRetryNotice), findsNothing);
  expect(find.text('3 of 6 selected'), findsOneWidget);
  final name = find.byKey(const ValueKey('group-name'));
  await tester.scrollUntilVisible(
    name,
    -160,
    scrollable: formScrollable,
    maxScrolls: 20,
  );
  await tester.pump(const Duration(milliseconds: 200));
  if (native == null) {
    await tester.enterText(name, 'Mixed team');
  } else {
    await tester.tap(name);
    await native(
      '$label-mixed-name',
      action: 'type',
      text: 'Mixed team',
      keyboard: true,
    );
    await until(
      () =>
          tester.view.viewInsets.bottom > 0 &&
          tester.widget<TextField>(name).controller!.text == 'Mixed team',
      'real mixed-group name IME',
    );
    final confirm = tester.getRect(icon('Create group'));
    final availableBottom =
        (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
        tester.view.devicePixelRatio;
    expect(confirm.width, greaterThanOrEqualTo(48));
    expect(confirm.height, greaterThanOrEqualTo(48));
    expect(confirm.bottom, lessThanOrEqualTo(availableBottom));
    await capture('mixed-keyboard', keyboard: true);
    await native('$label-mixed-hide', action: 'hide-keyboard');
    await until(
      () => tester.view.viewInsets.bottom == 0,
      'mixed-group IME closed',
    );
  }
  await capture('mixed-create');
  world.capabilitiesHeld = Completer<void>();
  world.createHeld = Completer<void>();
  world.inviteHeld = Completer<void>();
  world.registerHeld = Completer<void>();
  final checks = world.capabilityReads;
  await tester.tap(icon('Create group'));
  await tester.pump();
  visibleBusy();
  await until(() => world.capabilityReads > checks, 'held create revalidation');
  expect(
    world.owner.commands.where((call) => call.$2 == 'groups.create'),
    isEmpty,
  );
  await capture('mixed-revalidation');
  world.capabilitiesHeld!.complete();
  world.capabilitiesHeld = null;
  await until(
    () => world.owner.commands.any((call) => call.$2 == 'groups.create'),
    'held room creation',
  );
  visibleBusy();
  await capture('mixed-saving');
  world.createHeld!.complete();
  await until(
    () =>
        world.lender.commands
            .where((call) => call.$2 == 'groups.peer.invite')
            .length ==
        2,
    'independent invitations',
  );
  visibleBusy();
  await capture('mixed-inviting');
  world.inviteHeld!.complete();
  await until(
    () =>
        world.owner.commands
            .where((call) => call.$2 == 'groups.peer.register')
            .length ==
        2,
    'held registration',
  );
  visibleBusy();
  await capture('mixed-registering');
  world.registerHeld!.complete();
  await until(
    () =>
        find.byType(BotsCreateScreen).evaluate().isEmpty &&
        find.text('Mixed team').hitTestable().evaluate().isNotEmpty,
    'partially joined room returns to roster',
  );
  final room = session.state.groups.single;
  expect(
    room.members.where((member) => member.profile == 'default'),
    hasLength(2),
  );
  expect(room.members.where((member) => member.target.isPeer), hasLength(2));
  expect(
    world.owner.commands.where((call) => call.$2 == 'groups.create'),
    hasLength(1),
  );
  final home = room.members.singleWhere((member) => !member.target.isPeer);
  final remote = room.members.singleWhere(
    (member) => member.target.isPeer && member.profile == 'default',
  );
  expect(
    matchBotGroupMember(room, home, bots)!.installationId,
    'install:install-1',
  );
  expect(
    matchBotGroupMember(room, remote, bots)!.installationId,
    'install:lender-install',
  );
  // A restored file stays visible until the user explicitly removes it.
  await preferences.writeMessageDraft(
    room.scope.connectionIdentity,
    room.id,
    'Keep these words',
    const [],
    attachments: const [_keptFile],
  );
  await tester.tap(find.text('Mixed team').hitTestable());
  final composer = find.byKey(const ValueKey('group-message-composer'));
  await until(() => composer.evaluate().isNotEmpty, 'mixed room conversation');
  final members = find.byTooltip('Show group members · 3 bots');
  await until(
    () => members.hitTestable().evaluate().isNotEmpty,
    'reachable member popup',
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(members.hitTestable());
  await until(
    () =>
        find.text('Not joined').evaluate().isNotEmpty &&
        find.text('Joined').evaluate().isNotEmpty,
    'partial member join presentation',
  );
  expect(find.text('Other server'), findsNWidgets(2));
  await capture('mixed-partial');
  final reviewer = room.members.singleWhere(
    (member) => member.profile == 'reviewer',
  );
  final retry = icon('Retry ${reviewer.name}');
  final invitesBeforeRetry = world.lender.commands.length;
  world.inviteHeld = Completer<void>();
  await tester.tap(retry);
  await tester.pump();
  final joining = find.byWidgetPredicate(
    (widget) =>
        widget is CircularProgressIndicator &&
        widget.semanticsLabel == 'Joining member',
  );
  expect(joining.hitTestable(), findsOneWidget);
  if (reducedMotion) {
    expect(tester.widget<CircularProgressIndicator>(joining).value, .75);
  }
  await until(
    () => world.lender.commands.length == invitesBeforeRetry + 1,
    'exact reviewer retry',
  );
  expect(world.lender.commands.last.$1, 'reviewer');
  await capture('mixed-retry-pending');
  world.inviteHeld!.complete();
  await until(
    () => find
        .text('Joining could not be confirmed. Retry to check this member.')
        .evaluate()
        .isNotEmpty,
    'failed member retry stays actionable',
  );
  await capture('mixed-retry-failed');
  world.rejectReviewer = false;
  world.inviteHeld = Completer<void>();
  await tester.tap(retry);
  await tester.pump();
  expect(joining.hitTestable(), findsOneWidget);
  if (reducedMotion) {
    expect(tester.widget<CircularProgressIndicator>(joining).value, .75);
  }
  world.inviteHeld!.complete();
  await until(
    () =>
        find.text('Joined').evaluate().length == 2 &&
        joining.evaluate().isEmpty,
    'both independent peers joined',
  );
  await capture('mixed-recovered');
  expect(world.routes[reviewer.id], 'ready');
  expect(
    world.owner.commands.where((call) => call.$2 == 'groups.create'),
    hasLength(1),
  );
  expect(
    world.owner.commands.where((call) => call.$2 == 'groups.send'),
    isEmpty,
  );
  Navigator.of(tester.element(retry)).pop();
  await tester.pump(const Duration(milliseconds: 250));
  expect(tester.widget<IconButton>(icon('Attach file')).onPressed, isNull);
  expect(
    find.text(
      'Bots on other instances can receive text only. Remove the files before sending.',
    ),
    findsOneWidget,
  );
  expect(
    tester.widget<TextField>(composer).controller!.text,
    'Keep these words',
  );
  await tester.tap(icon('Send group message'));
  await tester.pump();
  expect(
    world.owner.commands.where((call) => call.$2 == 'groups.send'),
    isEmpty,
  );
  expect(
    tester.widget<TextField>(composer).controller!.text,
    'Keep these words',
  );
  final fileChip = find.widgetWithText(InputChip, 'kept-notes.txt');
  final removeFile = find.descendant(
    of: fileChip,
    matching: find.byIcon(Icons.clear),
  );
  expect(tester.widget<InputChip>(fileChip).onDeleted, isNotNull);
  await Scrollable.ensureVisible(
    tester.element(fileChip),
    alignment: .5,
  );
  await tester.pump(const Duration(milliseconds: 200));
  await capture('mixed-file-limit');
  expect(removeFile.hitTestable(), findsOneWidget);
  await tester.tap(removeFile.hitTestable());
  await until(
    () => fileChip.evaluate().isEmpty,
    'explicit removal of retained file',
  );
  expect(
    tester.widget<TextField>(composer).controller!.text,
    'Keep these words',
  );
  expect(
    find.text('Bots on other instances can receive text only.'),
    findsOneWidget,
  );
  expect(find.textContaining('Remove the files before sending.'), findsNothing);
  final sentText = native == null
      ? 'Keep these words'
      : 'Keep these words Native';
  if (native != null) {
    await tester.tap(composer);
    await native(
      '$label-mixed-message',
      action: 'append',
      text: ' Native',
      keyboard: true,
    );
    await until(
      () =>
          tester.view.viewInsets.bottom > 0 &&
          tester.widget<TextField>(composer).controller!.text == sentText,
      'native mixed-group text input',
    );
    final sendBounds = tester.getRect(icon('Send group message'));
    final availableBottom =
        (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
        tester.view.devicePixelRatio;
    expect(sendBounds.width, greaterThanOrEqualTo(48));
    expect(sendBounds.height, greaterThanOrEqualTo(48));
    expect(sendBounds.bottom, lessThanOrEqualTo(availableBottom));
  }
  await capture('mixed-text-only', keyboard: native == null ? null : true);
  await tester.tap(icon('Send group message'));
  await until(
    () =>
        world.owner.events.length == 1 &&
        tester.widget<TextField>(composer).controller!.text.isEmpty,
    'text send remains available in a mixed room',
  );
  final send = world.owner.commands.singleWhere(
    (call) => call.$2 == 'groups.send',
  );
  expect((send.$3['payload'] as Map)['text'], sentText);
  expect((send.$3['payload'] as Map)['attachments'], isNull);
  await capture('mixed-text-sent');
  if (native != null) {
    await native('$label-mixed-message-hide', action: 'hide-keyboard');
    await until(
      () => tester.view.viewInsets.bottom == 0,
      'mixed-group message IME closed',
    );
  }
  if (native == null) {
    // Departure retires only this visit. A late invitation cannot register or
    // navigate back into the room after the user has left it.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(members.hitTestable());
    await until(
      () => retry.hitTestable().evaluate().isNotEmpty,
      'member recovery before departure',
    );
    world.inviteHeld = Completer<void>();
    final invitations = world.lender.commands.length;
    await tester.tap(retry);
    await until(
      () =>
          world.lender.commands.length > invitations &&
          joining.evaluate().isNotEmpty,
      'held peer invitation before departure',
    );
    final registrations = world.owner.commands
        .where((call) => call.$2 == 'groups.peer.register')
        .length;
    Navigator.of(tester.element(joining)).pop();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byType(BackButton));
    await until(
      () => find.byType(BotGroupScreen).evaluate().isEmpty,
      'left mixed group while peer join waits',
    );
    world.inviteHeld!.complete();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      world.owner.commands.where((call) => call.$2 == 'groups.peer.register'),
      hasLength(registrations),
    );
    expect(find.byType(BotsContent), findsOneWidget);
    expect(find.byType(BotGroupScreen), findsNothing);
    expect(find.text('Mixed team'), findsOneWidget);
    expect(
      world.owner.commands.where((call) => call.$2 == 'groups.create'),
      hasLength(1),
    );
    expect(
      world.owner.commands.where((call) => call.$2 == 'groups.send'),
      hasLength(1),
    );
    await capture('mixed-departure');
  }
  await tester.pumpWidget(const SizedBox());
  disposeSession();
  await tester.pump();
}

void main() {
  if (const bool.fromEnvironment('CAPTURE_FORM_FAMILY')) {
    _PeerCaptureBinding();
  }
  setUpAll(loadFormFamilyFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final large in [false, true]) {
      testWidgets(
        'mixed group creation, partial recovery and text-only controls ${brightness.name} ${large ? '320/200%' : '390/100%'}',
        (tester) async {
          await runPeerGroupUiJourney(
            tester,
            brightness: brightness,
            large: large,
          );
        },
      );
    }
  }
  testWidgets('uncertain mixed-file intent retains reachable exact Retry', (
    tester,
  ) async {
    final world = _PeerWorld()..created = true;
    world.owner.room['members'] = [
      {
        'member_id': 'home',
        'profile': 'default',
        'handle': 'bot_home',
        'display_name': 'Home default',
        'target': {'kind': 'local', 'profile': 'default'},
      },
      {
        'member_id': 'remote',
        'profile': 'default',
        'handle': 'bot_remote',
        'display_name': 'Remote default',
        'target': {
          'kind': 'peer',
          'profile': 'default',
          'installation_id': 'install:lender-install',
          'peer_id': 'install:lender-install',
          'capability_digest': 'a' * 64,
        },
      },
    ];
    final preferences = await BotsPreferences.load();
    final roster = BotsSession(
      (_) async => [world.owner.repository, world.lenderRepository],
      loadPreferences: () async => preferences,
    );
    await roster.refresh();
    final room = roster.state.groups.single;
    const eventId = '11111111-1111-4111-8111-111111111111';
    await preferences.writeMessageDraft(
      room.scope.connectionIdentity,
      room.id,
      'Keep these words',
      const [],
      attachments: const [_keptFile],
      pendingEventId: eventId,
      pendingText: 'Keep these words',
      pendingWireText: 'Frozen wire words',
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: formFamilyCapture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wingTheme(Brightness.dark),
            home: BotGroupScreen(
              createSession: () => roster.openGroup(room),
              stopVoicePlayback: () async {},
              voiceInputSettings: () => null,
            ),
          ),
        ),
      );
      Future<void> until(bool Function() ready) async {
        for (var attempt = 0; attempt < 200; attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          if (ready()) return;
        }
        fail('Uncertain mixed-file UI did not settle');
      }

      Finder icon(String label) => find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == label,
      );
      final retry = icon('Retry same message');
      final composer = find.byKey(const ValueKey('group-message-composer'));
      await until(() => retry.hitTestable().evaluate().isNotEmpty);
      expect(tester.widget<IconButton>(retry).onPressed, isNotNull);
      expect(tester.widget<TextField>(composer).readOnly, true);
      expect(tester.widget<IconButton>(icon('Attach file')).onPressed, isNull);
      expect(
        tester
            .widget<InputChip>(find.widgetWithText(InputChip, 'kept-notes.txt'))
            .onDeleted,
        isNull,
      );
      expect(
        find.textContaining('Remove the files before sending.'),
        findsNothing,
      );
      await captureFormFamily(tester, 'peer-uncertain-mixed-files');
      world.sendHeld = Completer<void>();
      await tester.tap(retry);
      await until(
        () => world.owner.commands.any((call) => call.$2 == 'groups.send'),
      );
      final sent = world.owner.commands.singleWhere(
        (call) => call.$2 == 'groups.send',
      );
      expect(sent.$3['event_id'], eventId);
      expect((sent.$3['payload'] as Map)['text'], 'Frozen wire words');
      expect((sent.$3['payload'] as Map)['attachments'], [_keptFile.toJson()]);
      world.sendHeld!.complete();
      await until(
        () =>
            find.byTooltip('Retry same message').evaluate().isEmpty &&
            !tester.widget<TextField>(composer).readOnly,
      );
      expect(world.owner.events, hasLength(1));
      expect(
        world.owner.commands.where((call) => call.$2 == 'groups.send'),
        hasLength(1),
      );
      expect(
        preferences.messageDraft(room.scope.connectionIdentity, room.id),
        isNull,
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      roster.dispose();
      await tester.pump();
    }
  });
  testWidgets(
    'mixed group controls keep visible progress with reduced motion',
    (tester) async {
      await runPeerGroupUiJourney(
        tester,
        brightness: Brightness.dark,
        large: false,
        reducedMotion: true,
      );
    },
  );
}
