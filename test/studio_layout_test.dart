import 'package:wing/core/widgets/studio_selection_tile.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/models/context_occupancy.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/connection_manager.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';
import 'package:wing/core/widgets/compact_switch.dart';
import 'package:wing/core/widgets/playful_portrait.dart';
import 'package:wing/main.dart';
import 'support/profile_browser_fixture.dart';

const _export = bool.fromEnvironment('STUDIO_REVIEW');
const _frame = ValueKey('studio-review-frame');

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
      SharedPreferences.setMockInitialValues({});
      final manager = await ConnectionManager.create(
        await SharedPreferences.getInstance(),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final viewport in [(360.0, 1.0), (320.0, 2.0)]) {
        await tester.binding.setSurfaceSize(Size(viewport.$1, 800));
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
            await tester.binding.setSurfaceSize(Size(width, 800));
            addTearDown(() => tester.binding.setSurfaceSize(null));
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
            final fixture = ProfileBrowserFixture();
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

            final projectActions = find.descendant(
              of: find.byKey(const ValueKey('project-p2')),
              matching: find.byTooltip('Project actions'),
            );
            final anchor = tester.getRect(projectActions);
            expect(anchor.size, const Size(48, 48));
            expect(find.byIcon(Icons.edit_square), findsNothing);
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
            await tester.longPress(find.byKey(const ValueKey('project-p2')));
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

            final chat = await controller.createChat();
            await tester.pumpAndSettle();
            if (export) {
              await _capture(tester, '${brightness.name}-empty-chat-$scale');
            }
            chat.title = 'A quieter workspace';
            chat.model = 'provider/a-very-long-model-route-for-small-screens';
            chat.reasoningEffort = 'high';
            chat.context = const ContextOccupancy(
              used: 42000,
              max: 128000,
              percent: 32.8,
              estimated: true,
            );
            chat.messages.addAll([
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
            ]);
            await tester.pumpAndSettle();
            chat.context = const ContextOccupancy(
              used: 42000,
              max: 128000,
              percent: 32.8,
              estimated: true,
            );
            await tester.enterText(
              find.byKey(const Key('profile-message-composer')),
              ' ',
            );
            await tester.enterText(
              find.byKey(const Key('profile-message-composer')),
              '',
            );
            await tester.pumpAndSettle();
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
              final callsBefore = fixture.calls.length;
              await _capture(
                tester,
                '${brightness.name}-administration-profile$adminSuffix',
              );
              for (final tab in ['Server', 'Health', 'Profile']) {
                await tester.tap(find.widgetWithText(Tab, tab));
                await tester.pumpAndSettle();
                await _capture(
                  tester,
                  '${brightness.name}-administration-${tab.toLowerCase()}$adminSuffix',
                );
              }
              expect(
                fixture.calls.length,
                callsBefore,
                reason: 'Tab navigation must not execute server operations',
              );
              expect(controller.current!.chat, same(chat));
              await tester.tap(find.byTooltip('Open navigation menu'));
              await tester.pumpAndSettle();
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
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
                      labelText: 'Connection name',
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
      const choice = ChatModelChoice(provider: 'openai', model: 'gpt-6-astra');
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
                  ChatModelChoice(provider: 'anthropic', model: 'claude-opus'),
                ],
                initialChoice: choice,
                initialReasoningEffort: 'high',
                defaultModel: choice.model,
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
