import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/attachment_draft_service.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/image_clipboard.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

import 'profile_workspace_controller_test.dart' show Host;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  late Host host;
  late ProfileWorkspaceController controller;
  late ProfileChat chat;
  late SharedPreferences preferences;
  final png = image.encodePng(image.Image(width: 3, height: 2));
  const composerKey = Key('profile-message-composer');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    cache = await Directory.systemTemp.createTemp('hermes-paste-test-');
    host = Host();
    controller = ProfileWorkspaceController(
      connection: SavedConnection(
        id: 'host',
        label: 'Host',
        host: 'localhost',
        port: 1,
        apiKey: '',
      ),
      connectionIdentity: 'paste-test',
      preferences: preferences,
      gatewayFactory: host.gateway,
      attachmentService: AttachmentDraftService(
        cacheDirectoryProvider: () async => cache,
      ),
    );
    await controller.initialize();
    chat = await controller.createChat();
    chat.status = ProfileTurnStatus.completed;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ImageClipboard.channel, null);
    controller.dispose();
    await cache.delete(recursive: true);
  });

  test(
    'paste stages a sanitized image with saved text and never submits',
    () async {
      await controller.updateDraft(chat, 'Describe this');
      await controller.addPastedImage(chat, () async => png);
      final draft = chat.attachments.single;
      expect(draft.isImage, isTrue);
      expect(draft.sanitized, isTrue);
      expect(draft.name, 'Pasted image.png');
      expect(
        image.decodeImage(await File(draft.cachedPath).readAsBytes())!.width,
        3,
      );
      expect(chat.draft, 'Describe this');
      expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
      final store = ComposerDraftStore(
        preferences,
        connectionIdentity: 'paste-test',
      );
      expect(store.summaries(profileName: 'a').single.attachmentCount, 1);
      await controller.removeAttachment(chat, draft);
      expect(await File(draft.cachedPath).exists(), isFalse);
    },
  );

  test(
    'pending clipboard read reserves its original chat across chat switches',
    () async {
      final read = Completer<Uint8List>();
      final pending = controller.addPastedImage(chat, () => read.future);
      expect(controller.canAddAttachment(chat), isFalse);
      final other = await controller.createChat();
      read.complete(png);
      await pending;
      expect(chat.attachments, hasLength(1));
      expect(other.attachments, isEmpty);
      expect(controller.canAddAttachment(chat), isTrue);
    },
  );

  test(
    'invalid and unavailable clipboard data leaves the draft intact',
    () async {
      await controller.updateDraft(chat, 'Keep this');
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await expectLater(
          controller.addPastedImage(chat, () async => bytes),
          throwsA(isA<AttachmentDraftException>()),
        );
      }
      await expectLater(
        controller.addPastedImage(
          chat,
          () async => throw StateError('expired'),
        ),
        throwsStateError,
      );
      expect(chat.draft, 'Keep this');
      expect(chat.attachments, isEmpty);
      expect(await cache.list().toList(), isEmpty);
      expect(controller.canAddAttachment(chat), isTrue);
    },
  );

  test('pasted images enforce the existing attachment count limit', () async {
    for (var i = 0; i < maxRemoteAttachmentDrafts; i++) {
      await controller.addPastedImage(chat, () async => png);
    }
    await expectLater(
      controller.addPastedImage(chat, () async => png),
      throwsA(isA<AttachmentDraftException>()),
    );
    expect(chat.attachments, hasLength(maxRemoteAttachmentDrafts));
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileWorkspaceScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'pasted and picked images share left-aligned removable thumbnails',
    (tester) async {
      await tester.runAsync(() async {
        await controller.addPastedImage(chat, () async => png);
        final picked = File('${cache.path}/picked.jpg');
        await picked.writeAsBytes(
          image.encodeJpg(image.Image(width: 4, height: 3)),
        );
        await controller.addAttachment(chat, picked.path, 'picked.jpg');
      });
      await show(tester);
      final thumbnails = find.byKey(const ValueKey('composer-image-thumbnail'));
      expect(thumbnails, findsNWidgets(2));
      expect(find.text('Pasted image.png'), findsNothing);
      expect(find.text('picked.jpg'), findsNothing);
      final composer = tester.getRect(
        find.byKey(const ValueKey('conversation-composer')),
      );
      final first = tester.getRect(thumbnails.first);
      expect(first.left - composer.left, lessThan(24));
      expect(first.width, inInclusiveRange(64, 96));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Remove Pasted image.png'));
      });
      await tester.pumpAndSettle();
      expect(chat.attachments.single.name, 'picked.jpg');
    },
  );

  testWidgets('keyboard advertises image types and inserts into the draft', (
    tester,
  ) async {
    await show(tester);
    final field = tester.widget<TextField>(find.byKey(composerKey));
    final config = field.contentInsertionConfiguration!;
    expect(config.allowedMimeTypes, ImageClipboard.mimeTypes);
    await tester.tap(find.byKey(composerKey));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('TextInputClient.performAction', [
            -1,
            'TextInputAction.commitContent',
            {
              'mimeType': 'image/png',
              'uri': 'content://keyboard/image',
              'data': png,
            },
          ]),
        ),
        (_) {},
      );
      while (!controller.canAddAttachment(chat)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(chat.attachments.single.isImage, isTrue);
    expect(
      find.byKey(const ValueKey('composer-image-thumbnail')),
      findsOneWidget,
    );
    expect(host.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
  });

  testWidgets(
    'unreadable keyboard content shows an error without changing text',
    (tester) async {
      await controller.updateDraft(chat, 'Keep this');
      await show(tester);
      final field = tester.widget<TextField>(find.byKey(composerKey));
      field.contentInsertionConfiguration!.onContentInserted(
        const KeyboardInsertedContent(
          mimeType: 'image/png',
          uri: 'content://expired/image',
        ),
      );
      await tester.pumpAndSettle();
      expect(chat.draft, 'Keep this');
      expect(chat.attachments, isEmpty);
      expect(find.textContaining('Unable to paste this image'), findsOneWidget);
    },
  );

  testWidgets('image-only clipboard exposes Paste in an empty composer', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ImageClipboard.channel,
      (call) async {
        calls.add(call.method);
        return call.method == 'hasImage' ? true : png;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester);
    await tester.longPress(find.byKey(composerKey));
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);
    expect(calls, ['hasImage']);
    await tester.runAsync(() async {
      await tester.tap(find.text('Paste'));
      while (!controller.canAddAttachment(chat)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(calls, ['hasImage', 'readImage']);
    expect(chat.attachments, hasLength(1));
  });

  testWidgets('ordinary text still pastes at the selection', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ImageClipboard.channel,
      (call) async => false,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.hasStrings') return {'value': true};
        if (call.method == 'Clipboard.getData') return {'text': 'Copied text'};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester);
    await tester.longPress(find.byKey(composerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(chat.draft, 'Copied text');
    expect(chat.attachments, isEmpty);
  });
}
