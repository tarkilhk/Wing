import 'support/wing_client_identity_fixture.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:wing/core/models/profile_session_key.dart';
import 'package:wing/core/models/chat_output.dart';
import 'package:wing/core/presentation/skill_document.dart';
import 'package:wing/core/screens/profile_transcript.dart';
import 'package:wing/core/widgets/activity/skill_document_viewer.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/owned_remote_files.dart';
import 'package:wing/core/services/remote_files_client.dart';
import 'package:wing/core/services/transcript_resource_session.dart';
import 'package:wing/core/screens/chat_outputs_screen.dart';
import 'package:wing/core/widgets/chat_image_preview.dart';
import 'package:wing/core/widgets/chat_inline_image.dart';
import 'package:wing/core/widgets/user_message_attachment.dart';
import 'package:wing/core/models/user_message_content.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wing/core/widgets/studio_loading.dart';
import 'package:wing/core/widgets/studio_error.dart';
import 'package:wing/core/widgets/profile_tool_activity.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/widgets/source_code_text.dart';
import 'package:wing/core/widgets/subagent_timeline.dart';
import 'package:wing/core/services/profile_supervision_session.dart';
import 'package:wing/core/services/app_preferences.dart';
import 'package:wing/core/services/connection_access.dart';
import 'package:flutter/material.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/activity_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/profile_subagent_panel.dart';
import 'package:wing/core/widgets/profile_live_work_dock.dart';
import 'package:wing/core/widgets/profile_live_execution.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_connection_identity_test.dart' show identityTestConnection;
import 'support/profile_actions_fixture.dart';
import 'support/composer_fixture.dart' show emitChatEvent;
import 'helpers/pump_markdown_widget.dart';

class _SubagentFixture extends ProfileActionsFixture {
  List<Map<String, dynamic>>? childMessages;
  List<Map<String, dynamic>>? nestedMessages;
  Completer<void>? transcriptGate;
  Completer<void>? skillGate;
  Completer<void>? replayGate;
  bool transcriptAvailable = true;
  bool transcriptFails = false;
  String childResourceId = 'child-session';
  final childEvents = <Map<String, dynamic>>[];
  int listCalls = 0;
  Completer<void>? steerGate;
  bool acceptSteer = false;
  bool failSteer = false;
  bool findInterrupt = false;
  bool failInterrupt = false;
  bool emptyList = false;
  double? startedAt;
  List<Map<String, dynamic>>? rows;
  final requests = <(String, Map<String, dynamic>)>[];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      loadClientIdentity: loadTestWingClientIdentity,
      scope: scope,
      discover: base.discover,
      get: (path, query) async {
        if (path == 'skills') await skillGate?.future;
        if (path == 'sessions/child-session/messages' ||
            path == 'sessions/nested-session/messages') {
          final nested = path.contains('nested-session');
          final messages = nested ? nestedMessages : childMessages;
          return {
            'session_id': nested ? 'nested-session' : 'child-session',
            'messages':
                messages?.reversed.toList() ??
                [
                  {
                    'id': 101,
                    'role': 'assistant',
                    'content': 'Child saved evidence',
                  },
                ],
            'pagination': {
              'offset': int.parse(query['offset']!),
              'limit': int.parse(query['limit']!),
              'returned': messages?.length ?? 1,
              'order': 'latest',
            },
          };
        }
        return base.read(path, query);
      },
      rpc: (method, params) async {
        requests.add((method, params));
        if (method == 'session.transcript') {
          expectSync(params['order'], 'latest');
          expectSync(params['limit'], 100);
          expectSync(params['subagent_id'], isNotNull);
          await transcriptGate?.future;
          if (transcriptFails) {
            throw StateError('Transcript storage unavailable');
          }
          final nested = params['subagent_id'] == 'nested-agent';
          final messages =
              (nested ? nestedMessages : childMessages) ??
              [
                {
                  'id': 101,
                  'role': 'assistant',
                  'content': 'Child saved evidence',
                },
              ];
          return {
            'session_id': params['session_id'],
            'subagent_id': params['subagent_id'],
            'available': transcriptAvailable,
            'running': true,
            'child_session_id': transcriptAvailable
                ? (nested ? 'nested-session' : childResourceId)
                : null,
            'rows': [
              if (transcriptAvailable)
                for (final row in messages)
                  {
                    ...row,
                    'row_id': row['id'],
                    'row_kind': 'message',
                    'text': row['content'] ?? '',
                  },
            ],
            'next_cursor': null,
            'reset': true,
          };
        }
        final id = params['session_id'];
        final isChild = {
          'child-session',
          'child-successor',
          'nested-session',
        }.contains(id);
        final events = id == 'nested-session'
            ? <Map<String, dynamic>>[]
            : childEvents;
        if (method == 'session.resume' && isChild) {
          expectSync(params['display_projection'], isTrue);
          expectSync(params.containsKey('lazy'), isFalse);
          expectSync(params.containsKey('omit_messages'), isFalse);
          return {
            'session_id': id,
            'stored_session_id': id,
            'replay_epoch': 'child-epoch',
            'last_sequence': events.length,
            'running': true,
          };
        }
        if (method == 'session.events.since' && isChild) {
          await replayGate?.future;
          expectSync(params['replay_epoch'], 'child-epoch');
          return {
            'replay_epoch': 'child-epoch',
            'events': [
              for (final event in events)
                if ((event['seq'] as int) > (params['last_sequence'] as int))
                  event,
            ],
            'latest_seq': events.fold<int>(
              0,
              (latest, event) =>
                  (event['seq'] as int) > latest ? event['seq'] as int : latest,
            ),
            'truncated': false,
            'snapshot_required': false,
          };
        }
        switch (method) {
          case 'subagent.list':
            listCalls += 1;
            return {
              'subagents':
                  rows ??
                  [
                    if (!emptyList)
                      {
                        'subagent_id': 'child-1',
                        'goal': 'Inspect the release',
                        'status': 'running',
                        'model': 'test-model',
                        'last_tool': 'read_file',
                        'accepting_steer': true,
                        'started_at': startedAt,
                        'tool_count': 3,
                      },
                  ],
              'delegations': const [],
            };
          case 'subagent.steer':
            if (failSteer) throw StateError('Steering transport failed');
            if (steerGate case final gate?) await gate.future;
            return {
              'status': acceptSteer ? 'queued' : 'rejected',
              'subagent_id': 'child-1',
            };
          case 'subagent.interrupt':
            if (failInterrupt) throw StateError('Interrupt transport failed');
            return {'found': findInterrupt, 'subagent_id': 'child-1'};
          default:
            return base.call(method, params);
        }
      },
    );
  }
}

class _TracePicker extends FilePickerPlatform {
  final files = <(String, Uint8List)>[];
  final pending = Completer<Uri?>();
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    files.add((fileName, bytes));
    return pending.future;
  }
}

void main() {
  const review = bool.fromEnvironment('CAPTURE_SUBAGENT_FIXES');
  const frame = ValueKey('subagent-fixes-render');
  setUpAll(() async {
    if (!review) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'monospace': 'build/studio-mono.ttf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!review) return;
    await tester.settleMarkdown();
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(frame))
          .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('build/design-previews/subagent-fixes/site')
        ..createSync(recursive: true);
      await File(
        '${folder.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() ready,
    String outcome,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    do {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: outcome);
      if (ready()) return;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    } while (DateTime.now().isBefore(deadline));
    fail('Timed out waiting for $outcome');
  }

  late _SubagentFixture fixture;
  late ProfileWorkspaceController controller;
  late AppPreferences appPreferences;
  late ProfileChat chat;
  late ProfileSupervisionSession supervision;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = _SubagentFixture();
    final preferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(preferences);
    controller = ProfileWorkspaceController(
      access: ConnectionAccess(
        connection: identityTestConnection(),
        dashboardOAuth: null,
      ),
      connectionIdentity: 'subagent-panel',
      preferences: preferences,
      appPreferences: appPreferences,
      gatewayFactory: fixture.gateway,
    );
    await controller.initialize();
    chat = await controller.createChat(canDispatch: () => true);
    emitChatEvent(controller, chat, 'message.start', {});
    supervision = ProfileSupervisionSession(controller: controller, chat: chat);
  });

  tearDown(() {
    supervision.dispose();
    controller.dispose();
    appPreferences.dispose();
  });

  Future<void> showPanel(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1.8,
    bool motion = false,
    Size size = const Size(320, 640),
    TranscriptResourceSession Function(ProfileSessionKey)? resources,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wingTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: !motion,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                ProfileSubagentPanel(
                  session: supervision,
                  createResources: resources ?? controller.traceResources,
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    if (!motion) await tester.pumpAndSettle();
  }

  Future<void> openDetails(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1.8,
    Size size = const Size(320, 640),
  }) async {
    await showPanel(tester, brightness: brightness, scale: scale, size: size);
    await tester.ensureVisible(find.text('Inspect the release'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inspect the release'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Task').first);
    await tester.pumpAndSettle();
  }

  TranscriptResourceSession resourcesFor(
    ProfileSessionKey key,
    Future<http.Response> Function(http.Request) respond,
  ) {
    final client = RemoteFilesClient(
      dashboard: DashboardClient(
        host: 'trace.test',
        port: 9119,
        proxied: true,
        httpClient: MockClient(respond),
      ),
    );
    final gateway = fixture.gateway(key.workspace);
    return TranscriptResourceSession(
      files: OwnedRemoteFiles(
        source: client,
        profileName: key.workspace.profileName,
        storedSessionId: key.sessionId,
        release: client.close,
      ),
      loadHistory: (offset) => gateway.history(key.sessionId, offset: offset),
      createSkillReader: gateway.skillReader,
    );
  }

  Future<void> openChild(WidgetTester tester) async {
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'child-1',
      'child_session_id': 'child-session',
      'goal': 'Inspect the release',
    });
    await tester.pump();
    await tester.tap(find.text('Inspect the release'));
    await until(
      tester,
      () => find.byType(SubagentTimeline).evaluate().isNotEmpty,
      'child timeline',
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  List<Map<String, dynamic>> resourceRows(String name, String arguments) => [
    {'id': 1, 'role': 'user', 'content': 'Inspect source evidence'},
    {
      'id': 2,
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': 'source-1',
          'function': {'name': name, 'arguments': arguments},
        },
      ],
    },
    {
      'id': 3,
      'role': 'tool',
      'tool_call_id': 'source-1',
      'content': name == 'read_file'
          ? 'A short file excerpt'
          : 'Day details are readable.',
    },
  ];

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'child trace source image loads retries and opens ${brightness.name} $scale',
        (tester) async {
          const path =
              '/home/tarkil/.hermes/cache/scratch/rwc-ux/390-day29.png';
          fixture.childMessages = resourceRows(
            'vision_analyze',
            jsonEncode({
              'image_url': path,
              'question': 'Inspect mobile day details and controls',
            }),
          );
          final requests = <http.Request>[];
          var response = Completer<http.Response>();
          await showPanel(
            tester,
            brightness: brightness,
            scale: scale,
            size: scale == 1 ? const Size(390, 844) : const Size(320, 640),
            resources: (key) => resourcesFor(key, (request) {
              requests.add(request);
              return response.future;
            }),
          );
          await openChild(tester);
          await tester.openLiveActivity();
          await Scrollable.ensureVisible(
            tester.element(find.text('Analyzed image')),
            alignment: 0.5,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('Analyzed image'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.bySemanticsLabel('Loading image'), findsWidgets);
          await capture(
            tester,
            'resource-image-pending-${brightness.name}-$scale',
          );
          expect(requests.single.url.path, '/api/fs/download');
          expect(requests.single.url.queryParameters, {
            'path': path,
            'profile': chat.key.workspace.profileName,
            'session_id': 'child-session',
          });
          response.complete(http.Response('{"detail":"File not found"}', 404));
          await until(
            tester,
            () => find
                .text('This image could not be previewed.')
                .evaluate()
                .isNotEmpty,
            'recoverable image failure',
          );
          response = Completer<http.Response>();
          await Scrollable.ensureVisible(
            tester.element(find.byTooltip('Retry image')),
            alignment: 0.5,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byTooltip('Retry image'));
          await tester.pump();
          expect(find.bySemanticsLabel('Loading image'), findsWidgets);
          response.complete(
            http.Response.bytes(
              img.encodePng(
                img.fill(
                  img.Image(width: 180, height: 100),
                  color: img.ColorRgb8(37, 103, 120),
                ),
              ),
              200,
            ),
          );
          await until(
            tester,
            () => find.byType(Image).evaluate().isNotEmpty,
            'image provider',
          );
          for (final element in find.byType(Image).evaluate()) {
            final image = element.widget as Image;
            await tester.runAsync(() => precacheImage(image.image, element));
          }
          await tester.pump();
          expect(find.text('This image could not be previewed.'), findsNothing);
          expect(
            tester.widget<RawImage>(find.byType(RawImage)).image,
            isNotNull,
          );
          expect(requests, hasLength(2));
          expect(requests.last.url, requests.first.url);
          await Scrollable.ensureVisible(
            tester.element(find.byType(RawImage)),
            alignment: 0.5,
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(RawImage).hitTestable(), findsOneWidget);
          await capture(
            tester,
            'resource-image-ready-${brightness.name}-$scale',
          );
          await Scrollable.ensureVisible(
            tester.element(find.byTooltip('Preview image')),
            alignment: 0.5,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byTooltip('Preview image'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(ChatImagePreview), findsOneWidget);
          expect(
            tester
                .widget<ChatImagePreview>(find.byType(ChatImagePreview))
                .bytes,
            isNotEmpty,
          );
          Navigator.of(tester.element(find.byType(ChatImagePreview))).pop();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Close subagent activity'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'attachment gallery clears old previews during same-path owner rotation',
    (tester) async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final successor = Completer<Uint8List>();
      var calls = 0;
      Future<Uint8List> Function(String) loader = (_) async => bytes;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                change = update;
                return UserMessageAttachments(
                  width: 300,
                  attachments: [
                    for (var i = 0; i < 6; i++)
                      UserMessageAttachment(
                        name: '$i.png',
                        target: '$i.png',
                        isImage: true,
                      ),
                  ],
                  loadImage: loader,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      for (final element in find.byType(Image).evaluate()) {
        await tester.runAsync(
          () => precacheImage((element.widget as Image).image, element),
        );
      }
      await tester.pump();
      expect(find.byType(Image), findsWidgets);
      change(
        () => loader = (_) {
          calls++;
          return successor.future;
        },
      );
      await tester.pump();
      expect(calls, 5);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('+1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Image), findsNothing);
      successor.complete(bytes);
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rotated image header cannot open previously decoded owner bytes',
    (tester) async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final successor = Completer<Uint8List>();
      Future<Uint8List> Function(String) loader = (_) async => bytes;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                change = update;
                return ChatInlineImage(
                  target: 'same.png',
                  title: 'Evidence',
                  loadImage: loader,
                  headerBuilder: (context, open) => IconButton(
                    tooltip: 'Open captured image',
                    onPressed: open,
                    icon: const Icon(Icons.open_in_full),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Open captured image',
              ),
            )
            .onPressed,
        isNotNull,
      );
      change(() => loader = (_) => successor.future);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Open captured image',
              ),
            )
            .onPressed,
        isNull,
      );
      successor.complete(bytes);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Open captured image',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'explicit child replacement reaches Latest while live replay remains held',
    (tester) async {
      fixture.childMessages = [
        for (var i = 1; i <= 30; i++)
          {'id': i, 'role': 'assistant', 'content': 'Saved evidence $i. ' * 8},
      ];
      await showPanel(tester, scale: 1, size: const Size(390, 844));
      await openChild(tester);
      final reader = tester
          .widget<SubagentTimeline>(find.byType(SubagentTimeline))
          .session;
      reader.setActive(false);
      final scrollable = find
          .descendant(
            of: find.byType(ProfileTranscript),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, 700));
      await tester.pumpAndSettle();
      await until(
        tester,
        () => reader.readingPosition.resume != null,
        'older reading bookmark',
      );
      final bookmark = reader.readingPosition.resume!;
      fixture.childMessages = [
        for (var i = 100; i < 130; i++)
          {'id': i, 'role': 'assistant', 'content': 'Replacement evidence $i.'},
      ];
      reader.setActive(true);
      await until(
        tester,
        () =>
            reader.qualification?.contains('Newer activity is available') ==
            true,
        'deferred automatic replacement',
      );
      reader.setActive(false);
      expect(reader.readingPosition.resume!.messageId, bookmark.messageId);
      expect(reader.messages.first['id'], 1);
      fixture.replayGate = Completer<void>();
      await tester.tap(find.byTooltip('Refresh subagent activity'));
      await until(
        tester,
        () => reader.messages.first['id'] == 100,
        'committed replacement while replay held',
      );
      expect(reader.historyLoading, isTrue);
      await tester.pumpAndSettle();
      await tester.settleMarkdown();
      await capture(tester, 'canonical-replacement-before-assert');
      expect(
        find
            .textContaining('Replacement evidence 129.', findRichText: true)
            .hitTestable(),
        findsOneWidget,
      );
      expect(reader.readingPosition.resume, isNull);
      await capture(tester, 'canonical-replaced-latest-live-held');
      fixture.replayGate!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close subagent activity'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final attachment in [false, true]) {
    testWidgets(
      'same child image path reloads only when its committed owner changes ${attachment ? 'attachment' : 'markdown'}',
      (tester) async {
        fixture.childMessages = [
          {
            'id': 1,
            'role': attachment ? 'user' : 'assistant',
            'content': attachment
                ? '@image:evidence.png'
                : '![Evidence](evidence.png)',
          },
        ];
        final requests = <http.Request>[];
        final oldResponse = Completer<http.Response>();
        await showPanel(
          tester,
          scale: 1,
          resources: (key) => resourcesFor(key, (request) {
            requests.add(request);
            return key.sessionId == 'child-session'
                ? oldResponse.future
                : Future.value(
                    http.Response.bytes(
                      img.encodePng(
                        img.fill(
                          img.Image(width: 16, height: 16),
                          color: img.ColorRgb8(37, 103, 120),
                        ),
                      ),
                      200,
                    ),
                  );
          }),
        );
        await openChild(tester);
        await until(tester, () => requests.length == 1, 'initial child image');
        await tester.tap(find.byTooltip('Refresh subagent activity'));
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        fixture.childResourceId = 'child-successor';
        await tester.tap(find.byTooltip('Refresh subagent activity'));
        await until(
          tester,
          () => requests.length == 2,
          'same-path successor image',
        );
        expect(
          requests.map((request) => request.url.queryParameters['session_id']),
          ['child-session', 'child-successor'],
        );
        await until(
          tester,
          () => find.byType(Image).evaluate().isNotEmpty,
          'successor image provider',
        );
        for (final element in find.byType(Image).evaluate()) {
          await tester.runAsync(
            () => precacheImage((element.widget as Image).image, element),
          );
        }
        await tester.pump();
        expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
        oldResponse.complete(http.Response.bytes([1, 2, 3], 200));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        expect(find.text('This image could not be previewed.'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close subagent activity'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('committed child resource rotation fences all old consumers', (
    tester,
  ) async {
    fixture.childMessages = [
      {'id': 1, 'role': 'assistant', 'content': '[Report](report.md)'},
    ];
    final bindings = <ProfileSessionKey>[];
    final requests = <http.Request>[];
    final pending = Completer<http.Response>();
    await showPanel(
      tester,
      scale: 1,
      resources: (key) {
        bindings.add(key);
        return resourcesFor(key, (request) {
          requests.add(request);
          return key.sessionId == 'child-session'
              ? pending.future
              : Future.value(http.Response.bytes([4, 5, 6], 200));
        });
      },
    );
    await openChild(tester);
    final old = tester.widget<ProfileTranscript>(
      find.byType(ProfileTranscript),
    );
    final oldMessage = tester.widget<ProfileMessage>(
      find.byType(ProfileMessage),
    );
    final oldSkills = tester.widget<SkillReaderScope>(
      find.byType(SkillReaderScope),
    );
    final document = SkillDocument.fromReceived(
      name: 'review',
      content: '# Review',
    );
    fixture.skillGate = Completer<void>();
    final oldSkill = oldSkills.createReader(document);
    final skillLoad = oldSkill.load();
    const output = ChatOutput(
      kind: ChatOutputKind.file,
      path: 'report.md',
      url: null,
      label: 'report.md',
    );
    final image = expectLater(old.loadImage!('image.png'), throwsA(anything));
    final share = expectLater(old.onShareResource!(output), throwsA(anything));
    final save = expectLater(
      oldMessage.onDownloadRemoteFile!(output),
      throwsA(anything),
    );

    // An unchanged owner preserves the exact callback objects across reads.
    await tester.tap(find.byTooltip('Refresh subagent activity'));
    await tester.pumpAndSettle();
    final unchanged = tester.widget<ProfileTranscript>(
      find.byType(ProfileTranscript),
    );
    expect(identical(old.loadImage, unchanged.loadImage), isTrue);
    expect(identical(old.onShareResource, unchanged.onShareResource), isTrue);
    expect(bindings.map((key) => key.sessionId), ['child-session']);

    fixture.childResourceId = 'child-successor';
    await tester.tap(find.byTooltip('Refresh subagent activity'));
    await tester.pumpAndSettle();
    final current = tester.widget<ProfileTranscript>(
      find.byType(ProfileTranscript),
    );
    expect(identical(old.loadImage, current.loadImage), isFalse);
    expect(bindings.map((key) => key.sessionId), [
      'child-session',
      'child-successor',
    ]);
    pending.complete(http.Response.bytes([1, 2, 3], 200));
    fixture.skillGate!.complete();
    var oldSettled = false;
    unawaited(
      Future.wait([
        image,
        share,
        save,
        skillLoad,
      ]).then((_) => oldSettled = true),
    );
    await until(tester, () => oldSettled, 'retired resource completions');
    expect(oldSkill.observation, isNull);
    expect(() => oldSkills.createReader(document), throwsStateError);
    Uint8List? currentImage;
    unawaited(
      current.loadImage!('image.png').then((bytes) => currentImage = bytes),
    );
    await until(
      tester,
      () => currentImage != null,
      'successor resource completion',
    );
    expect(currentImage, [4, 5, 6]);
    expect(requests.last.url.queryParameters['session_id'], 'child-successor');
    expect(requests.last.url.queryParameters['path'], 'image.png');

    fixture.transcriptAvailable = false;
    await tester.tap(find.byTooltip('Refresh subagent activity'));
    await tester.pumpAndSettle();
    final unavailable = tester.widget<ProfileTranscript>(
      find.byType(ProfileTranscript),
    );
    expect(unavailable.loadImage, isNull);
    expect(unavailable.onOpenResource, isNull);
    expect(unavailable.onShareResource, isNull);
    expect(find.byType(SkillReaderScope), findsNothing);
    await expectLater(current.loadImage!('image.png'), throwsA(anything));
    expect(bindings, hasLength(2));
    await tester.tap(find.byTooltip('Close subagent activity'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'canonical child held read retry and departure ${brightness.name} $scale',
        (tester) async {
          fixture.transcriptGate = Completer<void>();
          final bindings = <ProfileSessionKey>[];
          await showPanel(
            tester,
            brightness: brightness,
            scale: scale,
            size: scale == 1 ? const Size(390, 844) : const Size(320, 640),
            resources: (key) {
              bindings.add(key);
              return resourcesFor(
                key,
                (_) async => http.Response.bytes([], 200),
              );
            },
          );
          await openChild(tester);
          expect(find.byType(SubagentTimeline), findsOneWidget);
          expect(
            find.bySemanticsLabel('Loading subagent activity'),
            findsWidgets,
          );
          expect(bindings, isEmpty);
          await until(
            tester,
            () =>
                ModalRoute.of(
                  tester.element(find.byType(SubagentTimeline)),
                )?.animation?.status ==
                AnimationStatus.completed,
            'fully presented child sheet while canonical read remains held',
          );
          await tester.pump();
          expect(fixture.transcriptGate!.isCompleted, isFalse);
          expect(find.text('Subagent activity').hitTestable(), findsOneWidget);
          expect(
            find.byTooltip('Close subagent activity').hitTestable(),
            findsOneWidget,
          );
          final loading = find.byWidgetPredicate(
            (widget) =>
                widget is StudioLoading &&
                widget.label == 'Loading subagent activity',
          );
          expect(loading, findsOneWidget);
          final paint = find.descendant(
            of: loading,
            matching: find.byType(CustomPaint),
          );
          expect(paint, findsOneWidget);
          final bounds = tester.getRect(paint);
          final viewport =
              Offset.zero &
              (tester.view.physicalSize / tester.view.devicePixelRatio);
          expect(bounds.isEmpty, isFalse);
          expect(viewport.intersect(bounds), bounds);

          await capture(
            tester,
            'canonical-initial-held-${brightness.name}-$scale',
          );
          fixture.transcriptGate!.complete();
          await tester.pumpAndSettle();
          expect(bindings, hasLength(1));
          fixture.transcriptGate = Completer<void>();
          fixture.transcriptFails = true;
          await tester.tap(find.byTooltip('Refresh subagent activity'));
          await tester.pump();
          await tester.pump();
          expect(
            find.bySemanticsLabel('Loading subagent activity'),
            findsWidgets,
          );
          await capture(
            tester,
            'canonical-refresh-held-${brightness.name}-$scale',
          );
          fixture.transcriptGate!.complete();
          await tester.pumpAndSettle();
          expect(find.byType(StudioError), findsWidgets);
          await tester.ensureVisible(find.byType(StudioError).first);
          await tester.pumpAndSettle();
          await capture(
            tester,
            'canonical-refresh-failed-${brightness.name}-$scale',
          );
          fixture.transcriptFails = false;
          fixture.transcriptGate = Completer<void>();
          final retry = find.byTooltip('Refresh history');
          await Scrollable.ensureVisible(
            tester.element(retry),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          expect(retry.hitTestable(), findsOneWidget);
          await tester.tap(retry);
          await tester.pump();
          await tester.pump();
          expect(
            find.bySemanticsLabel('Loading subagent activity'),
            findsWidgets,
          );
          await capture(
            tester,
            'canonical-retry-held-${brightness.name}-$scale',
          );
          await tester.tap(find.byTooltip('Close subagent activity'));
          await tester.pumpAndSettle();
          fixture.transcriptGate!.complete();
          await tester.pumpAndSettle();
          expect(find.byType(SubagentTimeline), findsNothing);
          expect(bindings, hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'child trace file preview binds full content and pending share to the child',
    (tester) async {
      fixture.childMessages = resourceRows('read_file', '{"path":"report.md"}');
      final requests = <http.Request>[];
      var response = Completer<http.Response>();
      await showPanel(
        tester,
        scale: 1,
        size: const Size(390, 844),
        resources: (key) => resourcesFor(key, (request) {
          requests.add(request);
          return response.future;
        }),
      );
      await openChild(tester);
      await tester.openLiveActivity();
      await Scrollable.ensureVisible(
        tester.element(find.text('Read file')),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Read file'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Preview file'), findsOneWidget);
      expect(find.byTooltip('Share file'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Preview file')),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Preview file'));
      await tester.pump();
      expect(find.byType(ChatOutputsScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('Loading outputs'), findsWidgets);
      await tester.pumpAndSettle();
      await capture(tester, 'resource-file-pending');
      expect(requests.single.url.path, '/api/fs/read-text');
      expect(requests.single.url.queryParameters, {
        'path': 'report.md',
        'profile': chat.key.workspace.profileName,
        'session_id': 'child-session',
      });
      response.complete(
        http.Response(
          jsonEncode({
            'path': '/child/work/report.md',
            'text': '# Full child report\n\nDetails beyond the excerpt.',
            'language': 'markdown',
            'mimeType': 'text/markdown',
            'binary': false,
            'truncated': false,
          }),
          200,
        ),
      );
      await until(
        tester,
        () => find
            .byWidgetPredicate(
              (w) =>
                  w is MarkdownMessageContent &&
                  w.data.contains('Details beyond the excerpt.'),
            )
            .evaluate()
            .isNotEmpty,
        'full child file viewer',
      );
      await tester.settleMarkdown();
      await tester.pumpAndSettle();
      await capture(tester, 'resource-file-ready');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await until(
        tester,
        () => find.byTooltip('Share file').evaluate().isNotEmpty,
        'returned child file action',
      );
      response = Completer<http.Response>();
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Share file')),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Share file'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byTooltip('Share file'),
          matching: find.byIcon(Icons.hourglass_top),
        ),
        findsOneWidget,
      );
      expect(requests.last.url.path, '/api/fs/download');
      expect(requests.last.url.queryParameters['session_id'], 'child-session');
      await tester.tap(find.byTooltip('Close subagent activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      response.complete(http.Response.bytes([1, 2, 3], 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(SubagentTimeline), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('nested child message resources save under their own session', (
    tester,
  ) async {
    fixture.childEvents.add({
      'session_id': 'child-session',
      'seq': 1,
      'type': 'subagent.start',
      'payload': {
        'subagent_id': 'nested-agent',
        'child_session_id': 'nested-session',
        'goal': 'Inspect nested evidence',
      },
    });
    fixture.nestedMessages = [
      {'id': 1, 'role': 'assistant', 'content': '[Nested report](report.md)'},
    ];
    final originalPicker = FilePickerPlatform.instance;
    final picker = _TracePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = originalPicker);
    final keys = <ProfileSessionKey>[];
    final requests = <http.Request>[];
    final response = Completer<http.Response>();
    await showPanel(
      tester,
      scale: 1,
      size: const Size(390, 844),
      resources: (key) {
        keys.add(key);
        return resourcesFor(key, (request) {
          requests.add(request);
          return response.future;
        });
      },
    );
    await openChild(tester);
    await tester.tap(find.byKey(const ValueKey(('live-work-tab', 0, false))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await Scrollable.ensureVisible(
      tester.element(find.text('Inspect nested evidence')),
      alignment: .5,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Inspect nested evidence'));
    await until(tester, () => keys.length == 2, 'nested resources');
    await tester.settleMarkdown();
    await until(
      tester,
      () => find.byTooltip('Download').evaluate().isNotEmpty,
      'nested deliverable',
    );
    expect(keys.map((key) => key.sessionId), [
      'child-session',
      'nested-session',
    ]);
    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Download')),
      alignment: .5,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Download'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byTooltip('Download'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(requests.single.url.queryParameters, {
      'path': 'report.md',
      'profile': chat.key.workspace.profileName,
      'session_id': 'nested-session',
    });
    response.complete(
      http.Response.bytes(
        utf8.encode('Nested original content'),
        200,
        headers: {'content-disposition': 'attachment; filename=report.md'},
      ),
    );
    await until(tester, () => picker.files.isNotEmpty, 'save picker');
    expect(picker.files.single.$1, 'report.md');
    expect(utf8.decode(picker.files.single.$2), 'Nested original content');
    expect(
      find.descendant(
        of: find.byTooltip('Download'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    picker.pending.complete(Uri.parse('content://documents/nested-report'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Close subagent activity').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('live-work-tab', 0, true))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close subagent activity').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'normal chat opens child timeline without selecting or controlling it',
    (tester) async {
      await showPanel(tester, scale: 1);
      final selected = controller.current!.chat;
      emitChatEvent(controller, chat, 'subagent.start', {
        'subagent_id': 'child-1',
        'child_session_id': 'child-session',
        'goal': 'Inspect the release',
      });
      await tester.pump();
      await tester.tap(find.text('Inspect the release'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(find.byType(SubagentTimeline), findsOneWidget);
      final child = tester
          .widget<SubagentTimeline>(find.byType(SubagentTimeline))
          .session;
      expect(child.messages.single['content'], 'Child saved evidence');
      expect(child.historyError, isNull);
      expect(child.liveError, isNull);
      expect(controller.current!.chat, same(selected));
      await tester.tap(find.text('Task').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final steerField = find.byType(TextField);
      await tester.ensureVisible(steerField);
      await tester.showKeyboard(steerField);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(steerField);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Steer'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding();
      tester.testTextInput.hide();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        fixture.requests.where((request) => request.$1 == 'subagent.tail'),
        isEmpty,
      );
      expect(
        fixture.requests.where(
          (call) => call.$1 == 'prompt.submit' || call.$1 == 'session.close',
        ),
        isEmpty,
      );
      await tester.tap(find.byTooltip('Close subagent activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SubagentTimeline), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('child completion retains one Activity for saved and live tools', (
    tester,
  ) async {
    fixture.childMessages = [
      {'id': 1, 'role': 'user', 'content': 'Inspect the release'},
      {
        'id': 2,
        'role': 'assistant',
        'content': '',
        'reasoning': '**Check saved evidence**',
        'tool_calls': [
          for (var i = 0; i < 11; i++)
            {
              'id': 'call-$i',
              'function': {'name': 'read_file', 'arguments': '{}'},
            },
        ],
      },
      for (var i = 0; i < 11; i++)
        {
          'id': i + 3,
          'role': 'tool',
          'tool_call_id': 'call-$i',
          'content': 'Evidence $i',
        },
    ];
    fixture.childEvents.addAll([
      {'session_id': 'child-session', 'seq': 1, 'type': 'message.start'},
      {
        'session_id': 'child-session',
        'seq': 2,
        'type': 'tool.start',
        'payload': {
          'tool_id': 'submirror:child-session:1',
          'name': 'read_file',
          'preview': 'current.txt',
        },
      },
    ]);
    await showPanel(tester, scale: 1);
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'child-1',
      'child_session_id': 'child-session',
      'goal': 'Inspect the release',
    });
    await tester.pump();
    await tester.tap(find.text('Inspect the release'));
    await until(
      tester,
      () => find.text('12 tools').evaluate().isNotEmpty,
      'the child timeline with saved and live tools',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live-activity-toggle')),
        matching: find.text('12 tools'),
      ),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.byType(ProfileLiveExecution), findsOneWidget);
    await tester.openLiveActivity();
    expect(find.byType(ProfileActivitySection), findsOneWidget);
    fixture.childEvents.add({
      'session_id': 'child-session',
      'seq': 3,
      'type': 'message.complete',
      'payload': {'text': 'Final reply awaiting persistence'},
    });
    await tester.tap(find.byTooltip('Refresh subagent activity'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live-activity-toggle')),
        matching: find.text('12 tools'),
      ),
      findsOneWidget,
      reason:
          'Saved work and the retained final replay must stay in one reply Activity',
    );
    expect(find.byType(ProfileLiveExecution), findsOneWidget);
    await tester.openLiveActivity();
    expect(find.byType(ProfileActivitySection), findsOneWidget);
    await tester.tap(find.byTooltip('Close subagent activity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('child timeline keeps its visible Running pulse', (tester) async {
    await showPanel(tester, scale: 1, motion: true);
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'child-1',
      'child_session_id': 'child-session',
      'goal': 'Inspect the release',
    });
    await tester.pump();
    await tester.tap(find.text('Inspect the release'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(SubagentTimeline), findsOneWidget);
    final sheet = find.ancestor(
      of: find.byType(SubagentTimeline),
      matching: find.byType(StudioLoadingFrame),
    );
    expect(sheet, findsOneWidget);
    final pulse = find.descendant(
      of: sheet,
      matching: find.byWidgetPredicate(
        (widget) => widget is StudioLoading && widget.label == 'Running',
      ),
    );
    void expectVisibleWork() {
      expect(pulse, findsOneWidget);
      final bounds = tester.getRect(pulse);
      final viewport =
          Offset.zero &
          (tester.view.physicalSize / tester.view.devicePixelRatio);
      expect(bounds.isEmpty, isFalse);
      expect(viewport.intersect(bounds), bounds);
      final paint = find.descendant(
        of: pulse,
        matching: find.byType(CustomPaint),
      );
      expect(paint, findsOneWidget);
      expect(tester.getSize(paint).isEmpty, isFalse);
    }

    final taskHeader = find.descendant(
      of: sheet,
      matching: find.ancestor(
        of: find.text('Task'),
        matching: find.byType(ListTile),
      ),
    );
    expect(taskHeader, findsOneWidget);
    expectVisibleWork();
    await tester.tap(taskHeader);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expectVisibleWork();
    await tester.tap(taskHeader);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expectVisibleWork();
    await tester.tap(find.byTooltip('Close subagent activity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'timeline steering stays visible and reports pending/rejection ${brightness.name} $scale',
        (tester) async {
          fixture.childMessages = [
            {'id': 1, 'role': 'user', 'content': 'Check source evidence'},
            {
              'id': 2,
              'role': 'assistant',
              'content': '',
              'reasoning':
                  '**Fixing database issues**\n\nCheck the retained parent and child rows before changing the query.',
              'tool_calls': [
                {
                  'id': 'saved',
                  'function': {
                    'name': 'read_file',
                    'arguments': '{"path":"evidence.py"}',
                  },
                },
              ],
            },
            {
              'id': 3,
              'role': 'tool',
              'tool_call_id': 'saved',
              'content': 'Saved source evidence',
            },
          ];
          await showPanel(
            tester,
            brightness: brightness,
            scale: scale,
            size: scale == 1 ? const Size(390, 844) : const Size(320, 640),
          );
          emitChatEvent(controller, chat, 'subagent.start', {
            'subagent_id': 'child-1',
            'child_session_id': 'child-session',
            'goal': 'Inspect the release',
          });
          await tester.pump();
          await tester.tap(find.text('Inspect the release'));
          final field = find.byType(TextField);
          final steer = find.byTooltip('Steer');
          await until(
            tester,
            () =>
                field.hitTestable().evaluate().isNotEmpty &&
                steer.hitTestable().evaluate().isNotEmpty,
            'the child steering editor and action',
          );
          expect(field.hitTestable(), findsOneWidget);
          expect(steer.hitTestable(), findsOneWidget);
          expect(find.byTooltip('Interrupt'), findsOneWidget);
          await tester.openLiveActivity(tools: false);
          final reasoning = find.text('Fixing database issues');
          await tester.ensureVisible(reasoning);
          await tester.pump(const Duration(milliseconds: 300));
          expect(reasoning, findsOneWidget);
          expect(
            find.ancestor(of: reasoning, matching: find.byType(ExpansionTile)),
            findsNothing,
          );
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is MarkdownMessageContent &&
                  w.data.startsWith('**Fixing database issues**'),
            ),
            findsNothing,
          );
          expect(
            tester
                .getRect(reasoning)
                .overlaps(tester.getRect(find.byType(SubagentTimeline))),
            isTrue,
            reason:
                'Reasoning ${tester.getRect(reasoning)}; viewport ${tester.getRect(find.byType(SubagentTimeline))}',
          );
          await capture(tester, 'reasoning-${brightness.name}-$scale');
          await tester.enterText(field, 'Check the retained child rows');
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(steer.hitTestable(), findsOneWidget);
          final gate = Completer<void>();
          fixture.steerGate = gate;
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          await tester.tap(steer);
          await tester.pump();
          expect(
            find.descendant(
              of: steer,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          expect(tester.widget<TextField>(field).enabled, isFalse);
          final dispatches = fixture.requests
              .where((c) => c.$1 == 'subagent.steer')
              .length;
          await tester.tap(steer);
          await tester.pump();
          expect(
            fixture.requests.where((c) => c.$1 == 'subagent.steer'),
            hasLength(dispatches),
          );
          final request = fixture.requests.lastWhere(
            (c) => c.$1 == 'subagent.steer',
          );
          expect(request.$2['session_id'], chat.runtime.runtimeId);
          expect(request.$2['subagent_id'], 'child-1');
          expect(request.$2['text'], 'Check the retained child rows');
          await capture(tester, 'steering-pending-${brightness.name}-$scale');
          gate.complete();
          await until(
            tester,
            () => find.text('Steer rejected').evaluate().isNotEmpty,
            'the rejected steering result',
          );
          expect(
            find.descendant(
              of: find.byType(StudioError),
              matching: find.text('Steer rejected'),
            ),
            findsOneWidget,
          );
          expect(
            tester.widget<TextField>(field).controller!.text,
            'Check the retained child rows',
          );
          expect(steer.hitTestable(), findsOneWidget);
          final rejected = find.text('Steer rejected');
          final feedbackViewport = find
              .ancestor(
                of: rejected,
                matching: find.byType(SingleChildScrollView),
              )
              .last;
          final viewportRect = tester.getRect(feedbackViewport);
          final messageRect = tester.getRect(rejected);
          if (messageRect.bottom > viewportRect.bottom) {
            // Larger fallback glyphs may wrap beyond the bounded viewport.
            await tester.drag(feedbackViewport, const Offset(0, -120));
            await tester.pumpAndSettle();
            expect(
              tester.getRect(rejected).bottom,
              lessThanOrEqualTo(viewportRect.bottom),
            );
          } else {
            expect(viewportRect.intersect(messageRect), messageRect);
          }
          await capture(tester, 'steering-rejected-${brightness.name}-$scale');
          fixture.steerGate = null;
          fixture.failSteer = true;
          await tester.tap(steer);
          await until(
            tester,
            () => find.text('Steering failed').evaluate().isNotEmpty,
            'the failed steering result',
          );
          expect(find.text('Steering failed'), findsOneWidget);
          expect(
            tester.widget<TextField>(field).controller!.text,
            'Check the retained child rows',
          );
          fixture.failSteer = false;
          fixture.acceptSteer = true;
          await tester.tap(steer);
          await until(
            tester,
            () =>
                find.text('Steering queued.').evaluate().isNotEmpty &&
                tester.widget<TextField>(field).controller!.text.isEmpty,
            'accepted steering to clear the submitted draft',
          );
          expect(tester.widget<TextField>(field).controller!.text, isEmpty);
          expect(find.text('Steering queued.'), findsOneWidget);
          await capture(tester, 'steering-queued-${brightness.name}-$scale');
          // A newer draft must survive acceptance of the captured submission.
          await tester.enterText(field, 'Original guidance');
          final acceptedGate = Completer<void>();
          fixture.steerGate = acceptedGate;
          addTearDown(() {
            if (!acceptedGate.isCompleted) acceptedGate.complete();
          });
          await tester.tap(steer);
          await tester.pump();
          tester.widget<TextField>(field).controller!.text = 'Newer guidance';
          acceptedGate.complete();
          await until(
            tester,
            () => tester.widget<TextField>(field).enabled != false,
            'the held steering submission to finish',
          );
          expect(
            tester.widget<TextField>(field).controller!.text,
            'Newer guidance',
          );

          tester.view.viewInsets = const FakeViewPadding();
          tester.testTextInput.hide();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          fixture.failInterrupt = true;
          await tester.tap(find.byTooltip('Interrupt'));
          final interruptError = find.descendant(
            of: find.byType(StudioError),
            matching: find.text('Interrupt failed'),
          );
          await until(
            tester,
            () => interruptError.evaluate().isNotEmpty,
            'the failed interrupt result',
          );
          expect(find.byTooltip('Interrupt').hitTestable(), findsOneWidget);
          await capture(tester, 'interrupt-error-${brightness.name}-$scale');
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Close subagent activity'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'agent timing is backend-derived and stops on completion or uncertainty',
    (tester) async {
      fixture.startedAt = DateTime.now().millisecondsSinceEpoch / 1000 - 40;
      await showPanel(tester);
      expect(find.text('Reading file'), findsOneWidget);
      expect(find.text('test-model · 3 tool calls'), findsOneWidget);
      var time = tester.widget<ActivityTime>(find.byType(ActivityTime));
      expect(time.backendStartedAt, fixture.startedAt);
      emitChatEvent(controller, chat, 'subagent.complete', {
        'subagent_id': 'child-1',
        'status': 'completed',
        'summary': 'Inspection finished',
        'duration_seconds': 42.5,
      });
      await tester.pump();
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Inspection finished'), findsOneWidget);
      time = tester.widget<ActivityTime>(find.byType(ActivityTime));
      expect(time.backendStartedAt, isNull);
      expect(time.durationSeconds, 42.5);
      expect(find.text('43 s'), findsOneWidget);
      emitChatEvent(controller, chat, 'subagent.start', {
        'subagent_id': 'uncertain',
        'goal': 'Check another source',
        'started_at': fixture.startedAt,
      });
      fixture.emptyList = true;
      await supervision.refreshSubagents();
      await tester.pump();
      expect(find.text('Last seen running'), findsOneWidget);
      expect(
        tester
            .widgetList<ActivityTime>(find.byType(ActivityTime))
            .every((w) => w.backendStartedAt == null),
        isTrue,
      );
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'agent states and metadata remain readable ${brightness.name} $scale',
        (tester) async {
          const longGoal =
              'Inspect the release candidate and verify the Android transport settings. Keep every original instruction in the task body.';
          const heading =
              'Inspect the release candidate and verify the Android transport settings';
          fixture.rows = [
            {
              'subagent_id': 'child-1',
              'goal': longGoal,
              'status': 'running',
              'last_tool': 'read_file',
              'model': 'test-model',
              'accepting_steer': true,
            },
            {
              'subagent_id': 'queued',
              'goal': 'Compare suppliers',
              'status': 'queued',
              'started_at': 1000,
            },
          ];
          for (final status in ['completed', 'failed', 'interrupted']) {
            emitChatEvent(controller, chat, 'subagent.complete', {
              'subagent_id': status,
              'goal': 'Research $status',
              'status': status,
              'summary': 'Result for $status',
              'duration_seconds': 1.25,
            });
          }
          await showPanel(tester, brightness: brightness, scale: scale);
          final title = tester.widget<Text>(find.text(heading));
          expect(title.maxLines, 2);
          expect(title.overflow, TextOverflow.ellipsis);
          expect(find.text(longGoal), findsNothing);
          for (final label in [
            'Running',
            'Queued',
            'Completed',
            'Failed',
            'Interrupted',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          final queuedRow = find.byKey(
            ValueKey(('subagent', chat.key, 'queued')),
          );
          final queuedTime = tester.widget<ActivityTime>(
            find.descendant(of: queuedRow, matching: find.byType(ActivityTime)),
          );
          expect(queuedTime.backendStartedAt, isNull);
          expect(queuedTime.durationSeconds, isNull);
          await tester.ensureVisible(find.text(heading));
          await tester.pumpAndSettle();
          await tester.tap(find.text(heading));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.text('Task').first);
          await tester.pumpAndSettle();
          expect(find.text(longGoal), findsOneWidget);
          expect(find.byTooltip('Copy Task'), findsOneWidget);
          Navigator.of(tester.element(find.text(longGoal))).pop();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'a terminal tool name is activity context, not a reported result',
    (tester) async {
      fixture.rows = [
        {
          'subagent_id': 'child-1',
          'goal': 'Inspect the release',
          'status': 'completed',
          'last_tool': 'read_file',
        },
      ];
      await openDetails(tester);
      await tester.pumpAndSettle();
      expect(find.text('Reported result'), findsNothing);
      expect(find.textContaining('Last activity:'), findsOneWidget);
      expect(find.byTooltip('Copy Current activity'), findsNothing);
      expect(find.byTooltip('Steer'), findsNothing);
      expect(find.byTooltip('Interrupt'), findsNothing);
      Navigator.of(tester.element(find.text('Task').first)).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('backend metadata remains passive beside existing controls', (
    tester,
  ) async {
    await openDetails(tester);
    await tester.ensureVisible(find.byTooltip('Expand Raw details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand Raw details'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy Raw details'), findsNothing);
    expect(find.byTooltip('Open Raw details'), findsNothing);
    expect(find.byTooltip('Wrap Raw details'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SourceCodeText &&
            widget.text.contains('Agent ID: child-1'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy Task'), findsOneWidget);
    expect(find.byTooltip('Refresh subagent activity'), findsOneWidget);
    Navigator.of(tester.element(find.text('Raw details'))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('refresh retains two live event children beside a failed child', (
    tester,
  ) async {
    fixture.emptyList = true;
    emitChatEvent(controller, chat, 'subagent.complete', {
      'subagent_id': 'failed',
      'goal': 'Timed out research',
      'status': 'timeout',
    });
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'one',
      'goal': 'Research one',
    });
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'two',
      'goal': 'Research two',
    });
    await showPanel(tester);
    expect(chat.subagents.map((item) => item.id), ['failed', 'one', 'two']);
    expect(find.text('Research one'), findsOneWidget);
    expect(find.text('Research two'), findsOneWidget);
    expect(find.text('1 finished'), findsNothing);
  });

  testWidgets('unavailable canonical child keeps received task context', (
    tester,
  ) async {
    fixture.transcriptAvailable = false;
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'child-1',
      'goal': 'Inspect the release',
    });
    emitChatEvent(controller, chat, 'subagent.tool', {
      'subagent_id': 'child-1',
      'tool_name': 'read_file',
      'tool_preview': 'Checking android/app/build.gradle.kts',
    });
    await openDetails(tester);
    expect(
      find.textContaining('Checking android/app/build.gradle.kts'),
      findsWidgets,
    );
    expect(find.byTooltip('Refresh subagent activity'), findsOneWidget);
    expect(find.byTooltip('Steer'), findsOneWidget);
    await tester.tap(find.byTooltip('Close subagent activity'));
    await tester.pumpAndSettle();
  });

  testWidgets('canonical child reader keeps rejected steering text', (
    tester,
  ) async {
    await openDetails(tester);

    expect(find.byType(SubagentTimeline), findsOneWidget);
    expect(find.byTooltip('Steer'), findsOneWidget);
    expect(find.byTooltip('Interrupt'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Check the Android path');
    final steerButton = find.byTooltip('Steer');
    await tester.ensureVisible(steerButton);
    await tester.pumpAndSettle();
    await tester.tap(steerButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Steer rejected'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Check the Android path',
    );
    expect(chat.subagents.single.status.name, 'running');
    final steer = fixture.requests.lastWhere(
      (call) => call.$1 == 'subagent.steer',
    );
    expect(steer.$2['session_id'], chat.runtime.runtimeId);
    expect(steer.$2['subagent_id'], 'child-1');
    expect(steer.$2['text'], 'Check the Android path');

    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'populated event roster refreshes authoritative steering capability',
    (tester) async {
      emitChatEvent(controller, chat, 'subagent.start', {
        'subagent_id': 'child-1',
        'goal': 'Inspect the release',
        'status': 'running',
        'model': 'test-model',
      });
      expect(chat.subagents.single.acceptingSteer, isFalse);

      await showPanel(tester);

      expect(fixture.listCalls, 1);
      expect(chat.subagents.single.acceptingSteer, isTrue);
      await tester.ensureVisible(find.text('Inspect the release'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect the release'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip('Steer'), findsOneWidget);

      Navigator.of(tester.element(find.byTooltip('Steer'))).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'main transcript resource callbacks stay stable across streamed chunks',
    (tester) async {
      chat.reading.installSavedHistory([
        {'id': 1, 'role': 'assistant', 'content': 'Saved report context.'},
      ]);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: ProfileWorkspaceScreen(
            createBotsSession: () => BotsSession((_) async => const []),
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.widget<ProfileTranscript>(
        find.byType(ProfileTranscript),
      );
      emitChatEvent(controller, chat, 'message.delta', {
        'text': 'First streamed chunk.',
      });
      await tester.pumpAndSettle();
      final after = tester.widget<ProfileTranscript>(
        find.byType(ProfileTranscript),
      );
      expect(identical(before.loadImage, after.loadImage), isTrue);
      expect(identical(before.onOpenResource, after.onOpenResource), isTrue);
      expect(identical(before.onShareResource, after.onShareResource), isTrue);
      expect(
        identical(
          tester
              .widget<ProfileMessage>(find.byType(ProfileMessage).first)
              .loadAttachmentImage,
          after.loadImage,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final status in ['running', 'completed']) {
    testWidgets(
      'settled conversation ${status == 'completed' ? 'retires completed' : 'keeps running'} subagents in the bottom dock',
      (tester) async {
        fixture.rows = [
          {
            'subagent_id': 'child-1',
            'goal': 'Inspect the release',
            'status': status,
          },
        ];
        await controller.refreshSubagents(chat);
        chat.reading.installSavedHistory([
          {'id': 1, 'role': 'user', 'content': 'Inspect the release'},
          {
            'id': 2,
            'role': 'assistant',
            'content': 'The inspection is finished.',
          },
        ]);
        emitChatEvent(controller, chat, 'message.complete', {});
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: ProfileWorkspaceScreen(
              createBotsSession: () => BotsSession((_) async => const []),
              controller: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(chat.runtime.executionActive, isFalse);
        expect(chat.reading.streamingMessage, isNull);
        if (status == 'completed') {
          expect(find.byType(ProfileLiveWorkDock), findsNothing);
          expect(find.byType(ProfileSubagentPanel), findsNothing);
          expect(tester.takeException(), isNull);
          return;
        }
        expect(find.byType(ProfileLiveWorkDock), findsOneWidget);
        expect(find.byType(ProfileLiveExecution), findsNothing);
        expect(find.text('Activity'), findsNothing);
        expect(find.byType(ProfileSubagentPanel), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey(('live-work-tab', 0, false))),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey(('activity-tab', 'agents'))),
          findsNothing,
        );
        expect(find.byType(ProfileSubagentPanel), findsOneWidget);
        expect(find.text('Running'), findsOneWidget);
        final agent = find.byKey(ValueKey(('subagent', chat.key, 'child-1')));
        await tester.ensureVisible(agent);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: agent,
            matching: find.byIcon(Icons.chevron_right),
          ),
        );
        await tester.pumpAndSettle();
        await tester.settleMarkdown();
        expect(find.text('Task'), findsOneWidget);
        await tester.tap(find.text('Task'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Copy Task'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        emitChatEvent(controller, chat, 'message.start', {});
        emitChatEvent(controller, chat, 'message.delta', {
          'text': 'The next answer is streaming.',
        });
        await tester.pump();
        await tester.settleMarkdown();
        await tester.pump(const Duration(milliseconds: 300));
        expect(chat.runtime.executionActive, isTrue);
        expect(find.byType(ProfileLiveWorkDock), findsOneWidget);
        expect(find.byType(ProfileSubagentPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('live work Subagents opens this chat subagent roster', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    emitChatEvent(controller, chat, 'message.start', {});
    emitChatEvent(controller, chat, 'subagent.start', {
      'subagent_id': 'child-1',
      'goal': 'Inspect the release',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileWorkspaceScreen(
          createBotsSession: () => BotsSession((_) async => const []),
          controller: controller,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Inspect the release'), findsNothing);

    await tester.tap(find.byKey(const ValueKey(('live-work-tab', 0, false))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Inspect the release').last);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Inspect the release'), findsOneWidget);
    expect(fixture.listCalls, 1);
  });
}
