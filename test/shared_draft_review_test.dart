import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/attachment_draft.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/shared_draft_review.dart';
import 'package:wing/core/services/android_share_intent_service.dart';
import 'package:wing/core/services/attachment_draft_service.dart';
import 'package:wing/core/services/composer_draft_store.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/profile_browser_fixture.dart';
import 'support/profile_paging_fixture.dart';

Future<ProfileWorkspaceController> _controller(
  ProfileBrowserFixture fixture, {
  AttachmentDraftService? attachments,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final controller = ProfileWorkspaceController(
    connection: SavedConnection(
      id: 'host',
      label: 'Review host',
      host: 'localhost',
      port: 1,
      apiKey: '',
    ),
    connectionIdentity: 'share-review',
    preferences: preferences,
    gatewayFactory: fixture.gateway,
    attachmentService: attachments,
  );
  await controller.initialize();
  return controller;
}

class _FailingAttachments extends AttachmentDraftService {
  int attempts = 0;

  @override
  Future<AttachmentDraft> prepareGenericFile({
    required String sourcePath,
    required String displayName,
    String mediaType = 'application/octet-stream',
    required Iterable<AttachmentDraft> existingDrafts,
  }) async {
    attempts++;
    throw const AttachmentDraftException('The shared file is unavailable.');
  }
}

Future<Future<bool>> _openReview(
  WidgetTester tester,
  ProfileWorkspaceController controller,
  AndroidSharePayload payload, {
  double textScale = 1,
  ProfileChat? initialChat,
  ({ProfileSessionKey key, ComposerDraftSnapshot draft})? recoverableDraft,
}) async {
  Future<bool>? result;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => FilledButton(
          key: const Key('open-review'),
          onPressed: () {
            result = reviewSharedDraft(
              context,
              controller,
              payload,
              initialChat: initialChat,
              recoverableDraft: recoverableDraft,
            );
          },
          child: const Text('Review share'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-review')));
  await tester.pumpAndSettle();
  return result!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'reviews text and files with New chat selected on a large phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = await _controller(ProfileBrowserFixture());
      addTearDown(controller.dispose);

      final result = await _openReview(
        tester,
        controller,
        const AndroidSharePayload(
          text: 'Please review this',
          files: [
            AndroidSharedFile(
              path: '/shared/photo.jpg',
              name: 'photo.jpg',
              mediaType: 'image/jpeg',
              byteLength: 1536,
            ),
          ],
        ),
        textScale: 2,
      );

      expect(find.text('Please review this'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('2 KiB'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Connection: Review host'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Connection: Review host'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('share-destination-new')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('New chat'), findsOneWidget);
      expect(find.byKey(const Key('share-add-to-draft')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    },
  );

  testWidgets('selects a profile and appends to an existing durable draft', (
    tester,
  ) async {
    final fixture = ProfileBrowserFixture();
    final controller = await _controller(fixture);
    addTearDown(controller.dispose);
    await ComposerDraftStore(
      await SharedPreferences.getInstance(),
      connectionIdentity: 'share-review',
    ).write(
      profileName: 'work',
      sessionId: 'newest',
      text: 'Existing draft',
      attachments: const [],
    );

    final result = await _openReview(
      tester,
      controller,
      const AndroidSharePayload(text: 'Shared text'),
    );

    await tester.tap(find.byKey(const ValueKey('share-profile-personal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('work').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-destination-newest')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('share-add-to-draft')));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(controller.current!.scope.profileName, 'work');
    expect(controller.current!.chat!.key.sessionId, 'newest');
    expect(controller.current!.chat!.draft, 'Existing draft\n\nShared text');
    expect(fixture.calls.where((call) => call.$2 == 'prompt.submit'), isEmpty);
  });

  testWidgets('a failed New chat stage stays open and reuses its target', (
    tester,
  ) async {
    final fixture = ProfileBrowserFixture();
    final attachments = _FailingAttachments();
    final controller = await _controller(fixture, attachments: attachments);
    addTearDown(controller.dispose);
    final result = await _openReview(
      tester,
      controller,
      const AndroidSharePayload(
        text: 'Keep this visible',
        files: [
          AndroidSharedFile(
            path: '/missing/report.pdf',
            name: 'report.pdf',
            mediaType: 'application/pdf',
            byteLength: 42,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('share-add-to-draft')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-review-error')), findsOneWidget);
    expect(find.text('Keep this visible'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('New chat (ready)'), findsOneWidget);
    expect(
      fixture.calls.where((call) => call.$2 == 'session.create'),
      hasLength(1),
    );
    expect(attachments.attempts, 1);

    await tester.tap(find.byKey(const Key('share-add-to-draft')));
    await tester.pumpAndSettle();
    expect(
      fixture.calls.where((call) => call.$2 == 'session.create'),
      hasLength(1),
    );
    expect(attachments.attempts, 2);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets(
    'photo staging retries keep the recovered draft and one new chat',
    (tester) async {
      final fixture = ProfileBrowserFixture();
      final attachments = _FailingAttachments();
      final controller = await _controller(fixture, attachments: attachments);
      addTearDown(controller.dispose);
      final source = ProfileSessionKey(
        controller.current!.scope,
        'expired-draft',
      );
      final drafts = ComposerDraftStore(
        await SharedPreferences.getInstance(),
        connectionIdentity: 'share-review',
      );
      await drafts.write(
        profileName: source.workspace.profileName,
        sessionId: source.sessionId,
        text: 'Keep the original draft',
        attachments: [],
      );
      final result = await _openReview(
        tester,
        controller,
        const AndroidSharePayload(
          files: [
            AndroidSharedFile(
              path: '/missing/capture.jpg',
              name: 'capture.jpg',
              mediaType: 'application/octet-stream',
              byteLength: 42,
            ),
          ],
        ),
        recoverableDraft: (
          key: source,
          draft: (await controller.savedDraft(source))!,
        ),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byKey(const Key('share-add-to-draft')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('share-review-error')), findsOneWidget);
        expect(controller.current!.chat!.draft, 'Keep the original draft');
        expect(
          fixture.calls.where((call) => call.$2 == 'session.create'),
          hasLength(1),
        );
        expect(
          fixture.calls.where((call) => call.$2 == 'prompt.submit'),
          isEmpty,
        );
      }
      expect(attachments.attempts, 2);
      final recoveredKey = controller.current!.chat!.key;
      expect(
        (await controller.savedDraft(recoveredKey))!.text,
        'Keep the original draft',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    },
  );

  testWidgets('loads the next saved-chat page without another API', (
    tester,
  ) async {
    final fixture = ProfilePagingFixture()..count = 75;
    fixture.pageFailures.add(('personal', 50));
    final controller = await _controller(fixture);
    addTearDown(controller.dispose);
    final result = await _openReview(
      tester,
      controller,
      const AndroidSharePayload(text: 'Shared'),
    );

    expect(controller.current!.sessions, hasLength(50));
    await tester.scrollUntilVisible(
      find.byKey(const Key('share-load-more')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('share-load-more')), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-load-more')));
    await tester.pumpAndSettle();

    expect(controller.current!.sessions, hasLength(50));
    expect(find.byKey(const Key('share-review-error')), findsOneWidget);
    expect(find.text('Retry more chats'), findsOneWidget);

    fixture.pageFailures.clear();
    await tester.tap(find.byKey(const Key('share-load-more')));
    await tester.pumpAndSettle();

    expect(controller.current!.sessions, hasLength(75));
    expect(
      fixture.reads.where(
        (read) => read.$1 == 'sessions' && read.$2['offset'] == '50',
      ),
      hasLength(2),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('preselects the supplied saved chat outside the first page', (
    tester,
  ) async {
    final fixture = ProfilePagingFixture()..count = 75;
    final controller = await _controller(fixture);
    addTearDown(controller.dispose);
    await controller.openSession(
      ProfileSessionKey(controller.current!.scope, 'chat-60'),
    );
    final initialChat = controller.current!.chat!;
    final result = await _openReview(
      tester,
      controller,
      const AndroidSharePayload(text: 'Append to the older chat'),
      initialChat: initialChat,
    );

    expect(
      find.byKey(const ValueKey('share-destination-chat-60')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'chat-60',
    );
    await tester.tap(find.byKey(const Key('share-add-to-draft')));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(initialChat.draft, 'Append to the older chat');
    expect(fixture.calls.where((call) => call.$2 == 'session.create'), isEmpty);
  });

  testWidgets('does not expose an unowned initial chat as a destination', (
    tester,
  ) async {
    final controller = await _controller(ProfileBrowserFixture());
    addTearDown(controller.dispose);
    final wrongOwner = ProfileChat(
      key: ProfileSessionKey(
        WorkspaceScope(
          connectionId: 'other-connection',
          connectionIdentity: 'other-identity',
          profileName: 'personal',
        ),
        'chat-60',
      ),
      runtimeId: 'other-runtime',
      title: 'Unowned chat',
    );
    final result = await _openReview(
      tester,
      controller,
      const AndroidSharePayload(text: 'Choose safely'),
      initialChat: wrongOwner,
    );

    expect(
      find.byKey(const ValueKey('share-destination-chat-60')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('share-destination-new')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
