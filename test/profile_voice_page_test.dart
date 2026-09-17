import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_profile_voice_page.dart';
import 'package:wing/core/services/administration_repository.dart';
import 'package:wing/core/services/voice_sample.dart';
import 'package:wing/core/theme/profile_workspace_theme.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/profile_voice_fixture.dart';
import 'support/voice_fixture.dart';

void main() {
  const frame = Key('profile-voice-frame');
  const capture = bool.fromEnvironment('VOICE_REVIEW');
  setUpAll(() async {
    if (!capture) return;
    const path = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(
                File('$path/${entry.value}').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
  });
  Future<void> show(
    WidgetTester tester,
    ProfileVoiceFixture f,
    VoiceDeviceFixture device, {
    Brightness brightness = Brightness.light,
    WorkspaceAccent accent = WorkspaceAccent.mint,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wingTheme(
          brightness,
          accent: brightness == Brightness.dark ? accent.dark : accent.light,
        ),
        home: RepaintBoundary(
          key: frame,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: AdminProfileVoicePage(
              profile: f.server.profile('personal'),
              device: device,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> captureFrame(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(frame),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/vanilla-voice-review').createSync(recursive: true);
      await File(
        'build/vanilla-voice-review/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'selection autosaves before Play and Stop controls native playback',
    (tester) async {
      final f = ProfileVoiceFixture()..writeGate = Completer();
      final device = VoiceDeviceFixture()..playbackDelay = Completer();
      addTearDown(device.stream.close);
      await show(tester, f, device);
      expect(find.text('Save'), findsNothing);
      expect(find.text(voiceSampleText), findsOneWidget);
      await reveal(tester, find.text('Jenny'));
      await tester.tap(find.text('Jenny'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Play'))
            .onPressed,
        isNull,
      );
      f.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(
        setting(f.configs['personal']!, 'tts.edge.voice'),
        'en-US-JennyNeural',
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Play')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(device.calls, contains('play'));
      expect(device.calls, isNot(contains('speak')));
      expect(f.requests.singleWhere((r) => r.$2 == 'audio/speak').$4, {
        'text': voiceSampleText,
      });
      expect(find.text('Stop'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(device.playing, isNull);
      device.playbackDelay!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);
    },
  );

  for (final cancellation in ['stop', 'select', 'background', 'leave']) {
    testWidgets('$cancellation discards late synthesis', (tester) async {
      final f = ProfileVoiceFixture()..audioGate = Completer();
      final device = VoiceDeviceFixture();
      addTearDown(device.stream.close);
      await show(tester, f, device);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Preparing audio…'), findsOneWidget);
      switch (cancellation) {
        case 'stop':
          await tester.tap(find.text('Stop'));
        case 'select':
          await reveal(tester, find.text('Jenny'));
          await tester.tap(find.text('Jenny'));
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        case 'leave':
          await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      f.audioGate!.complete(f.audio);
      await tester.pumpAndSettle();
      expect(device.calls, isNot(contains('play')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }

  testWidgets('failed autosave requires refresh and retains confirmed voice', (
    tester,
  ) async {
    final f = ProfileVoiceFixture()..reject = true;
    final device = VoiceDeviceFixture();
    addTearDown(device.stream.close);
    await show(tester, f, device);
    await reveal(tester, find.text('Jenny'));
    await tester.tap(find.text('Jenny'));
    await tester.pumpAndSettle();
    expect(
      find.text('Save not confirmed. Refresh before trying again.'),
      findsOneWidget,
    );
    expect(find.text('Refresh required'), findsOneWidget);
    expect(
      setting(f.configs['personal']!, 'tts.edge.voice'),
      'en-US-AriaNeural',
    );
    f.reject = false;
    await tester.tap(find.byTooltip('Refresh voices'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('custom IDs autosave and ElevenLabs voices come from account', (
    tester,
  ) async {
    final f = ProfileVoiceFixture();
    setSetting(f.configs['personal']!, 'tts.provider', 'elevenlabs');
    final device = VoiceDeviceFixture();
    addTearDown(device.stream.close);
    await show(tester, f, device);
    expect(find.text('Storyteller'), findsOneWidget);
    await reveal(tester, find.text('Advanced'));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Voice ID');
    await reveal(tester, field);
    await tester.enterText(field, 'account-voice-123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      setting(f.configs['personal']!, 'tts.elevenlabs.voice_id'),
      'account-voice-123',
    );
    await reveal(tester, find.text('Storyteller'));
    await tester.tap(find.text('Storyteller'));
    await tester.pumpAndSettle();
    expect(
      setting(f.configs['personal']!, 'tts.elevenlabs.voice_id'),
      'custom-b',
    );
  });

  for (final brightness in Brightness.values) {
    for (final accent in WorkspaceAccent.values) {
      testWidgets('320dp 200% text $brightness $accent', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.reset);
        final f = ProfileVoiceFixture();
        setSetting(
          f.configs['personal']!,
          'tts.edge.voice',
          'en-US-A-very-long-custom-voice-ID',
        );
        final device = VoiceDeviceFixture();
        addTearDown(device.stream.close);
        await show(
          tester,
          f,
          device,
          brightness: brightness,
          accent: accent,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await captureFrame(tester, '${brightness.name}-${accent.name}-top');
        await tester.scrollUntilVisible(
          find.text('Jenny'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureFrame(tester, '${brightness.name}-${accent.name}-choices');
        await tester.scrollUntilVisible(
          find.text('Advanced'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text('Advanced')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(TextField, 'Voice ID'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
