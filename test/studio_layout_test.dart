import 'support/chat_browser_interactions.dart';
import 'package:wing/core/widgets/studio_selection_tile.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/ws_client.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/screens/administration/administration_content.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/wing_icons.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';
import 'package:wing/core/widgets/model_chooser.dart';
import 'package:wing/core/widgets/compact_switch.dart';
import 'package:wing/core/widgets/playful_portrait.dart';
import 'package:wing/main.dart';
import 'support/profile_browser_fixture.dart';

const _export = bool.fromEnvironment('STUDIO_REVIEW');
const _frame = ValueKey('studio-review-frame');

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

class _StudioConversationFixture extends ProfileBrowserFixture {
  @override
  List<Map<String, dynamic>> projects(String profile) => [
    for (final project in super.projects(profile))
      {
        ...project,
        'sessionIds': project['isNoProject'] == true
            ? [
                'new-chat',
                for (final session in sessions(profile))
                  if (!{'newest', 'project-only'}.contains(session['id']))
                    session['id'],
              ]
            : project['id'] == 'p2' || project['id'] == 'work-project'
            ? ['newest', if (profile != 'work') 'project-only']
            : <String>[],
      },
  ];

  @override
  List<Map<String, dynamic>> sessions(String profile) => [
    for (final row in super.sessions(profile))
      {...row, if (row['id'] == 'newest') 'title': 'A quieter workspace'},
  ];

  @override
  List<Map<String, dynamic>> historyRows(String profile, String id) =>
      id != 'newest'
      ? []
      : [
          {
            'id': 1,
            'role': 'user',
            'content': 'Keep the workspace compact and easy to read.',
          },
          {
            'id': 2,
            'role': 'tool',
            'tool_name': 'Read project',
            'content': 'Inspect the existing screen and controls.',
          },
          {
            'id': 3,
            'role': 'assistant',
            'content':
                '## A little more room\n\nSearch is at the top. **New chat** stays within reach.\n\nThe activity details keep their familiar layout.\n\n```dart\nfinal profile = selectedProfile;\n```',
          },
        ];

  @override
  ProfileGateway gateway(WorkspaceScope scope) {
    final base = super.gateway(scope);
    return ProfileGateway(
      scope: scope,
      discover: base.discover,
      get: base.read,
      patch: (path, body) async {
        calls.add((scope.profileName, 'PATCH $path', body));
        return {'ok': true};
      },
      rpc: (method, params) async {
        final result = await base.call(method, params);
        if (method == 'session.resume') {
          return {
            ...result,
            'session_id': 'runtime-${params['session_id']}',
            'stored_session_id': params['session_id'],
            'info': {
              'profile_name': scope.profileName,
              'model': 'provider/a-very-long-model-route-for-small-screens',
              'reasoning_effort': 'high',
            },
          };
        }
        return result;
      },
    );
  }
}

class _StudioReviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  if (!_export) return;
  // Asset decoding runs outside the test clock. Finish it before exporting.
  final imageWidgets = tester.widgetList<Image>(find.byType(Image)).toList();
  final context = tester.element(find.byKey(_frame));
  await tester.runAsync(() async {
    await Future.wait(
      imageWidgets.map((image) => precacheImage(image.image, context)),
    );
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_frame),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/studio-review')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  if (_export) _StudioReviewBinding();

  setUpAll(() async {
    if (_export) {
      final font = File('build/studio-roboto.ttf');
      if (font.existsSync()) {
        for (final family in ['Roboto', 'Ahem']) {
          final loader = FontLoader(family)
            ..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            );
          await loader.load();
        }
        for (final entry in {
          'MaterialIcons': 'build/studio-icons.otf',
          'WingIcons': 'assets/fonts/wing-icons.ttf',
          'monospace': 'build/studio-mono.ttf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(File(entry.value).readAsBytesSync()),
              ),
            );
          await loader.load();
        }
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} first connection keeps setup reachable', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final manager = await ConnectionManager.create(
        await SharedPreferences.getInstance(),
      );
      addTearDown(tester.view.reset);
      for (final viewport in [(360.0, 1.0), (320.0, 2.0)]) {
        _viewport(tester, Size(viewport.$1, 800));
        await tester.pumpWidget(
          RepaintBoundary(
            key: _frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(viewport.$2)),
                child: child!,
              ),
              home: HomeScreen(connManager: manager),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PlayfulPortrait), findsOneWidget);
        expect(find.text('Your agent, with you'), findsOneWidget);
        await _capture(
          tester,
          '${brightness.name}-first-connection-${viewport.$2}',
        );
        await tester.scrollUntilVisible(
          find.text('Restore configuration'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(HomeScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Restore configuration').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });
    for (final accent in WorkspaceAccent.values) {
      test(
        'readable text and actions for ${brightness.name} ${accent.name}',
        () {
          final theme = profileWorkspaceTheme(
            wingTheme(brightness),
            accent: accent,
          );
          final colors = theme.colorScheme;
          for (final surface in [
            colors.surface,
            colors.surfaceContainer,
            colors.primaryContainer,
          ]) {
            expect(
              contrastRatio(colors.onSurface, surface),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrastRatio(colors.onSurfaceVariant, surface),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(
            contrastRatio(colors.onPrimary, colors.primary),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(colors.primary, colors.surfaceContainer),
            greaterThanOrEqualTo(4.5),
          );
        },
      );

      for (final viewport in [(360.0, 1.0), (320.0, 2.0), (840.0, 1.0)]) {
        final width = viewport.$1;
        final scale = viewport.$2;
        testWidgets(
          '${brightness.name} ${accent.name} at width $width and text scale $scale preserves composer targets and scope',
          (tester) async {
            _viewport(tester, Size(width, 800));
            addTearDown(tester.view.reset);
            SharedPreferences.setMockInitialValues({
              WorkspaceAccent.preferenceKey: accent.name,
            });
            PackageInfo.setMockInitialValues(
              appName: 'Wing',
              packageName: 'com.example.preview',
              version: '2.34.3',
              buildNumber: '1',
              buildSignature: '',
            );
            final fixture = _StudioConversationFixture();
            final controller = ProfileWorkspaceController(
              connection: SavedConnection(
                id: 'studio',
                label: 'Studio preview',
                host: 'unused',
                port: 1,
                apiKey: '',
              ),
              connectionIdentity: 'studio-layout',
              preferences: await SharedPreferences.getInstance(),
              gatewayFactory: fixture.gateway,
            );
            addTearDown(controller.dispose);
            await controller.initialize();
            await tester.pumpWidget(
              RepaintBoundary(
                key: _frame,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: profileWorkspaceTheme(
                    wingTheme(brightness),
                    accent: accent,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: ProfileWorkspaceScreen(controller: controller),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              MediaQuery.sizeOf(
                tester.element(find.byType(ProfileWorkspaceScreen)),
              ).width,
              width,
            );
            final search = tester.getRect(
              find.byKey(const ValueKey('workspace-search')),
            );
            final create = tester.getRect(
              find.byKey(const ValueKey('workspace-new-chat')),
            );
            expect(search.bottom, lessThan(400));
            expect(create.top, greaterThan(650));
            expect(create.height, greaterThanOrEqualTo(48));
            final export = accent == WorkspaceAccent.mint && width <= 360;
            if (export) {
              await _capture(tester, '${brightness.name}-chats-$scale');
            }

            await filterChatsToProfile(tester, 'personal');
            final clearFilters = find.byKey(
              const ValueKey('workspace-clear-filters'),
            );
            final clearRect = tester.getRect(clearFilters);
            expect(clearRect.width, greaterThanOrEqualTo(48));
            expect(clearRect.height, greaterThanOrEqualTo(48));
            await tester.tapAt(
              Offset(clearRect.right - 2, clearRect.center.dy),
            );
            await tester.pumpAndSettle();
            expect(tester.widget<IconButton>(clearFilters).onPressed, isNull);
            await filterChatsToProfile(tester, 'personal');
            await revealChatProject(tester, 'personal', 'p2');
            final projectActions = find.descendant(
              of: find.byKey(const ValueKey('project-personal-p2')),
              matching: find.byTooltip('Project actions'),
            );
            final anchor = tester.getRect(projectActions);
            expect(anchor.size, const Size(48, 48));
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('project-personal-p2')),
                matching: find.byIcon(WingIcons.newChat),
              ),
              findsNothing,
            );
            await tester.tap(projectActions);
            await tester.pumpAndSettle();
            final menu = find
                .ancestor(
                  of: find.byKey(const ValueKey('project-action-new')),
                  matching: find.byType(Material),
                )
                .first;
            final menuRect = tester.getRect(menu);
            expect(menuRect.width, lessThan(width - 16));
            expect(menuRect.right, closeTo(anchor.right, 1));
            expect(
              menuRect.top,
              closeTo((anchor.bottom + 4).clamp(8, 792 - menuRect.height), 1),
            );
            expect(menuRect.bottom, lessThanOrEqualTo(792));
            expect(find.byType(BottomSheet), findsNothing);
            if (export) {
              await _capture(tester, '${brightness.name}-project-menu-$scale');
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('project-action-new')),
              findsNothing,
            );
            await tester.longPress(
              find.byKey(const ValueKey('project-personal-p2')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('project-action-rename')),
              findsOneWidget,
            );
            await tester.tapAt(const Offset(8, 8));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('project-action-new')),
              findsNothing,
            );

            await controller.createChat();
            await tester.pumpAndSettle();
            if (export) {
              await _capture(tester, '${brightness.name}-empty-chat-$scale');
            }
            final chat = (await controller.openSession(
              ProfileSessionKey(controller.current!.scope, 'newest'),
            ))!;
            controller.current!.gateway.onEvent!(
              StreamEvent(
                type: 'session.usage',
                sessionId: chat.runtimeId,
                data: {
                  'usage': {
                    'context_used': 42000,
                    'context_max': 128000,
                    'context_percent': 32.8,
                    'context_estimated': true,
                  },
                },
              ),
            );
            await tester.pumpAndSettle();
            expect(chat.context?.used, 42000);
            expect(chat.markReadFailed, isFalse);
            expect(chat.projectLookupFailed, isFalse);
            expect(controller.chatProjectLabel(chat), 'Mobile app');
            expect(find.text('Project unavailable'), findsNothing);
            expect(
              find.textContaining(
                'This chat opened, but it could not be marked',
              ),
              findsNothing,
            );
            expect(find.text('A quieter workspace'), findsOneWidget);
            expect(
              find.textContaining('A little more room', findRichText: true),
              findsWidgets,
            );
            expect(find.text('Start a conversation'), findsNothing);
            expect(
              find.byKey(
                ValueKey(
                  scale > 1.5 && width < 480
                      ? 'chat-scope-stacked'
                      : 'chat-scope-inline',
                ),
              ),
              findsOneWidget,
            );
            final ring = tester.getRect(
              find.byKey(const ValueKey('context-ring-details')),
            );
            final model = tester.getRect(
              find.byKey(const Key('chat-intelligence-button')),
            );
            final send = tester.getRect(find.byTooltip('Send'));
            expect(ring.width, greaterThanOrEqualTo(48));
            expect(ring.height, greaterThanOrEqualTo(48));
            expect(model.width, greaterThanOrEqualTo(48));
            expect(send.width, greaterThanOrEqualTo(48));
            expect(ring.overlaps(model), isFalse);
            expect(model.overlaps(send), isFalse);
            expect(send.right, lessThanOrEqualTo(width));
            expect(tester.takeException(), isNull);
            if (export) {
              await _capture(tester, '${brightness.name}-conversation-$scale');
            }

            await tester.enterText(
              find.byKey(const Key('profile-message-composer')),
              'An unsent draft\nwith a second line',
            );
            tester.view.viewInsets = FakeViewPadding(
              bottom: 280 * tester.view.devicePixelRatio,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(controller.current!.chat, same(chat));
            expect(chat.draft, contains('An unsent draft'));
            if (export) {
              await _capture(tester, '${brightness.name}-keyboard-$scale');
              final heldAction = await tester.startGesture(
                tester.getCenter(find.byTooltip('Send')),
              );
              await tester.pump(const Duration(milliseconds: 600));
              await heldAction.moveTo(
                tester.getCenter(
                  find.byKey(const ValueKey('composer-choice-queue')),
                ),
              );
              await tester.pump(const Duration(milliseconds: 100));
              await _capture(
                tester,
                '${brightness.name}-held-action-transition-$scale',
              );
              await tester.pump(const Duration(milliseconds: 220));
              await _capture(tester, '${brightness.name}-held-action-$scale');
              await heldAction.cancel();
              await tester.pumpAndSettle();
              expect(chat.draft, contains('An unsent draft'));
            }
            tester.view.resetViewInsets();
            await tester.pumpAndSettle();

            if (export) {
              final adminSuffix = scale == 1 ? '' : '-large-text';
              await tester.tap(find.byTooltip('Open navigation menu'));
              await tester.pumpAndSettle();
              await _capture(tester, '${brightness.name}-drawer$adminSuffix');
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('nav-administration')),
                200,
                scrollable: find.descendant(
                  of: find.byType(Drawer),
                  matching: find.byType(Scrollable),
                ),
              );
              await Scrollable.ensureVisible(
                tester.element(
                  find.byKey(const ValueKey('nav-administration')),
                ),
                alignment: .5,
              );
              await tester.pumpAndSettle();
              await tester.tap(
                find.byKey(const ValueKey('nav-administration')),
              );
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '${brightness.name}-administration-profile$adminSuffix',
              );
              expect(find.byType(TabBar), findsNothing);
              await tester.tap(find.byTooltip('Open navigation menu'));
              await tester.pumpAndSettle();
              final health = find.byKey(const ValueKey('nav-health'));
              await tester.scrollUntilVisible(
                health,
                200,
                scrollable: find.descendant(
                  of: find.byType(Drawer),
                  matching: find.byType(Scrollable),
                ),
              );
              await Scrollable.ensureVisible(
                tester.element(health),
                alignment: .5,
              );
              await tester.pumpAndSettle();
              expect(health.hitTestable(), findsOneWidget);
              await tester.tap(health);
              await tester.pumpAndSettle();
              expect(find.byType(HermesHealthContent), findsOneWidget);
              await _capture(
                tester,
                '${brightness.name}-administration-health$adminSuffix',
              );
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
              expect(controller.current!.chat, same(chat));
              await tester.scrollUntilVisible(
                find.byKey(const ValueKey('nav-settings')),
                200,
                scrollable: find.descendant(
                  of: find.byType(Drawer),
                  matching: find.byType(Scrollable),
                ),
              );
              await tester.tap(find.byKey(const ValueKey('nav-settings')));
              await tester.pumpAndSettle();
              await _capture(tester, '${brightness.name}-settings$adminSuffix');
              await tester.scrollUntilVisible(
                find.text('While your agent is working'),
                200,
                scrollable: find.byType(Scrollable).last,
              );
              await tester.pumpAndSettle();
              await _capture(
                tester,
                '${brightness.name}-settings-actions$adminSuffix',
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }

    testWidgets('${brightness.name} control and intelligence specimens', (
      tester,
    ) async {
      _viewport(tester, const Size(420, 1000));
      addTearDown(tester.view.reset);
      final theme = wingTheme(brightness);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('Studio controls')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Primary'),
                      ),
                      FilledButton.tonal(
                        onPressed: () {},
                        child: const Text('Tonal'),
                      ),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Secondary'),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Text action'),
                      ),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('Elevated'),
                      ),
                      const FilledButton(
                        onPressed: null,
                        child: Text('Unavailable'),
                      ),
                      IconButton.filled(
                        onPressed: () {},
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: 'Instance name',
                      hintText: 'Workstation',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: 'Required field',
                      errorText: 'Enter a value to continue',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Selected'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      FilterChip(
                        label: const Text('Filter'),
                        selected: false,
                        onSelected: (_) {},
                      ),
                      ActionChip(label: const Text('Action'), onPressed: () {}),
                      InputChip(
                        label: const Text('Attachment'),
                        onDeleted: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Skills')),
                      ButtonSegment(value: 1, label: Text('Tools')),
                    ],
                    selected: const {0},
                    onSelectionChanged: (_) {},
                  ),
                  CompactSwitchListTile(
                    value: true,
                    onChanged: (_) {},
                    title: const Text('Enabled preference'),
                  ),
                  StudioSelectionTile(
                    value: true,
                    onChanged: (_) {},
                    title: const Text('Selected option'),
                  ),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Panel title'),
                      subtitle: Text('Readable secondary information'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, '${brightness.name}-controls');
      const choice = ModelChoice(provider: 'openai', model: 'gpt-6-astra');
      await tester.pumpWidget(
        RepaintBoundary(
          key: _frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Scaffold(
              body: ChatIntelligenceSheet(
                choices: const [
                  choice,
                  ModelChoice(provider: 'anthropic', model: 'claude-opus'),
                ],
                initialChoice: choice,
                initialReasoningEffort: 'high',
                defaultModel: choice.model,
                profileName: 'personal',
                onRefreshModels: () async => const [choice],
                onReviewProviderAccess: () {},
                onApply: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, '${brightness.name}-intelligence');
    });
  }
}
