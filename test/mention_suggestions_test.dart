import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/composer_reference.dart';
import 'package:wing/core/models/slash_command.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/mention_suggestions.dart';
import 'package:wing/core/widgets/slash_command_suggestions.dart';
import 'package:wing/core/screens/bots/bot_group_screen.dart';
import 'package:wing/core/services/bots_session.dart';
import 'package:wing/core/widgets/bot_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/bots_fixture.dart';

const _captureKey = ValueKey('references-render');
const _agent = MentionCandidate(
  label: 'Hermes',
  detail: '@hermes',
  reference: ComposerReference(
    kind: ComposerReferenceKind.agent,
    token: '@hermes',
    target: 'hermes',
  ),
);
const _folder = MentionCandidate(
  label: 'Design documents',
  detail: 'Folder',
  reference: ComposerReference(
    kind: ComposerReferenceKind.folder,
    token: '@folder:`/work/Design documents`',
    target: '/work/Design documents',
  ),
);

void main() {
  testWidgets('references retain emphasis beside native commands and skills', (
    tester,
  ) async {
    const file = ComposerReference(
      kind: ComposerReferenceKind.file,
      token: '@file:"/work/design note.md"',
      target: '/work/design note.md',
    );
    final input = SkillComposerController(
      text: '/bg use /plugin:skill with ${file.token} and @hermes',
    );
    addTearDown(input.dispose);
    input.setScope('first-chat');
    input.observeCommands(const [
      SlashCommand('/bg', 'Background task', 'Session'),
      SlashCommand('/plugin:skill', '', 'Skills'),
    ]);
    input.observeReferences([file, _agent.reference]);
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(Brightness.light),
        home: Scaffold(body: TextField(controller: input)),
      ),
    );
    final context = tester.element(find.byType(EditableText));
    List<TextSpan> spans() => input
        .buildTextSpan(context: context, withComposing: true)
        .children!
        .whereType<TextSpan>()
        .toList();
    final native = spans().singleWhere((span) => span.text == '/bg');
    expect(native.style!.fontFamily, 'monospace');
    expect(native.style!.fontWeight, FontWeight.w400);
    for (final token in ['/plugin:skill', file.token, '@hermes']) {
      final span = spans().singleWhere((span) => span.text == token);
      expect(span.style!.fontWeight, FontWeight.w700);
      expect(span.style!.fontFamily, isNull);
      expect(span.style!.color, Theme.of(context).colorScheme.primary);
    }
    final start = input.text.indexOf('design');
    final selection = TextSelection.collapsed(offset: start + 6);
    input.value = input.value.copyWith(
      selection: selection,
      composing: TextRange(start: start, end: start + 6),
    );
    final composing = spans()
        .where((span) => span.style!.decoration == TextDecoration.underline)
        .toList();
    expect(composing.map((span) => span.text).join(), 'design');
    expect(
      composing.every((span) => span.style!.fontWeight == FontWeight.w700),
      isTrue,
    );
    expect(
      input.buildTextSpan(context: context, withComposing: true).toPlainText(),
      input.text,
    );
    expect(input.selection, selection);
    input.setScope('next-chat');
    expect(spans().any((span) => span.text == '@hermes'), isFalse);
    expect(
      spans().any((span) => span.style!.fontFamily == 'monospace'),
      isFalse,
    );
  });

  setUpAll(() async {
    final fonts = Platform.environment['CAPTURE_REFERENCE_FONTS'];
    if (fonts == null) return;
    for (final entry in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final font in entry.value) {
        loader.addFont(
          File('$fonts/$font').readAsBytes().then((b) => b.buffer.asByteData()),
        );
      }
      await loader.load();
    }
  });

  Future<void> host(
    WidgetTester tester,
    SkillComposerController composer,
    FocusNode focus, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    required Future<MentionCompletion> Function(
      MentionQuery,
      String?,
      bool Function(),
    )
    load,
    required Future<void> Function(String, ComposerReference) select,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: _captureKey,
          child: Scaffold(
            appBar: AppBar(title: const Text('Conversation')),
            body: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  const Expanded(child: Center(child: Text('Message'))),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: MentionSuggestions(
                            composer: composer,
                            composerFocus: focus,
                            load: load,
                            select: select,
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * .7,
                          ),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: TextField(
                                controller: composer,
                                focusNode: focus,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  testWidgets(
    'folder browsing keeps text; selection preserves the suffix and focus',
    (tester) async {
      final composer = SkillComposerController.fromValue(
        const TextEditingValue(
          text: 'Look @ now',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      final focus = FocusNode();
      addTearDown(composer.dispose);
      addTearDown(focus.dispose);
      final browsed = <String?>[], saved = <String>[];
      await host(
        tester,
        composer,
        focus,
        load: (query, directory, canRead) async {
          browsed.add(directory);
          return MentionCompletion(
            query: query,
            items: [_agent, _folder],
            directory: directory ?? '/work',
            parent: '/',
          );
        },
        select: (text, ref) async {
          saved.add(text);
        },
      );
      await tester.tap(find.text('Design documents'));
      await tester.pump();
      expect(composer.text, 'Look @ now');
      expect(saved, isEmpty);
      expect(browsed.last, '/work/Design documents');
      await tester.tap(find.byTooltip('Add this folder as context'));
      await tester.pump();
      expect(saved.single, 'Look @folder:`/work/Design documents`  now');
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dismissal retires a held completion; a fresh query can retry', (
    tester,
  ) async {
    final composer = SkillComposerController(text: '@h');
    composer.selection = const TextSelection.collapsed(offset: 2);
    final focus = FocusNode(), held = Completer<MentionCompletion>();
    MentionQuery? issued;
    bool Function()? canReadAppearance;
    addTearDown(composer.dispose);
    addTearDown(focus.dispose);
    await host(
      tester,
      composer,
      focus,
      load: (query, directory, canRead) {
        issued = query;
        canReadAppearance = canRead;
        return held.future;
      },
      select: (text, ref) async {},
    );
    expect(canReadAppearance!(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(canReadAppearance!(), isFalse);
    held.complete(MentionCompletion(query: issued!, items: [_agent]));
    await tester.pump();
    expect(find.text('Hermes'), findsNothing);
    expect(composer.text, '@h');
  });

  testWidgets(
    'failed completion retries without draft changes; enlarged partial results scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      final composer = SkillComposerController(text: '@h');
      composer.selection = const TextSelection.collapsed(offset: 2);
      final focus = FocusNode();
      addTearDown(composer.dispose);
      addTearDown(focus.dispose);
      var calls = 0;
      await host(
        tester,
        composer,
        focus,
        scale: 2,
        load: (query, directory, canRead) async {
          if (++calls == 1) throw StateError('Read failed');
          return MentionCompletion(
            query: query,
            items: [_agent],
            warning:
                'Server files are unavailable. Agent references are still available.',
          );
        },
        select: (text, ref) async {},
      );
      expect(find.byTooltip('Retry references').hitTestable(), findsOneWidget);
      final before = composer.value;
      await tester.tap(find.byTooltip('Retry references'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(composer.value, before);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'IME composition suppresses selection and skill picker coexists',
    (tester) async {
      final composer = SkillComposerController.fromValue(
        const TextEditingValue(
          text: '@he',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 1, end: 3),
        ),
      );
      final focus = FocusNode();
      addTearDown(composer.dispose);
      addTearDown(focus.dispose);
      var requests = 0;
      await host(
        tester,
        composer,
        focus,
        load: (query, directory, canRead) async {
          requests++;
          return MentionCompletion(query: query, items: [_agent]);
        },
        select: (text, ref) async {},
      );
      expect(requests, 0);
      composer.value = composer.value.copyWith(composing: TextRange.empty);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('Hermes'), findsOneWidget);
      expect(composer.value.composing, TextRange.empty);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('references render with keyboard at $scale in $brightness', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.reset);
        final composer = SkillComposerController(text: '@');
        composer.selection = const TextSelection.collapsed(offset: 1);
        final focus = FocusNode();
        addTearDown(composer.dispose);
        addTearDown(focus.dispose);
        await host(
          tester,
          composer,
          focus,
          brightness: brightness,
          scale: scale,
          load: (query, directory, canRead) async => MentionCompletion(
            query: query,
            items: [
              _agent,
              _folder,
              const MentionCandidate(
                label: 'A long reference filename that must remain readable.md',
                detail: '128 bytes',
                reference: ComposerReference(
                  kind: ComposerReferenceKind.file,
                  token: '@file:/work/long.md',
                  target: '/work/long.md',
                ),
              ),
            ],
            directory: '/home/user/projects/very-long-workspace-directory',
            parent: '/home/user/projects',
          ),
          select: (text, ref) async {},
        );
        expect(tester.takeException(), isNull);
        for (final button in tester.widgetList<IconButton>(
          find.byType(IconButton),
        )) {
          expect(button.tooltip, isNotEmpty);
        }
        if (Platform.environment.containsKey('CAPTURE_REFERENCES')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(_captureKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory('build/references-review')
              ..createSync(recursive: true);
            await File(
              '${dir.path}/${brightness.name}-$scale.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
      testWidgets(
        'group references remain reachable above keyboard at $scale in $brightness',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
          addTearDown(tester.view.reset);
          final fixture = BotsFixture();
          fixture.profiles[1]['ui_meta']['hermes-bots']['shape'] = 'hexagon';
          fixture.profiles[1]['ui_meta']['hermes-bots']['color'] = '#8b5cf6';
          final owner = BotsSession((_) async => [fixture.repository]);
          addTearDown(owner.dispose);
          await owner.refresh();
          final group = owner.state.groups.first;
          await tester.pumpWidget(
            MaterialApp(
              theme: wingTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 280),
                ),
                child: child!,
              ),
              home: RepaintBoundary(
                key: _captureKey,
                child: BotGroupScreen(
                  createSession: () => owner.openGroup(group),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '@');
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          final list = find.descendant(
            of: find.byType(MentionSuggestions),
            matching: find.byType(ListView),
          );
          for (final expected in [
            ('atlas', 'squircle', '#65c7bc', 32.0),
            ('mira', 'hexagon', '#8b5cf6', 32.0),
          ]) {
            final avatar = find.byWidgetPredicate(
              (widget) => widget is BotAvatar && widget.name == expected.$1,
            );
            await tester.scrollUntilVisible(
              avatar,
              80,
              scrollable: find.descendant(
                of: list,
                matching: find.byType(Scrollable),
              ),
            );
            final rendered = tester.widget<BotAvatar>(avatar);
            expect((
              rendered.name,
              rendered.shape,
              rendered.color,
              rendered.size,
            ), expected);
          }
          await tester.drag(list, const Offset(0, 300));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
          if (Platform.environment.containsKey('CAPTURE_REFERENCES')) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_captureKey),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('build/references-review');
              await dir.create(recursive: true);
              await File(
                '${dir.path}/group-avatars-${brightness.name}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await tester.scrollUntilVisible(
            find.text('Everyone'),
            80,
            scrollable: find.descendant(
              of: list,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
          expect(find.text('Everyone').hitTestable(), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Atlas'),
            -80,
            scrollable: find.descendant(
              of: list,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Atlas'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '@bot_atlas ',
          );
          await tester.enterText(
            find.byType(TextField),
            'Review\nall\nthis\ntext\ncarefully\n@every',
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          expect(
            find.byTooltip('Close references').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Everyone'), findsOneWidget);
          expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (Platform.environment.containsKey('CAPTURE_REFERENCES')) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_captureKey),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory('build/references-review')
                  ..createSync(recursive: true);
                await File(
                  '${dir.path}/group-${brightness.name}-$scale.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
