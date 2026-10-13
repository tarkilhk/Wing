import 'package:wing/core/models/transcript_message.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/theme/bot_bubble_colors.dart';
import 'package:wing/core/widgets/profile_message.dart';
import 'package:wing/core/widgets/bot_avatar.dart';
import 'package:wing/core/models/bots.dart';
import 'package:wing/core/models/hermes_profile.dart';

import 'helpers/pump_markdown_widget.dart';

const _capture = bool.fromEnvironment('STUDIO_REVIEW');
const _frame = ValueKey('timestamp-frame');
const _messageFrame = ValueKey('message-frame');
final _date = DateTime(2026, 9, 15, 14, 7);

void main() {
  setUpAll(() async {
    if (!_capture) return;
    for (final entry in {
      'Roboto': 'build/studio-roboto.ttf',
      'Ahem': 'build/studio-roboto.ttf',
      'MaterialIcons': 'build/studio-icons.otf',
      'WingIcons': 'assets/fonts/wing-icons.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    required String role,
    Object? timestamp,
    Brightness brightness = Brightness.light,
    double scale = 1,
    String content = 'A short message.',
    bool showEditAction = false,
    VoidCallback? onEdit,
    bool showRestoreAction = false,
    VoidCallback? onRestore,
    BotRecord? senderAppearance,
    double width = 320,
    double height = 640,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpMarkdownWidget(
      RepaintBoundary(
        key: _frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wingTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (context) => RepaintBoundary(
                  key: _messageFrame,
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 4, 16),
                      child: ProfileMessage(
                        senderAppearance: senderAppearance,
                        showEditAction: showEditAction,
                        onEdit: onEdit,
                        showRestoreAction: showRestoreAction,
                        onRestore: onRestore,
                        message: TranscriptMessage.fromRow({
                          'id': 4,
                          'role': role,
                          'content': content,
                          'timestamp': timestamp,
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final long in [false, true]) {
        testWidgets('incoming bot bubble ${brightness.name} $scale long=$long', (
          tester,
        ) async {
          const body =
              '**Issue created**\n\n'
              'Deploy self-hosted Health Hub MCP for Android Health Connect ingestion.\n\n'
              '- Persistent storage and HTTPS\n'
              '- Backups and integration checks\n\n'
              '[View issue #620](https://gitea.hollinger.asia/Tarkil-Org/homelab-infra/issues/620)';
          final text = long ? body : '**Done.** Issue #620 is open.';
          final bot = BotRecord(
            scope: WorkspaceScope(
              connectionId: 'host',
              connectionIdentity: 'host-1',
              profileName: 'default',
            ),
            instance: 'Claw',
            profile: const HermesProfile(name: 'default'),
            title: 'Default',
            shape: 'squircle',
            color: '#8b5cf6',
            pinned: false,
            hidden: false,
            hasAvatar: false,
            revision: 1,
            metadata: const {},
          );
          await pump(
            tester,
            role: 'user',
            timestamp: _date.millisecondsSinceEpoch / 1000,
            brightness: brightness,
            scale: scale,
            width: scale == 1 ? 390 : 320,
            content: 'Message from 🤖 Default (@hermes): $text',
            senderAppearance: bot,
            showEditAction: true,
            showRestoreAction: true,
          );
          expect(find.text('Default'), findsOneWidget);
          expect(find.text('Show message'), findsNothing);
          expect(find.byTooltip('Copy message'), findsOneWidget);
          expect(find.byTooltip('Edit message'), findsNothing);
          expect(find.byTooltip('Restore checkpoint'), findsNothing);
          expect(
            tester.widget<BotAvatar>(find.byType(BotAvatar)).color,
            '#8b5cf6',
          );
          final bubble = tester.getRect(
            find.byKey(
              const ValueKey<(String, Object?)>(('bot-message-bubble', 4)),
            ),
          );
          final bubbleFinder = find.byKey(
            const ValueKey<(String, Object?)>(('bot-message-bubble', 4)),
          );
          final theme = Theme.of(tester.element(bubbleFinder));
          final palette = BotBubbleColors.fromAvatar(
            BotAvatar.resolveColor(bot.color, bot.title),
            theme,
          );
          expect(
            tester
                .widget<ColoredBox>(
                  find
                      .descendant(
                        of: bubbleFinder,
                        matching: find.byType(ColoredBox),
                      )
                      .first,
                )
                .color,
            palette.fill,
          );
          expect(
            tester
                .widget<ColoredBox>(
                  find.byKey(
                    const ValueKey<(String, Object?)>((
                      'bot-message-footer',
                      4,
                    )),
                  ),
                )
                .color,
            palette.footer,
          );
          expect(
            tester.widget<Text>(find.text('15 Sep, 14:07')).style?.color,
            palette.timestamp,
          );
          final avatar = tester.getRect(find.byType(BotAvatar));
          expect(avatar.left, closeTo(16, .01));
          expect(bubble.left, closeTo(avatar.right + 8, .01));
          final date = tester.getRect(find.text('15 Sep, 14:07'));
          expect(bubble.contains(date.topLeft), isTrue);
          expect(bubble.contains(date.bottomRight), isTrue);
          if (_capture) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_messageFrame),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/design-previews/bot-messages')
                ..createSync(recursive: true);
              await File(
                '${directory.path}/${brightness.name}-$scale-${long ? 'long' : 'short'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('${brightness.name} sent message actions at $scale', (
        tester,
      ) async {
        var edits = 0;
        var restores = 0;
        await pump(
          tester,
          role: 'user',
          timestamp: _date.toUtc().millisecondsSinceEpoch / 1000,
          brightness: brightness,
          scale: scale,
          content:
              'We actually need to wait to know timing of flight of the next day, to see if we should get a hotel close to airport (early morning flight), or if normal city hotel is OK (flight later during the day!)',
          showEditAction: true,
          onEdit: () => edits++,
          showRestoreAction: true,
          onRestore: () => restores++,
        );
        final copy = tester.getRect(find.byTooltip('Copy message'));
        final edit = tester.getRect(find.byTooltip('Edit message'));
        final restore = tester.getRect(find.byTooltip('Restore checkpoint'));
        final time = tester.getRect(find.text('15 Sep, 14:07'));
        final bubble = tester.getRect(
          find.byKey(
            const ValueKey<(String, Object?)>(('user-message-bubble', 4)),
          ),
        );
        expect(copy.left, closeTo(bubble.right, .01));
        expect(copy.top, closeTo(bubble.top, .01));
        final body = tester.getRect(find.byType(SelectableText));
        expect(time.top, greaterThanOrEqualTo(body.bottom));
        expect(bubble.contains(time.topLeft), isTrue);
        expect(bubble.contains(time.bottomRight), isTrue);
        expect(bubble.left, greaterThan(16));
        expect(time.left, closeTo(bubble.left + 10, .01));
        expect(time.overlaps(edit), isFalse);
        expect(time.overlaps(restore), isFalse);
        if (time.bottom > edit.top) {
          expect(time.right, lessThanOrEqualTo(edit.left));
        }
        expect(restore.right, closeTo(bubble.right - 2, .01));
        expect(edit.right, closeTo(restore.left, .01));
        expect(copy.right, closeTo(316, .01));
        expect(edit.size, const Size(48, 32));
        expect(restore.size, const Size(48, 32));
        expect(copy.size, const Size(44, 48));
        expect(find.text('Edit message'), findsNothing);
        expect(find.text('Copy message'), findsNothing);
        await tester.ensureVisible(find.byTooltip('Edit message'));
        final visibleEdit = tester.getRect(find.byTooltip('Edit message'));
        await tester.tapAt(
          Offset(visibleEdit.right - 2, visibleEdit.bottom - 2),
        );
        await tester.pumpAndSettle();
        expect(edits, 1);
        await tester.ensureVisible(find.byTooltip('Restore checkpoint'));
        final visibleRestore = tester.getRect(
          find.byTooltip('Restore checkpoint'),
        );
        await tester.tapAt(
          Offset(visibleRestore.right - 2, visibleRestore.bottom - 2),
        );
        await tester.pumpAndSettle();
        expect(restores, 1);
        if (_capture) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_messageFrame),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('build/chat-footer-review')
              ..createSync(recursive: true);
            await File(
              '${directory.path}/${brightness.name}-$scale.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${brightness.name} short prompt keeps disabled Edit and Copy reachable at $scale',
        (tester) async {
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await pump(
            tester,
            role: 'user',
            content: 'Hi',
            timestamp: _date.millisecondsSinceEpoch / 1000,
            brightness: brightness,
            scale: scale,
            showEditAction: true,
          );
          final edit = find.byTooltip('Edit message');
          final copy = find.byTooltip('Copy message');
          final editTarget = tester.getRect(edit);
          final copyTarget = tester.getRect(copy);
          final body = tester.getRect(find.byType(SelectableText));
          final time = tester.getRect(find.text('15 Sep, 14:07'));
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('edit-message-4')),
                )
                .onPressed,
            isNull,
          );
          expect(editTarget.size, const Size(48, 32));
          expect(copyTarget.size, const Size(44, 48));
          expect(body.right, lessThanOrEqualTo(copyTarget.left));
          final bubble = tester.getRect(
            find.byKey(
              const ValueKey<(String, Object?)>(('user-message-bubble', 4)),
            ),
          );
          expect(bubble.contains(time.topLeft), isTrue);
          expect(bubble.contains(time.bottomRight), isTrue);
          expect(time.left, closeTo(bubble.left + 10, .01));
          await tester.tapAt(
            Offset(copyTarget.right - 2, copyTarget.bottom - 2),
          );
          await tester.pumpAndSettle();
          expect(copied, 'Hi');
          expect(find.byType(SnackBar), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    for (final role in ['user', 'assistant']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${brightness.name} $role at $scale uses no extra space', (
          tester,
        ) async {
          for (final content in [
            'A short message.',
            'A longer message that wraps across multiple lines on a narrow phone.',
          ]) {
            await pump(
              tester,
              role: role,
              brightness: brightness,
              scale: scale,
              content: content,
            );
            final size = tester.getSize(find.byType(ProfileMessage));
            final copy = tester.getRect(find.byType(IconButton));
            final body = tester.getRect(find.byType(SelectableText).first);
            if (role == 'assistant') {
              expect(copy.top, closeTo(body.top, .01));
            }
            await pump(
              tester,
              role: role,
              brightness: brightness,
              scale: scale,
              content: content,
              timestamp: _date.millisecondsSinceEpoch / 1000,
            );
            expect(find.text('15 Sep, 14:07'), findsOneWidget);
            expect(tester.getSize(find.byType(ProfileMessage)), size);
            expect(tester.getRect(find.byType(IconButton)), copy);
            expect(tester.getRect(find.byType(SelectableText).first), body);
            expect(copy.width, greaterThanOrEqualTo(44));
            expect(copy.height, greaterThanOrEqualTo(48));
          }
          if (_capture) {
            await tester.runAsync(() async {
              final context = tester.element(find.byKey(_frame));
              for (final widget in tester.widgetList<Image>(
                find.byType(Image),
              )) {
                await precacheImage(widget.image, context);
              }
            });
            await tester.pumpAndSettle();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_frame),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory('build/message-timestamps')
                ..createSync(recursive: true);
              await File(
                '${directory.path}/${brightness.name}-$role-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }

  testWidgets('incoming bot Copy keeps the exact authored Markdown', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(
      tester,
      role: 'user',
      content: 'Message from 🤖 Pace (@pace): **Ready**\n\n- One\n- Two',
    );
    await tester.tap(find.byTooltip('Copy message'));
    await tester.pumpAndSettle();
    expect(copied, '**Ready**\n\n- One\n- Two');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'full local date is accessible, long press reveals it, copy stays text only',
    (tester) async {
      final semantics = tester.ensureSemantics();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      for (final role in ['user', 'assistant']) {
        await pump(
          tester,
          role: role,
          timestamp: _date.millisecondsSinceEpoch / 1000,
        );
        const full = 'Tuesday, September 15, 2026, 2:07 PM';
        expect(find.bySemanticsLabel(RegExp(full)), findsWidgets);
        await tester.longPress(find.text('15 Sep, 14:07'));
        await tester.pumpAndSettle();
        expect(find.text(full), findsOneWidget);
        await tester.tap(find.byIcon(Icons.copy_outlined));
        await tester.pumpAndSettle();
        expect(copied, 'A short message.');
      }
      semantics.dispose();
    },
  );

  testWidgets('missing and invalid timestamps do not invent a time', (
    tester,
  ) async {
    for (final value in [null, 'unknown', double.nan, double.infinity, 1e20]) {
      await pump(tester, role: 'user', timestamp: value);
      expect(find.text('15 Sep, 14:07'), findsNothing);
      expect(find.byType(Tooltip), findsOneWidget); // Copy only.
    }
  });
}
