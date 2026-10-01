// Profile-only full-app observer. All mutations target chats created here.
// flutter build apk --profile -t tools/performance/live_stream.dart
// No credentials, addresses, profile names or transcript text leave this tool.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wing/core/models/answer_versions.dart';
import 'package:wing/core/screens/profile_workspace_screen.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';
import 'package:wing/core/widgets/background_markdown_content.dart';
import 'package:wing/core/widgets/chat_intelligence_picker.dart';
import 'package:wing/core/widgets/markdown_message_content.dart';
import 'package:wing/main.dart' as app;

const _prompts = {
  'prose':
      'Wing performance QA. Do not use tools, memories, files or delegation. '
      'Write about 1200 words of ordinary prose describing an imaginary garden. '
      'Use twenty paragraphs. Include italic and bold phrases and occasional '
      'technical identifiers such as garden_path_index. No code blocks. '
      'Finish with the exact sentence: Wing prose QA complete.',
  'mixed':
      'Wing performance QA. Do not use tools, memories, files or delegation. '
      'Write about 1200 words explaining an imaginary garden planner. Include '
      'headings, paragraphs, nested lists, a small Markdown table, ordinary '
      'links to https://example.com and six fenced Dart code examples. '
      'Finish with the exact sentence: Wing mixed QA complete.',
};

Iterable<Element> _walk(Element element) sync* {
  if (element.widget case Offstage(offstage: true)) return;
  yield element;
  final children = <Element>[];
  element.visitChildren(children.add);
  for (final child in children) {
    yield* _walk(child);
  }
}

ProfileWorkspaceController _controller() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) throw StateError('Not mounted');
  return _walk(
    root,
  ).map((e) => e.widget).whereType<ProfileWorkspaceScreen>().single.controller;
}

class _Owned {
  _Owned(this.controller, this.chat);
  final ProfileWorkspaceController controller;
  final ProfileChat chat;
  bool dispatching = false;
  bool dispatchFailed = false;
  int submissions = 0;
  String? preservedDraft;
  String? mode;
  int responseBaseCount = 0;

  String? get finalResponse {
    for (var i = chat.messages.length - 1; i >= responseBaseCount; i--) {
      if (chat.messages[i]['role'] == 'assistant') {
        return answerMessageText(chat.messages[i]);
      }
    }
    return null;
  }

  String get sentinel =>
      mode == 'mixed' ? 'Wing mixed QA complete.' : 'Wing prose QA complete.';
}

class _Measurement {
  _Measurement(this.owned) {
    timer = Timer.periodic(const Duration(milliseconds: 20), (_) => sample());
  }
  final _Owned owned;
  final startUs = developer.Timeline.now;
  late final Timer timer;
  final samples = <Map<String, Object?>>[];
  final frames = <Map<String, int>>[];
  int sourceChanges = 0, previousLength = 0, maximumLength = 0;
  int? firstTextUs, firstReadyUs, completedUs;
  int renderedCharacters = 0, pendingParses = 0;
  bool renderReady = false;
  bool finalSentinelVisible = false, latestResponseMounted = false;
  int? latestSourceObservedUs, latestReadyLagUs, finalReadyUs;
  int? _lastReadySourceObservedUs;
  int _lastRenderSample = 0;

  void sample() {
    final now = developer.Timeline.now;
    final chat = owned.chat;
    final length = chat.streaming.length;
    if (length != previousLength) {
      sourceChanges++;
      previousLength = length;
      if (length > maximumLength) maximumLength = length;
      if (length > 0) firstTextUs ??= now;
      if (length > 0) latestSourceObservedUs = now;
    }
    if (!chat.busy && maximumLength > 0) completedUs ??= now;
    if (now - _lastRenderSample < 100000) return;
    _lastRenderSample = now;
    renderedCharacters = 0;
    pendingParses = 0;
    renderReady = false;
    finalSentinelVisible = false;
    latestResponseMounted = false;
    final root = WidgetsBinding.instance.rootElement;
    if (root != null &&
        maximumLength > 0 &&
        owned.controller.current?.chat == chat) {
      final source = chat.streaming.isNotEmpty
          ? chat.streaming
          : owned.finalResponse;
      final bodies = _walk(root).where(
        (e) =>
            e.widget is MarkdownMessageContent &&
            (e.widget as MarkdownMessageContent).data == source,
      );
      var allReady = true;
      for (final body in bodies) {
        latestResponseMounted = true;
        final states = _walk(body)
            .whereType<StatefulElement>()
            .map((e) => e.state)
            .whereType<BackgroundMarkdownContentState>()
            .toList();
        renderedCharacters += states.fold<int>(
          0,
          (n, s) => n + (s.renderedSource?.length ?? 0),
        );
        pendingParses += states.where((s) => s.pending).length;
        allReady =
            allReady &&
            states.every(
              (s) => !s.pending && s.renderedSource == s.widget.data,
            );
        if (renderedCharacters > 0) firstReadyUs ??= now;
        finalSentinelVisible =
            finalSentinelVisible ||
            _walk(body).any(
              (e) =>
                  e.widget is RichText &&
                  (e.widget as RichText).text.toPlainText().contains(
                    owned.sentinel,
                  ),
            );
      }
      renderReady = latestResponseMounted && allReady;
      if (renderReady &&
          latestSourceObservedUs != null &&
          _lastReadySourceObservedUs != latestSourceObservedUs) {
        latestReadyLagUs = now - latestSourceObservedUs!;
        _lastReadySourceObservedUs = latestSourceObservedUs;
      }
      if (!chat.busy && renderReady && owned.finalResponse != null) {
        finalReadyUs ??= now;
      }
    }
    samples.add({
      'timeUs': now,
      'sourceCharacters': length,
      'renderedProseCharacters': renderedCharacters,
      'pendingParses': pendingParses,
      'renderReady': renderReady,
      'draftCharacters': chat.composerText.length,
      'selected': owned.controller.current?.chat == chat,
      'busy': chat.busy,
      'latestResponseMounted': latestResponseMounted,
    });
  }

  void timings(List<FrameTiming> timings) {
    for (final frame in timings) {
      final start = frame.timestampInMicroseconds(FramePhase.buildStart);
      if (start >= startUs) {
        frames.add({
          'startUs': start,
          'buildUs': frame.buildDuration.inMicroseconds,
          'rasterUs': frame.rasterDuration.inMicroseconds,
        });
      }
    }
  }

  Map<String, Object?> report() => {
    'startUs': startUs,
    'endUs': developer.Timeline.now,
    'sourcePollIntervalUs': 20000,
    'renderPollIntervalUs': 100000,
    'observedSourceChanges': sourceChanges,
    'maximumSourceCharacters': maximumLength,
    'firstObservedTextUs': firstTextUs,
    'firstObservedReadyUs': firstReadyUs,
    'firstTextToReadyObservedUs': firstTextUs == null || firstReadyUs == null
        ? null
        : firstReadyUs! - firstTextUs!,
    'firstObservedCompletionUs': completedUs,
    'latestSourceToReadyObservedUs': latestReadyLagUs,
    'completionToReadyObservedUs': completedUs == null || finalReadyUs == null
        ? null
        : finalReadyUs! - completedUs!,
    'finalSentinelVisible': finalSentinelVisible,
    'samples': samples,
    'frames': frames,
  };
}

void main() {
  if (!kProfileMode) throw StateError('Use an AOT profile build');
  WidgetsFlutterBinding.ensureInitialized();
  final owned = <_Owned>[];
  _Measurement? measurement;
  var mutating = false;
  _Owned selected(Map<String, String> parameters) {
    final slot = int.tryParse(parameters['slot'] ?? '');
    if (slot == null || slot < 0 || slot >= owned.length) {
      throw StateError('Unknown owned slot');
    }
    return owned[slot];
  }

  Map<String, Object?> snapshot(_Owned item) => {
    'selected': item.controller.current?.chat == item.chat,
    'luna': RegExp(r'^gpt-\d+\.\d+-luna$').hasMatch(item.chat.model ?? ''),
    'busy': item.chat.busy,
    'status': item.chat.status.name,
    'sourceCharacters': item.chat.streaming.length,
    'savedMessages': item.chat.messages.length,
    'draftCharacters': item.chat.composerText.length,
    'draftPreserved': item.preservedDraft == null
        ? null
        : item.preservedDraft == item.chat.composerText,
    'chatError': item.chat.error != null,
    'controllerError': item.controller.error != null,
    'toolActivityCount': item.chat.toolActivities.length,
    'subagentCount': item.chat.subagents.length,
    'dispatching': item.dispatching,
    'dispatchFailed': item.dispatchFailed,
    'submissions': item.submissions,
    'finalResponseCharacters': item.finalResponse?.length ?? 0,
    'finalResponseComplete':
        item.mode != null &&
        item.finalResponse?.trimRight().endsWith(item.sentinel) == true,
    'renderReady': measurement?.owned == item ? measurement?.renderReady : null,
    'pendingParses': measurement?.owned == item
        ? measurement?.pendingParses
        : null,
    'renderedProseCharacters': measurement?.owned == item
        ? measurement?.renderedCharacters
        : null,
    'finalSentinelVisible': measurement?.owned == item
        ? measurement?.finalSentinelVisible
        : null,
  };
  WidgetsBinding.instance.addTimingsCallback((frames) {
    measurement?.timings(frames);
  });
  for (final action in [
    'prepare',
    'open',
    'stage',
    'submit',
    'snapshot',
    'markDraft',
    'start',
    'stop',
    'cancel',
  ]) {
    developer.registerExtension('ext.wingLive.$action', (_, parameters) async {
      final mutation = !{
        'snapshot',
        'markDraft',
        'start',
        'stop',
      }.contains(action);
      if (mutation && mutating) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'Operation busy',
        );
      }
      if (mutation) mutating = true;
      try {
        if (action == 'prepare') {
          final controller = _controller();
          if (!controller.initialized ||
              controller.current == null ||
              controller.current!.chat?.busy == true) {
            throw StateError('Wait for the current chat');
          }
          final chat = await controller.createChat();
          final item = _Owned(controller, chat);
          owned.add(item);
          final options = await controller.loadIntelligence(chat);
          final choices = options.choices
              .where(
                (c) =>
                    RegExp(r'^gpt-\d+\.\d+-luna$').hasMatch(c.model) &&
                    (parameters['model'] == null ||
                        c.model == parameters['model']) &&
                    (parameters['provider'] == null ||
                        c.provider == parameters['provider']),
              )
              .toList();
          if (choices.length != 1) throw StateError('Ambiguous Luna route');
          final applied = await controller.setIntelligence(
            chat,
            ChatIntelligenceSelection(
              choice: choices.single,
              reasoningEffort: 'low',
            ),
            confirmModelChange: (_) async => true,
          );
          if (!applied) throw StateError('Luna was not selected');
          final title =
              'Wing streaming stress QA ${DateTime.now().millisecondsSinceEpoch}';
          await controller.current!.gateway.call('session.title', {
            'session_id': chat.runtimeId,
            'title': title,
          });
          chat.title = title;
          return developer.ServiceExtensionResponse.result(
            jsonEncode({
              'slot': owned.length - 1,
              'ownedTitle': title,
              'ownedSessionId': chat.key.sessionId,
              ...snapshot(item),
            }),
          );
        }
        final item = selected(parameters);
        if (action == 'open') await item.controller.openSession(item.chat.key);
        if (action == 'stage' || action == 'submit') {
          final prompt = _prompts[parameters['mode']];
          if (prompt == null ||
              item.chat.busy ||
              item.dispatching ||
              item.controller.current?.chat != item.chat ||
              item.chat.composerText.isNotEmpty ||
              item.chat.attachments.isNotEmpty ||
              item.chat.queuedPrompts.isNotEmpty ||
              !RegExp(r'^gpt-\d+\.\d+-luna$').hasMatch(item.chat.model ?? '')) {
            throw StateError('Owned Luna chat must be selected and empty');
          }
          await item.controller.updateDraft(item.chat, prompt);
          item.mode = parameters['mode'];
          item.responseBaseCount = item.chat.messages.length;
          item.preservedDraft = null;
          if (action == 'submit') {
            item.dispatching = true;
            item.dispatchFailed = false;
            item.submissions++;
            // One dispatch only. Never retry an uncertain acknowledgement.
            unawaited(
              item.controller
                  .send(item.chat)
                  .catchError((Object _) {
                    item.dispatchFailed = true;
                    return null;
                  })
                  .whenComplete(() => item.dispatching = false),
            );
          }
        }
        if (action == 'cancel') await item.controller.stop(item.chat);
        if (action == 'markDraft') item.preservedDraft = item.chat.composerText;
        if (action == 'start') {
          measurement?.timer.cancel();
          measurement = _Measurement(item);
        }
        if (action == 'stop') {
          final captured = measurement;
          if (captured == null || captured.owned != item) {
            throw StateError('No matching capture');
          }
          captured.timer.cancel();
          captured.sample();
          final report = {...snapshot(item), ...captured.report()};
          measurement = null;
          return developer.ServiceExtensionResponse.result(jsonEncode(report));
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode(snapshot(item)),
        );
      } catch (_) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'Live QA operation rejected; verify the owned slot and app readiness.',
        );
      } finally {
        if (mutation) mutating = false;
      }
    });
  }
  app.main();
}
