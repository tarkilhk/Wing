import 'support/backend_update_channel_fixture.dart';
import 'package:wing/core/widgets/studio_loading.dart';
import 'package:wing/core/widgets/studio_error.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/backend_update_controller.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/widgets/backend_version_card.dart';
import 'package:wing/core/screens/versions_updates_screen.dart';
import 'package:wing/core/services/versions_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';

const _available = <String, dynamic>{
  'current_version': '1.2.3',
  'install_method': 'git',
  'behind': 2,
  'update_available': true,
  'can_apply': true,
};

class _UpdateHost {
  final source = BackendUpdateChannelFixture();
  Map<String, dynamic> checkResponse = _available;
  Map<String, dynamic> statusResponse = {
    'running': true,
    'pid': 41,
    'exit_code': null,
    'lines': <String>[],
  };
  Map<String, dynamic> postResponse = {
    'ok': true,
    'name': 'hermes-update',
    'pid': 41,
    'action_id': 'action-1',
  };
  Map<String, dynamic> receiptResponse = {
    'receipt': {
      'pid': 41,
      'finished_at': '2026-09-12T12:00:00Z',
      'outcome': 'success',
    },
    'summary': 'success',
  };
  Completer<Map<String, dynamic>>? pendingHealth;
  Completer<Map<String, dynamic>>? pendingCheck;
  Completer<Map<String, dynamic>>? pendingStatus;
  bool statusFails = false;
  final reads = <(String, Map<String, String>)>[];
  final posts = <(String, Map<String, dynamic>)>[];

  late final ProfileGateway gateway = ProfileGateway(
    scope: WorkspaceScope(connectionId: 'host', profileName: 'work'),
    get: (endpoint, query) async {
      reads.add((endpoint, query));
      final metadata = source.read(endpoint, query);
      if (metadata != null) return metadata;
      if (endpoint == 'health') {
        if (pendingHealth != null) return pendingHealth!.future;
        return {
          'ok': true,
          'version': checkResponse['current_version'],
          'commit': BackendUpdateChannelFixture.currentSha,
        };
      }
      if (endpoint == 'hermes/update/check') {
        source.fetchedAt++;
        return pendingCheck?.future ?? checkResponse;
      }
      if (endpoint == 'hermes/update/receipt') {
        return receiptResponse;
      }
      if (statusFails) {
        throw StateError('private disconnected detail');
      }
      return pendingStatus?.future ?? statusResponse;
    },
    ownedPut: source.put,
    ownedPost: (endpoint, body, canDispatch, onDispatched) async {
      if (!canDispatch()) throw StateError('Retired');
      onDispatched();
      posts.add((endpoint, body));
      return postResponse;
    },
    rpc: (_, _) async => <String, dynamic>{},
    discover: () async => const ProfileDiscovery(
      profiles: [],
      currentName: null,
      activeName: null,
    ),
  );
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_BACKEND_CHANNELS');
  setUpAll(() async {
    if (!capture) return;
    for (final (family, path) in [
      ('Roboto', 'build/studio-roboto.ttf'),
      ('MaterialIcons', 'build/studio-icons.otf'),
    ]) {
      await (FontLoader(family)..addFont(
            File(path).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          ))
          .load();
    }
  });
  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('channels-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/design-previews/backend-channels/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void expectCompactDialog(WidgetTester tester, String title, String action) {
    final dialog = tester.getRect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    final heading = tester.getRect(find.text(title));
    final cancel = tester.getRect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byTooltip('Cancel'),
      ),
    );
    final commit = tester.getRect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byTooltip(action),
      ),
    );
    expect(heading.left - dialog.left, closeTo(WingSpacing.md, 0.01));
    expect(dialog.right - heading.right, closeTo(WingSpacing.md, 0.01));
    expect(heading.top - dialog.top, closeTo(WingSpacing.md, 0.01));
    expect(dialog.right - commit.right, closeTo(WingSpacing.md, 0.01));
    expect(dialog.bottom - commit.bottom, closeTo(WingSpacing.md, 0.01));
    expect(commit.left - cancel.right, closeTo(WingSpacing.sm, 0.01));
    expect(cancel.size, const Size(48, 48));
    expect(commit.size, cancel.size);
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'version route ${brightness.name} $scale loading, unknown, retry and success',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final health = Completer<Map<String, dynamic>>();
            final check = Completer<Map<String, dynamic>>();
            final host = _UpdateHost()
              ..pendingHealth = health
              ..pendingCheck = check;
            tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: wingTheme(brightness),
                debugShowCheckedModeBanner: false,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: scale == 2,
                  ),
                  child: RepaintBoundary(
                    key: const ValueKey('channels-capture'),
                    child: child!,
                  ),
                ),
                home: VersionsUpdatesScreen(
                  controllerFactory: (_) =>
                      VersionsController(gateway: host.gateway),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.text('Loading version…'), findsNothing);
            expect(find.text('—'), findsOneWidget);
            expect(find.text('Checking for updates…'), findsNothing);
            expect(
              find.text('Update availability unknown.').hitTestable(),
              findsNothing,
            );
            expect(
              find.bySemanticsLabel('Update availability unknown.'),
              findsNothing,
            );
            expect(find.byType(StudioLoading), findsOneWidget);
            await snapshot(tester, '${brightness.name}-$scale-initial');

            host.pendingHealth = null;
            health.complete({
              'ok': true,
              'version': '0.22.0',
              'commit': BackendUpdateChannelFixture.currentSha,
            });
            await tester.pump();
            await tester.pump();
            expect(find.text('0.22.0'), findsOneWidget);
            expect(find.text('Checking for updates…'), findsNothing);
            expect(find.byType(StudioLoading), findsOneWidget);
            await snapshot(tester, '${brightness.name}-$scale-version-ready');

            check.complete({
              'current_version': '0.22.0',
              'behind': -1,
              'can_apply': false,
            });
            await tester.pumpAndSettle();
            expect(find.text('Update availability unknown.'), findsOneWidget);
            expect(find.byType(StudioLoading), findsNothing);
            await snapshot(tester, '${brightness.name}-$scale-unknown');

            final retry = Completer<Map<String, dynamic>>();
            host.pendingCheck = retry;
            await tester.ensureVisible(find.byTooltip('Check for updates'));
            final header = tester.getRect(find.text('Versions & updates'));
            await tester.tap(find.byTooltip('Check for updates'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.text('Checking for updates…'), findsNothing);
            expect(
              find.text('Update availability unknown.').hitTestable(),
              findsNothing,
            );
            expect(
              find.bySemanticsLabel('Update availability unknown.'),
              findsNothing,
            );
            expect(find.byType(StudioLoading), findsOneWidget);
            expect(tester.getRect(find.text('Versions & updates')), header);
            final button = tester.widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Check for updates',
              ),
            );
            expect(button.onPressed, isNull);
            retry.completeError(StateError('unreachable'));
            await tester.pumpAndSettle();
            expect(find.text('Could not check for updates.'), findsNothing);
            expect(
              find.text('Update availability could not be checked. Try again.'),
              findsOneWidget,
            );
            expect(find.byType(StudioError), findsOneWidget);
            expect(find.byType(StudioLoading), findsNothing);
            await snapshot(tester, '${brightness.name}-$scale-check-failed');

            host.pendingCheck = null;
            host.checkResponse = {
              ..._available,
              'behind': 0,
              'update_available': false,
            };
            await tester.tap(find.byTooltip('Check for updates'));
            await tester.pumpAndSettle();
            expect(find.text('Up to date on main'), findsOneWidget);
            expect(find.byType(StudioLoading), findsNothing);
            expect(tester.takeException(), isNull);
            await snapshot(tester, '${brightness.name}-$scale-current');

            host.checkResponse = _available;
            await tester.tap(find.byTooltip('Check for updates'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byTooltip('Update backend'));
            await tester.tap(find.byTooltip('Update backend'));
            await tester.pumpAndSettle();
            final startCheck = Completer<Map<String, dynamic>>();
            host.pendingCheck = startCheck;
            await tester.tap(find.byTooltip('Update backend').last);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byType(StudioLoading), findsOneWidget);
            expect(find.text('Starting backend update…'), findsNothing);
            expect(find.text('Checking for updates…'), findsNothing);
            startCheck.complete(_available);
            await tester.pumpAndSettle();
            expect(find.byType(StudioLoading), findsNothing);
            expect(host.posts, hasLength(1));
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'channel route ${brightness.name} $scale held refresh, save failure and retry',
        (tester) async {
          final host = _UpdateHost()
            ..checkResponse = {
              ..._available,
              'behind': null,
              'update_available': false,
              'message': "Couldn't reach the update source — try again later.",
            };
          host.source
            ..channel = 'stable'
            ..branch = null
            ..error = 'release-unavailable'
            ..targetSha = null;
          tester.view.physicalSize = Size(scale == 2 ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                  key: const ValueKey('channels-capture'),
                  child: child!,
                ),
              ),
              home: VersionsUpdatesScreen(
                controllerFactory: (_) =>
                    VersionsController(gateway: host.gateway),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Channel: stable'), findsOneWidget);
          expect(
            find.text(host.checkResponse['message'] as String),
            findsOneWidget,
          );
          expect(find.byTooltip('Update backend'), findsNothing);
          await snapshot(tester, '${brightness.name}-$scale-error');

          final refresh = Completer<Map<String, dynamic>>();
          host.pendingCheck = refresh;
          final actions = find
              .ancestor(
                of: find.byTooltip('Check for updates'),
                matching: find.byType(Wrap),
              )
              .first;
          await tester.ensureVisible(find.byTooltip('Check for updates'));
          final before = tester.getRect(actions);
          await tester.tap(find.byTooltip('Check for updates'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byType(StudioLoading), findsOneWidget);
          expect(tester.getRect(actions), before);
          await snapshot(tester, '${brightness.name}-$scale-checking');
          host.pendingCheck = null;
          host.source
            ..error = null
            ..targetSha = '2222222222222222222222222222222222222222'
            ..targetVersion = '0.21.7';
          host.checkResponse = {..._available, 'behind': -1};
          refresh.complete(host.checkResponse);
          await tester.pumpAndSettle();
          expect(find.byType(StudioLoading), findsNothing);
          expect(find.text('Release update available'), findsOneWidget);
          expect(find.text('Release: 0.21.7'), findsOneWidget);
          await snapshot(tester, '${brightness.name}-$scale-release');

          await tester.ensureVisible(find.byTooltip('Change update channel'));
          await tester.tap(find.byTooltip('Change update channel'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Stable releases'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Main branch').last);
          await tester.pumpAndSettle();
          expectCompactDialog(tester, 'Update channel', 'Save update channel');
          final saveRect = tester.getRect(
            find.byTooltip('Save update channel'),
          );
          await snapshot(tester, '${brightness.name}-$scale-editor');
          final write = Completer<void>();
          host.source
            ..pendingWrite = write
            ..saveFails = true;
          await tester.tap(find.byTooltip('Save update channel'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 32));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          // Measure the held save after the shared press feedback settles.
          await tester.pump(WingMotion.buttonPress);
          await tester.pump(WingMotion.buttonRelease);
          expectCompactDialog(tester, 'Update channel', 'Save update channel');
          expect(
            tester.getRect(find.byTooltip('Save update channel')),
            saveRect,
          );
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == 'Cancel',
                  ),
                )
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is IconButton && w.tooltip == 'Save update channel',
                  ),
                )
                .onPressed,
            isNull,
          );
          await tester.binding.handlePopRoute();
          await tester.pump(const Duration(milliseconds: 32));
          expect(find.text('Update channel'), findsOneWidget);
          await snapshot(tester, '${brightness.name}-$scale-saving');
          write.complete();
          await tester.pumpAndSettle();
          expect(find.text('Main branch'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            find.text('The channel save could not be confirmed. Try again.'),
            findsWidgets,
          );
          expectCompactDialog(tester, 'Update channel', 'Save update channel');
          await snapshot(tester, '${brightness.name}-$scale-save-error');

          host.source
            ..pendingWrite = null
            ..saveFails = false;
          host.checkResponse = _available;
          await tester.ensureVisible(find.byTooltip('Save update channel'));
          await tester.tap(find.byTooltip('Save update channel'));
          await tester.pumpAndSettle();
          expect(find.text('Update channel'), findsNothing);
          expect(find.text('Channel: main'), findsOneWidget);
          expect(
            find.text('Update available · 2 commits behind main'),
            findsOneWidget,
          );
          expect(host.source.writes, hasLength(2));
          expect(host.posts, isEmpty);
          expect(tester.takeException(), isNull);
          await snapshot(tester, '${brightness.name}-$scale-main');
          await tester.ensureVisible(find.byTooltip('Update backend'));
          await tester.tap(find.byTooltip('Update backend'));
          await tester.pumpAndSettle();
          expectCompactDialog(
            tester,
            'Update backend on this server?',
            'Update backend',
          );
          await snapshot(tester, '${brightness.name}-$scale-confirmation');
          await tester.tap(find.byTooltip('Cancel'));
          await tester.pumpAndSettle();
          host.source
            ..channel = 'stable'
            ..branch = null
            ..rollback = true
            ..targetVersion = '0.21.6';
          host.checkResponse = {
            ..._available,
            'behind': -1,
            'rollback_to': '0.21.6',
            'message':
                'Updating moves this build back to stable release 0.21.6.',
          };
          await tester.tap(find.byTooltip('Check for updates'));
          await tester.pumpAndSettle();
          expect(find.text('Switch to an older release'), findsOneWidget);
          await tester.ensureVisible(find.byTooltip('Update backend'));
          await tester.tap(find.byTooltip('Update backend'));
          await tester.pumpAndSettle();
          expectCompactDialog(
            tester,
            'Update backend on this server?',
            'Update backend',
          );
          expect(
            find.textContaining('moves the server back to release 0.21.6'),
            findsOneWidget,
          );
          await snapshot(tester, '${brightness.name}-$scale-rollback');
          await tester.tap(find.byTooltip('Cancel'));
          await tester.pumpAndSettle();
          expect(host.posts, isEmpty);
        },
      );
    }
  }
  testWidgets(
    'known update status refresh stays quiet and publishes new output',
    (tester) async {
      final host = _UpdateHost();
      final controller = BackendUpdateController(host.gateway);
      addTearDown(controller.dispose);
      await controller.checkForUpdate();
      await controller.refreshStatus();
      final pending = Completer<Map<String, dynamic>>();
      host.pendingStatus = pending;
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(host.statusResponse);
      });
      final card = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => Scaffold(body: child),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: BackendVersionCard(
                  key: card,
                  updateController: controller,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(card));
      final refresh = controller.refreshStatus();
      await tester.pump(const Duration(seconds: 12));
      expect(find.byType(StudioLoading), findsNothing);
      expect(tester.getRect(find.byKey(card)), before);
      expect(find.byTooltip('Changes in this update'), findsOneWidget);
      pending.complete({
        ...host.statusResponse,
        'lines': ['Fresh update output'],
      });
      await refresh;
      await tester.pumpAndSettle();
      expect(controller.status!.lines, ['Fresh update output']);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Fresh update output'), findsOneWidget);
    },
  );
  Future<void> showCard(
    WidgetTester tester,
    _UpdateHost host, {
    Size size = const Size(800, 900),
    double textScale = 1,
  }) async {
    final controller = BackendUpdateController(host.gateway);
    addTearDown(controller.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackendVersionCard(
              updateController: controller,
              connectionLabel: 'Production host',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> check(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  Future<void> openConfirmation(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Update backend'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'named previews are visible and custom branches stay host-owned',
    (tester) async {
      final host = _UpdateHost()..checkResponse = {..._available, 'behind': -1};
      host.source
        ..channel = 'pm-preview'
        ..branch = null;
      await showCard(tester, host);
      await tester.pumpAndSettle();
      expect(find.text('Channel: pm-preview'), findsOneWidget);
      expect(find.text('Release update available'), findsOneWidget);
      await tester.tap(find.byTooltip('Change update channel'));
      await tester.pumpAndSettle();
      expect(find.text('Keep the configured preview channel.'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      host.source
        ..channel = 'main'
        ..branch = 'feature/mobile';
      host.checkResponse = _available;
      await tester.tap(find.byTooltip('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Branch: feature/mobile'), findsOneWidget);
      expect(find.byTooltip('Change update channel'), findsNothing);
      expect(host.source.writes, isEmpty);
      expect(host.posts, isEmpty);
    },
  );

  testWidgets('loads version and upstream status automatically on opening', (
    tester,
  ) async {
    final host = _UpdateHost()
      ..checkResponse = {..._available, 'behind': 0, 'update_available': false};
    await showCard(tester, host);
    await check(tester);

    expect(
      host.reads.where((call) => call.$1 == 'hermes/update/check'),
      hasLength(1),
    );
    expect(
      host.reads.firstWhere((call) => call.$1 == 'hermes/update/check').$1,
      'hermes/update/check',
    );
    expect(
      host.reads.firstWhere((call) => call.$1 == 'hermes/update/check').$2,
      {'force': 'true', 'profile': 'work'},
    );
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('Install method: git'), findsOneWidget);
    expect(find.text('Up to date on main'), findsOneWidget);
    expect(find.byTooltip('Changes in this update'), findsNothing);
    expect(find.byTooltip('Update backend'), findsNothing);
    expect(find.byTooltip('Check update progress'), findsNothing);

    await tester.tap(find.byTooltip('Check for updates'));
    await tester.pumpAndSettle();
    expect(
      host.reads.where((call) => call.$1 == 'hermes/update/check'),
      hasLength(2),
    );
  });

  testWidgets(
    'missing change details do not block updating or trigger requests',
    (tester) async {
      final host = _UpdateHost()..checkResponse = {..._available, 'behind': -1};
      await showCard(tester, host);
      await tester.pumpAndSettle();
      expect(
        find.text('Update available · commit count unknown'),
        findsOneWidget,
      );
      final reads = host.reads.length;
      await tester.tap(find.byTooltip('Changes in this update'));
      await tester.pumpAndSettle();
      expect(find.text('Production host'), findsOneWidget);
      expect(
        find.text(
          'Hermes did not provide change details for this update. Check for updates again later.',
        ),
        findsOneWidget,
      );
      expect(find.text('Commit details'), findsNothing);
      expect(host.reads, hasLength(reads));
      expect(host.posts, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Update backend'), findsOneWidget);
    },
  );

  testWidgets('keeps malformed availability unknown and shows host guidance', (
    tester,
  ) async {
    final host = _UpdateHost()
      ..checkResponse = {
        'current_version': '1.2.3',
        'behind': -1,
        'update_available': 'yes',
        'can_apply': false,
      };
    await showCard(tester, host);
    await check(tester);

    expect(find.text('Update availability unknown.'), findsOneWidget);
    expect(
      find.text('Updates must be applied from the server host.'),
      findsOneWidget,
    );
    expect(find.text('Up to date on main'), findsNothing);
  });

  testWidgets('confirmation names the host and cancel does not post', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);

    expect(find.text('Update backend on Production host?'), findsOneWidget);
    expect(
      find.text(
        'Update the whole server using main. All profiles may disconnect while Hermes restarts.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(host.posts, isEmpty);
  });

  testWidgets('confirmed update rechecks eligibility and starts once', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);
    await tester.tap(find.byTooltip('Update backend').last);
    await tester.pumpAndSettle();

    expect(
      host.reads.where((call) => call.$1 == 'hermes/update/check'),
      hasLength(2),
    );
    expect(host.posts, hasLength(1));
    expect(host.posts.single.$1, 'hermes/update?profile=work');
    expect(
      find.text('Backend update started. Check update progress to follow it.'),
      findsOneWidget,
    );
  });

  testWidgets('fresh check can refuse a previously advertised update', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    host.checkResponse = {
      ..._available,
      'update_available': false,
      'behind': 0,
    };
    await openConfirmation(tester);
    await tester.tap(find.byTooltip('Update backend').last);
    await tester.pumpAndSettle();

    expect(host.posts, isEmpty);
    expect(
      find.text('The server reports no update is available.'),
      findsOneWidget,
    );
  });

  testWidgets('manual status refresh reports disconnection without retrying', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);
    await tester.tap(find.byTooltip('Update backend').last);
    await tester.pumpAndSettle();
    host.statusFails = true;

    await tester.tap(find.byTooltip('Check update progress'));
    await tester.pumpAndSettle();

    expect(
      find.text('Backend update status is unavailable. Check again.'),
      findsOneWidget,
    );
    expect(host.posts, hasLength(1));
  });

  testWidgets('shows terminal outcome and expandable bounded output', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host);
    await check(tester);
    await openConfirmation(tester);
    await tester.tap(find.byTooltip('Update backend').last);
    await tester.pumpAndSettle();
    host.statusResponse = {
      'running': false,
      'pid': 41,
      'exit_code': 0,
      'action_id': 'action-1',
      'lines': ['Downloading', 'Applied core', 'Skipped optional'],
    };
    host.receiptResponse = {
      'receipt': {
        'pid': 41,
        'finished_at': '2026-09-12T12:00:00Z',
        'outcome': 'partial',
      },
      'summary': 'partial',
    };

    await tester.tap(find.byTooltip('Check update progress'));
    await tester.pumpAndSettle();

    expect(
      find.text('The backend update completed only partially.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Update logs'));
    await tester.pumpAndSettle();
    expect(
      find.text('Downloading\nApplied core\nSkipped optional'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(
        SelectableText,
        'Downloading\nApplied core\nSkipped optional',
      ),
      findsOneWidget,
    );
  });

  testWidgets('confirmation cannot cross the retained connection owner', (
    tester,
  ) async {
    final first = _UpdateHost();
    final second = _UpdateHost();
    final firstController = BackendUpdateController(first.gateway);
    final secondController = BackendUpdateController(second.gateway);
    addTearDown(firstController.dispose);
    addTearDown(secondController.dispose);
    late StateSetter replace;
    var current = first;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => Scaffold(body: child),
        home: StatefulBuilder(
          builder: (context, setState) {
            replace = setState;
            return BackendVersionCard(
              updateController: current == first
                  ? firstController
                  : secondController,
              connectionLabel: current == first ? 'First host' : 'Second host',
            );
          },
        ),
      ),
    );
    await check(tester);
    await openConfirmation(tester);

    replace(() => current = second);
    await tester.pump();
    await tester.tap(find.byTooltip('Update backend').last);
    await tester.pumpAndSettle();

    expect(first.posts, isEmpty);
    expect(second.posts, isEmpty);
  });

  testWidgets('external controller remains parent-owned after card disposal', (
    tester,
  ) async {
    final host = _UpdateHost();
    final external = BackendUpdateController(host.gateway);
    await external.checkForUpdate();
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => Scaffold(body: child),
        home: BackendVersionCard(updateController: external),
      ),
    );
    expect(find.text('1.2.3'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    void listener() {}
    expect(() => external.addListener(listener), returnsNormally);
    external.removeListener(listener);
    external.dispose();
  });

  testWidgets('confirmation cannot start a replacement external controller', (
    tester,
  ) async {
    final first = _UpdateHost();
    final second = _UpdateHost();
    final firstController = BackendUpdateController(first.gateway);
    final secondController = BackendUpdateController(second.gateway);
    addTearDown(firstController.dispose);
    addTearDown(secondController.dispose);
    late StateSetter replace;
    var currentController = firstController;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => Scaffold(body: child),
        home: StatefulBuilder(
          builder: (context, setState) {
            replace = setState;
            return BackendVersionCard(updateController: currentController);
          },
        ),
      ),
    );
    await check(tester);
    await openConfirmation(tester);

    replace(() {
      currentController = secondController;
    });
    await tester.pump();
    await tester.tap(find.byTooltip('Update backend').last);
    await tester.pumpAndSettle();

    expect(first.posts, isEmpty);
    expect(second.posts, isEmpty);
  });

  testWidgets(
    'late check response cannot cross retained connection ownership',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final first = _UpdateHost()..pendingCheck = pending;
      final second = _UpdateHost()
        ..checkResponse = {..._available, 'current_version': '4.5.6'};
      final firstController = BackendUpdateController(first.gateway);
      final secondController = BackendUpdateController(second.gateway);
      addTearDown(firstController.dispose);
      addTearDown(secondController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => Scaffold(body: child),
          home: BackendVersionCard(updateController: firstController),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => Scaffold(body: child),
          home: BackendVersionCard(updateController: secondController),
        ),
      );
      pending.complete(_available);
      await tester.pump();

      expect(find.text('1.2.3'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('4.5.6'), findsOneWidget);
    },
  );

  testWidgets('disposed card ignores a late check response', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final host = _UpdateHost()..pendingCheck = pending;
    final controller = BackendUpdateController(host.gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => Scaffold(body: child),
        home: BackendVersionCard(updateController: controller),
      ),
    );
    await tester.pump();
    expect(find.text('Checking for updates…'), findsNothing);
    expect(find.text('Checking…'), findsNothing);
    expect(find.byType(StudioLoading), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Check for updates',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Check for updates'), findsNothing);
    expect(find.byTooltip('Check for updates'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(_available);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions remain usable on a narrow large-text phone', (
    tester,
  ) async {
    final host = _UpdateHost();
    await showCard(tester, host, size: const Size(320, 640), textScale: 2);
    await check(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Update backend'));
    await tester.pumpAndSettle();
    await openConfirmation(tester);
    expect(find.text('Update backend on Production host?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
