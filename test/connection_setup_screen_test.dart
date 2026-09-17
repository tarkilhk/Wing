import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/connection_setup_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/connection_setup_probe.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/playful_portrait.dart';
import 'package:wing/core/widgets/connection_icon_picker.dart';
import 'package:wing/core/widgets/wing_wordmark.dart';

import 'support/connection_probe_fixture.dart';

const _captureEnabled = bool.fromEnvironment('CAPTURE_CONNECTION_SETUP');
const _frame = Key('connection-render');

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester, {
  ConnectionProbeFixture? fixture,
  Future<SavedConnection> Function(SavedConnection)? save,
  Future<void> Function(ConnectionIcon)? saveIcon,
  void Function(SavedConnection)? candidate,
  SavedConnection? initial,
  Brightness brightness = Brightness.light,
  WorkspaceAccent accent = WorkspaceAccent.mint,
  double scale = 1,
  double keyboard = 0,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: profileWorkspaceTheme(wingTheme(brightness), accent: accent),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: ConnectionSetupScreen(
          initialConnection: initial,
          onSaveIcon: initial == null ? null : saveIcon ?? (_) async {},
          createProbe: (connection) {
            candidate?.call(connection);
            return fixture ?? ConnectionProbeFixture();
          },
          onSave: save ?? (connection) async => connection,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (initial == null) await _tap(tester, 'Use an address');
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('connection-address')),
    'https://hermes.example.com/agent/',
  );
  await _tap(tester, 'Continue');
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('connection-username')), 'alex');
  await tester.enterText(
    find.byKey(const Key('connection-password')),
    ' secret with spaces ',
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_captureEnabled) return;
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  final context = tester.element(find.byKey(_frame));
  await tester.runAsync(() async {
    await Future.wait(
      images.map((image) => precacheImage(image.image, context)),
    );
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frame),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/connection-review')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_captureEnabled) return;
    const directory = String.fromEnvironment('CAPTURE_FONT_DIR');
    if (directory.isEmpty) {
      throw StateError('Capture requires CAPTURE_FONT_DIR.');
    }
    for (final entry in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final name in entry.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(File('$directory/$name').readAsBytesSync()),
          ),
        );
      }
      await loader.load();
    }
  });

  testWidgets(
    'sign-in icon saves an existing connection without verification',
    (tester) async {
      final initial = SavedConnection(
        id: 'saved',
        label: 'Office',
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        apiKey: '',
        icon: ConnectionIcon.cloud,
      );
      final fixture = ConnectionProbeFixture();
      var savedIcon = initial.icon;
      var saves = 0;
      var fail = true;
      await _pump(
        tester,
        initial: initial,
        fixture: fixture,
        save: (c) async {
          saves++;
          return c;
        },
        saveIcon: (icon) async {
          if (fail) throw StateError('disk unavailable');
          savedIcon = icon;
        },
      );
      await _tap(tester, 'Continue');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Change connection icon'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connection-icon-rocket')));
      await _tap(tester, 'Save icon');
      await tester.pumpAndSettle();
      expect(savedIcon, ConnectionIcon.cloud);
      expect(find.text('Couldn’t save this icon. Try again.'), findsOneWidget);
      fail = false;
      await _tap(tester, 'Save icon');
      await tester.pumpAndSettle();
      expect(savedIcon, ConnectionIcon.rocket);
      expect(
        tester
            .widget<ConnectionIconBadge>(find.byType(ConnectionIconBadge))
            .icon,
        ConnectionIcon.rocket,
      );
      expect(fixture.calls, isEmpty);
      expect(saves, 0);
      await tester.tap(find.byTooltip('Change connection icon'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('connection-icon-rocket')),
            )
            .isSelected,
        isTrue,
      );
      await _tap(tester, 'Cancel');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(savedIcon, ConnectionIcon.rocket);
    },
  );

  testWidgets('a new connection keeps its sign-in icon until final save', (
    tester,
  ) async {
    SavedConnection? saved;
    await _pump(
      tester,
      save: (c) async {
        saved = c;
        return c;
      },
    );
    await _signIn(tester);
    await tester.tap(find.byTooltip('Change connection icon'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('connection-icon-home')));
    await _tap(tester, 'Save icon');
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await _tap(tester, 'Check connection');
    await tester.pumpAndSettle();
    await _tap(tester, 'Save and open');
    await tester.pumpAndSettle();
    expect(saved?.icon, ConnectionIcon.home);
  });

  testWidgets(
    'one address, explicit sign-in, real checks, then a separate save',
    (tester) async {
      final fixture = ConnectionProbeFixture();
      SavedConnection? checked;
      SavedConnection? saved;
      await _pump(
        tester,
        fixture: fixture,
        candidate: (c) => checked = c,
        save: (c) async {
          saved = c;
          return c;
        },
      );
      expect(find.byType(PlayfulPortrait), findsOneWidget);
      expect(find.byType(WingFeathers), findsOneWidget);
      expect(find.text('Port'), findsNothing);
      expect(find.text('Access headers'), findsNothing);
      await _signIn(tester);
      expect(fixture.calls, isEmpty);
      await _tap(tester, 'Check connection');
      await tester.pumpAndSettle();
      expect(find.text('Connection verified'), findsOneWidget);
      expect(checked?.port, 443);
      expect(checked?.dashboardPort, 443);
      expect(checked?.dashboardPrefix, '/agent');
      expect(checked?.dashboardPassword, ' secret with spaces ');
      expect(checked?.desktopGatewayUrl, isNull);
      expect(checked?.apiKey, isEmpty);
      expect(saved, isNull);
      await tester.enterText(find.byKey(const Key('connection-name')), 'Home');
      await _tap(tester, 'Connection icon');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connection-icon-home')));
      await _tap(tester, 'Save icon');
      await tester.pumpAndSettle();
      await _tap(tester, 'Save and open');
      await tester.pumpAndSettle();
      expect(saved?.label, 'Home');
      expect(saved?.icon, ConnectionIcon.home);
      expect(fixture.calls, ConnectionCheck.values);
    },
  );

  testWidgets(
    'password mode cannot accidentally attempt unauthenticated access',
    (tester) async {
      final fixture = ConnectionProbeFixture();
      await _pump(tester, fixture: fixture);
      await tester.enterText(
        find.byKey(const Key('connection-address')),
        'https://hermes.example.com',
      );
      await _tap(tester, 'Continue');
      await tester.pumpAndSettle();
      await _tap(tester, 'Check connection');
      await tester.pumpAndSettle();
      expect(find.text('Enter your dashboard username.'), findsOneWidget);
      expect(find.text('Enter your dashboard password.'), findsOneWidget);
      expect(fixture.calls, isEmpty);
    },
  );

  testWidgets('back during a check cancels and late results cannot advance', (
    tester,
  ) async {
    final fixture = ConnectionProbeFixture()
      ..discoveryGate = Completer<ProfileDiscovery>();
    await _pump(tester, fixture: fixture);
    await _signIn(tester);
    await _tap(tester, 'Check connection');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    fixture.discoveryGate!.complete(connectionDiscovery);
    await tester.pumpAndSettle();
    expect(fixture.closed, isTrue);
    expect(find.text('Sign in to Hermes'), findsOneWidget);
    expect(find.text('Connection verified'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('connection-password')))
          .controller!
          .text,
      ' secret with spaces ',
    );
  });

  testWidgets(
    'save failure preserves the verified draft and retries only storage',
    (tester) async {
      final fixture = ConnectionProbeFixture();
      var saves = 0;
      await _pump(
        tester,
        fixture: fixture,
        save: (c) async {
          saves++;
          throw const CredentialStorageException('private storage error');
        },
      );
      await _signIn(tester);
      await _tap(tester, 'Check connection');
      await tester.pumpAndSettle();
      await _tap(tester, 'Save and open');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Couldn’t save this connection on this device'),
        findsOneWidget,
      );
      expect(find.textContaining('private storage error'), findsNothing);
      await _tap(tester, 'Save and open');
      await tester.pumpAndSettle();
      expect(saves, 2);
      expect(fixture.calls, ConnectionCheck.values);
      expect(find.text('Connection verified'), findsOneWidget);
    },
  );

  testWidgets(
    'custom setup applies explicit proxy auth and a same-host chat path',
    (tester) async {
      SavedConnection? checked;
      await _pump(tester, candidate: (c) => checked = c);
      await _signIn(tester);
      await _tap(tester, 'Custom setup');
      await tester.pumpAndSettle();
      await _tap(tester, 'My access proxy handles sign-in');
      await _tap(tester, 'Use a separate chat address');
      await tester.enterText(
        find.byKey(const Key('connection-chat-address')),
        'https://hermes.example.com:8443/chat/',
      );
      await _tap(tester, 'Use these settings');
      await tester.pumpAndSettle();
      expect(find.text('Connect through your proxy'), findsOneWidget);
      await _tap(tester, 'Check connection');
      await tester.pumpAndSettle();
      expect(checked?.dashboardProxied, isTrue);
      expect(checked?.dashboardUsername, isNull);
      expect(checked?.dashboardPassword, isNull);
      expect(
        checked?.desktopGatewayUrl,
        'https://hermes.example.com:8443/chat',
      );
    },
  );

  testWidgets(
    'editing keeps current secrets and can remove custom chat routing',
    (tester) async {
      final initial = SavedConnection(
        id: 'saved',
        label: 'Office',
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        apiKey: '',
        dashboardPortOverride: 443,
        dashboardUsername: 'alex',
        dashboardPassword: ' exact password ',
        desktopGatewayUrl: 'https://chat.example.com',
        gatewayHeaders: {'X-Access': 'hidden-secret'},
      );
      SavedConnection? checked;
      await _pump(tester, initial: initial, candidate: (c) => checked = c);
      await _tap(tester, 'Continue');
      await tester.pumpAndSettle();
      await _tap(tester, 'Custom setup');
      await tester.pumpAndSettle();
      expect(find.text('hidden-secret'), findsNothing);
      await _tap(tester, 'Use a separate chat address');
      await _tap(tester, 'Use these settings');
      await tester.pumpAndSettle();
      await _tap(tester, 'Check connection');
      await tester.pumpAndSettle();
      expect(checked?.desktopGatewayUrl, isNull);
      expect(checked?.gatewayHeaders, initial.gatewayHeaders);
      expect(checked?.dashboardPassword, ' exact password ');
      expect(find.text('Save changes'), findsOneWidget);
    },
  );

  if (_captureEnabled) {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name} portrait connection review', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pump(tester, brightness: brightness);
        await _capture(tester, '${brightness.name}-portrait-address');
        await _signIn(tester);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-portrait-signin');
        await _tap(tester, 'Check connection');
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-portrait-verified');
      });
    }
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${brightness.name} journey fits 320dp at ${scale}x including keyboard and failure',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final fixture = ConnectionProbeFixture()
            ..failAt = ConnectionCheck.chat;
          await _pump(
            tester,
            fixture: fixture,
            brightness: brightness,
            scale: scale,
          );
          await _capture(tester, '${brightness.name}-address-${scale}x');
          await _signIn(tester);
          await _capture(tester, '${brightness.name}-signin-${scale}x');
          await _tap(tester, 'Check connection');
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Profiles are available, but live chat'),
            findsOneWidget,
          );
          await _capture(tester, '${brightness.name}-recovery-${scale}x');
          await _tap(tester, 'Edit sign-in or custom setup');
          await tester.pumpAndSettle();
          await _tap(tester, 'Custom setup');
          await tester.pumpAndSettle();
          await _tap(tester, 'Use a separate chat address');
          await tester.pumpAndSettle();
          await _capture(tester, '${brightness.name}-custom-${scale}x');
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox());
          await _pump(
            tester,
            brightness: brightness,
            scale: scale,
            keyboard: 260,
          );
          await _signIn(tester);
          await tester.pumpAndSettle();
          final primary = find.byKey(const Key('connection-primary'));
          await tester.ensureVisible(primary);
          await tester.pumpAndSettle();
          final rect = tester.getRect(primary);
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.bottom, lessThanOrEqualTo(380));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
