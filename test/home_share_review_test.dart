import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/android_share_intent_service.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Credentials implements CredentialStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  String? readCached(String key) => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<ConnectionManager> _manager() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ConnectionManager.create(prefs, credentialStore: _Credentials());
}

ProfileWorkspaceController _controller(
  SavedConnection connection,
  SharedPreferences prefs, {
  Set<String> missingSessions = const {},
}) {
  final controller = ProfileWorkspaceController(
    connection: connection,
    connectionIdentity: 'home-share-${connection.id}',
    preferences: prefs,
    gatewayFactory: (scope) => ProfileGateway(
      scope: scope,
      discover: () async => const ProfileDiscovery(
        profiles: [HermesProfile(name: 'default')],
        currentName: 'default',
        activeName: 'default',
      ),
      get: (_, query) async => {
        'sessions': <Map<String, dynamic>>[],
        'offset': int.parse(query['offset']!),
        'limit': int.parse(query['limit']!),
        'total': 0,
      },
      rpc: (method, params) async {
        if (method == 'session.resume' &&
            missingSessions.contains(params['session_id'])) {
          throw JsonRpcError('session.resume', 'session not found', code: 4007);
        }
        return method == 'session.create' || method == 'session.resume'
            ? {
                'session_id': 'runtime-${connection.id}',
                'stored_session_id': method == 'session.resume'
                    ? params['session_id']
                    : 'stored-${connection.id}',
                'session_key': method == 'session.resume'
                    ? params['session_id']
                    : 'stored-${connection.id}',
                'info': {'profile_name': 'default'},
              }
            : {'projects': <Map<String, dynamic>>[]};
      },
    ),
  );
  return controller;
}

Future<void> _pumpHome(
  WidgetTester tester,
  ConnectionManager manager,
  AndroidShareIntentService shareIntents, {
  Set<String> missingSessions = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        connManager: manager,
        shareIntents: shareIntents,
        profileController: (connection) => _controller(
          connection,
          manager.prefs,
          missingSessions: missingSessions,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidShareIntentService.channelName);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'acknowledgeShare') {
            expectSync((call.arguments as Map)['id'], isNotEmpty);
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'share chooses its saved connection and acknowledges only after Add to draft',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final manager = await _manager();
      await manager.saveConnection('Work', 'work.local', 8642, 'work-key');
      await manager.saveConnection('Home', 'home.local', 8642, 'home-key');
      final shares = AndroidShareIntentService();
      addTearDown(shares.dispose);
      final payload = const AndroidSharePayload(
        id: 'share-work-1',
        text: 'Shared from another app',
      );

      await _pumpHome(tester, manager, shares);
      shares.pendingShare.value = payload;
      await tester.pump();

      expect(
        find.text('Choose a connection for this shared draft'),
        findsOneWidget,
      );
      expect(shares.pendingShare.value, same(payload));
      final workChoice = find
          .ancestor(of: find.text('Work'), matching: find.byType(ListTile))
          .last;
      tester.widget<ListTile>(workChoice).onTap!();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(find.text('Add shared content'), findsOneWidget);
      expect(find.text('Connection: Work'), findsOneWidget);
      expect(shares.pendingShare.value, same(payload));
      expect(find.byType(ProfileWorkspaceScreen), findsNothing);

      await tester.tap(find.byKey(const Key('share-add-to-draft')));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
      expect(shares.pendingShare.value, isNull);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('profile-message-composer')),
            )
            .controller!
            .text,
        payload.text,
      );
    },
  );

  testWidgets(
    'cancel keeps Home review controls and Discard clears the share',
    (tester) async {
      final manager = await _manager();
      await manager.saveConnection('Work', 'work.local', 8642, 'work-key');
      final shares = AndroidShareIntentService();
      addTearDown(shares.dispose);
      final payload = const AndroidSharePayload(
        id: 'share-pending-1',
        text: 'Keep pending until reviewed',
      );

      await _pumpHome(tester, manager, shares);
      shares.pendingShare.value = payload;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Add shared content'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Shared draft ready'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(shares.pendingShare.value, same(payload));

      await tester.tap(find.text('Discard'));
      await tester.pump();
      expect(shares.pendingShare.value, isNull);
      expect(find.text('Shared draft ready'), findsNothing);
    },
  );

  testWidgets('ACK failure keeps the staged draft and incoming share visible', (
    tester,
  ) async {
    const channel = MethodChannel(AndroidShareIntentService.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'acknowledgeShare') {
            throw PlatformException(code: 'ack-failed');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final manager = await _manager();
    await manager.saveConnection('Work', 'work.local', 8642, 'work-key');
    final shares = AndroidShareIntentService();
    addTearDown(shares.dispose);
    const payload = AndroidSharePayload(
      id: 'share-ack-failure',
      text: 'Do not lose this staged draft',
    );

    await _pumpHome(tester, manager, shares);
    shares.pendingShare.value = payload;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-add-to-draft')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileWorkspaceScreen), findsOneWidget);
    final composer = find.byKey(const Key('profile-message-composer'));
    expect(composer, findsOneWidget);
    expect(tester.widget<TextField>(composer).controller!.text, payload.text);
    expect(shares.pendingShare.value, same(payload));
    expect(find.textContaining('could not be cleared'), findsOneWidget);
  });

  testWidgets('failed discard preserves the Home review controls', (
    tester,
  ) async {
    const channel = MethodChannel(AndroidShareIntentService.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'acknowledgeShare') {
            throw PlatformException(code: 'discard-failed');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final manager = await _manager();
    await manager.saveConnection('Work', 'work.local', 8642, 'work-key');
    final shares = AndroidShareIntentService();
    addTearDown(shares.dispose);
    const payload = AndroidSharePayload(
      id: 'share-discard-failure',
      text: 'Keep this pending',
    );

    await _pumpHome(tester, manager, shares);
    shares.pendingShare.value = payload;
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(shares.pendingShare.value, same(payload));
    expect(find.text('Shared draft ready'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.textContaining('could not be discarded'), findsOneWidget);
  });

  testWidgets('camera review restores its original connection and saved chat', (
    tester,
  ) async {
    final manager = await _manager();
    await manager.saveConnection('Work', 'work.local', 8642, 'work-key');
    await manager.saveConnection('Home', 'home.local', 8642, 'home-key');
    final work = manager.getConnections().firstWhere(
      (connection) => connection.label == 'Work',
    );
    final shares = AndroidShareIntentService();
    addTearDown(shares.dispose);
    final payload = AndroidSharePayload(
      id: 'camera-original',
      text: 'Captured content',
      target: {
        'connection': work.id,
        'connection_identity': 'home-share-${work.id}',
        'profile': 'default',
        'session': 'original-chat',
      },
    );
    await _pumpHome(tester, manager, shares);
    shares.pendingShare.value = payload;
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a connection for this shared draft'),
      findsNothing,
    );
    expect(find.text('Connection: Work'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'original-chat',
    );
    await tester.tap(find.byKey(const Key('share-add-to-draft')));
    await tester.pumpAndSettle();
    final workspace = tester.widget<ProfileWorkspaceScreen>(
      find.byType(ProfileWorkspaceScreen),
    );
    expect(workspace.controller.current!.chat!.key.sessionId, 'original-chat');
    expect(workspace.controller.current!.chat!.draft, payload.text);
    expect(shares.pendingShare.value, isNull);
  });

  testWidgets('cold camera recovery keeps the saved text in its new draft', (
    tester,
  ) async {
    final manager = await _manager();
    await manager.saveConnection('Work', 'work.local', 8642, 'work-key');
    final connection = manager.getConnections().single;
    final drafts = ComposerDraftStore(
      manager.prefs,
      connectionIdentity: 'home-share-${connection.id}',
    );
    await drafts.write(
      profileName: 'default',
      sessionId: 'expired-unsent',
      text: 'Cold camera draft check',
      attachments: [],
    );
    final shares = AndroidShareIntentService();
    addTearDown(shares.dispose);
    await _pumpHome(
      tester,
      manager,
      shares,
      missingSessions: {'expired-unsent'},
    );
    shares.pendingShare.value = AndroidSharePayload(
      id: 'cold-camera',
      text: 'Captured content',
      target: {
        'connection': connection.id,
        'connection_identity': 'home-share-${connection.id}',
        'profile': 'default',
        'session': 'expired-unsent',
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('New chat with recovered draft'), findsOneWidget);
    expect(find.text('Cold camera draft check'), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-add-to-draft')));
    await tester.pumpAndSettle();
    final workspace = tester.widget<ProfileWorkspaceScreen>(
      find.byType(ProfileWorkspaceScreen),
    );
    expect(
      workspace.controller.current!.chat!.draft,
      'Cold camera draft check\n\nCaptured content',
    );
    expect(
      (await drafts.read(
        profileName: 'default',
        sessionId: workspace.controller.current!.chat!.key.sessionId,
      ))!.text,
      'Cold camera draft check\n\nCaptured content',
    );
    expect(
      await drafts.read(profileName: 'default', sessionId: 'expired-unsent'),
      isNull,
    );
    expect(shares.pendingShare.value, isNull);
  });

  testWidgets(
    'changed camera connection requires explicit destination review',
    (tester) async {
      final manager = await _manager();
      await manager.saveConnection('Work', 'work.local', 8642, 'work-key');
      final work = manager.getConnections().single;
      final shares = AndroidShareIntentService();
      addTearDown(shares.dispose);
      final payload = AndroidSharePayload(
        id: 'camera-changed',
        text: 'Keep captured content',
        target: {
          'connection': work.id,
          'connection_identity': 'previous-server-settings',
          'profile': 'default',
          'session': 'original-chat',
        },
      );
      await _pumpHome(tester, manager, shares);
      shares.pendingShare.value = payload;
      await tester.pumpAndSettle();
      expect(
        find.textContaining('original chat could not be reopened'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('share-destination-original-chat')),
        findsNothing,
      );
      expect(shares.pendingShare.value, same(payload));
      expect(find.byType(ProfileWorkspaceScreen), findsNothing);
    },
  );
}
