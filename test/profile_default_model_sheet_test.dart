import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/widgets/profile_default_model_sheet.dart';

class _Fixture {
  String provider = 'openai-codex';
  String model = 'gpt-5.6-sol';
  bool confirmRequired = false;
  bool staleReadback = false;
  bool configured = true;
  Completer<void>? postDelay;
  int discoveryCalls = 0;
  final reads = <(String, Map<String, String>)>[];
  final posts = <(String, Map<String, dynamic>)>[];

  late final ProfileGateway gateway = ProfileGateway(
    scope: WorkspaceScope(
      connectionId: 'central',
      connectionIdentity: 'profile-model-test',
      profileName: 'work',
    ),
    get: (path, query) async {
      reads.add((path, query));
      if (path == 'model/info') {
        return configured ? {'provider': provider, 'model': model} : {};
      }
      if (path == 'model/options') {
        return {
          'providers': [
            {
              'slug': 'openai-codex',
              'name': 'OpenAI subscription',
              'models': ['gpt-5.6-sol', 'gpt-6-astra'],
            },
            {
              'slug': 'nous',
              'name': 'Nous',
              'models': [
                {'id': 'hermes-4'},
              ],
            },
          ],
        };
      }
      throw StateError('Unexpected read $path');
    },
    post: (path, body) async {
      posts.add((path, Map<String, dynamic>.from(body)));
      await postDelay?.future;
      if (confirmRequired && body['confirm_expensive_model'] != true) {
        return {
          'ok': false,
          'confirm_required': true,
          'confirm_message': 'This route may cost more.',
        };
      }
      if (!staleReadback) {
        provider = body['provider'] as String;
        model = body['model'] as String;
        configured = true;
      }
      return {'ok': true};
    },
    rpc: (_, _) async => {},
    discover: () async {
      discoveryCalls++;
      return const ProfileDiscovery(
        profiles: [HermesProfile(name: 'work')],
        currentName: 'work',
        activeName: 'work',
      );
    },
  );
}

void main() {
  late _Fixture fixture;
  bool? result;

  setUp(() {
    fixture = _Fixture();
    result = null;
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(800, 900),
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showProfileDefaultModelSheet(
                  context,
                  gateway: fixture.gateway,
                  connectionLabel: 'Central server',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> selectAstra(WidgetTester tester) async {
    final choice = find.byKey(
      const Key('profile-model-openai-codex-gpt-6-astra'),
    );
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('profile-model-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('loads explicit options and saves the captured profile scope', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('work on Central server'), findsOneWidget);
    expect(
      find.text(
        'Sets the server default for this profile and applies to new sessions only. Running chats keep their current model.',
      ),
      findsOneWidget,
    );
    expect(fixture.reads.singleWhere((read) => read.$1 == 'model/options').$2, {
      'explicit_only': '1',
      'profile': 'work',
    });

    await selectAstra(tester);
    await save(tester);

    expect(fixture.discoveryCalls, 1);
    expect(fixture.posts, hasLength(1));
    expect(fixture.posts.single.$1, 'model/set?profile=work');
    expect(fixture.posts.single.$2, {
      'scope': 'main',
      'provider': 'openai-codex',
      'model': 'gpt-6-astra',
    });
    expect(result, isTrue);
  });

  testWidgets('confirmation denial does not retry or report success', (
    tester,
  ) async {
    fixture.confirmRequired = true;
    await open(tester);
    await selectAstra(tester);
    await tester.tap(find.byKey(const Key('profile-model-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('This route may cost more.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-model-confirm-cancel')));
    await tester.pumpAndSettle();

    expect(fixture.posts, hasLength(1));
    expect(fixture.discoveryCalls, 1);
    expect(find.text('Model change cancelled.'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('confirmation acceptance revalidates and retries explicitly', (
    tester,
  ) async {
    fixture.confirmRequired = true;
    await open(tester);
    await selectAstra(tester);
    await tester.tap(find.byKey(const Key('profile-model-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('This route may cost more.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-model-confirm-accept')));
    await tester.pumpAndSettle();

    expect(fixture.discoveryCalls, 2);
    expect(fixture.posts, hasLength(2));
    expect(fixture.posts.last.$2['confirm_expensive_model'], isTrue);
    expect(result, isTrue);
  });

  testWidgets('successful ACK with mismatched readback stays open as failure', (
    tester,
  ) async {
    fixture.staleReadback = true;
    await open(tester);
    await selectAstra(tester);
    await save(tester);

    expect(
      find.text(
        'The model change could not be confirmed. Review the selection and try again.',
      ),
      findsOneWidget,
    );
    expect(result, isNull);
  });

  testWidgets('filters the model list by provider and model text', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(
      find.byKey(const Key('profile-model-search')),
      'nous',
    );
    await tester.pump();
    expect(find.text('Nous'), findsWidgets);
    expect(find.text('OpenAI subscription'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('profile-model-search')),
      'missing-model',
    );
    await tester.pump();
    expect(find.text('No matching models'), findsOneWidget);
  });

  testWidgets('system back is blocked while saving and success closes sheet', (
    tester,
  ) async {
    fixture.postDelay = Completer<void>();
    await open(tester);
    await selectAstra(tester);

    await tester.tap(find.byKey(const Key('profile-model-save')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Profile default model'), findsOneWidget);
    expect(result, isNull);

    fixture.postDelay!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Profile default model'), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('an unconfigured profile can select and save its first default', (
    tester,
  ) async {
    fixture.configured = false;
    await open(tester);

    await tester.tap(find.text('OpenAI subscription'));
    await tester.pumpAndSettle();
    await selectAstra(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('profile-model-save')))
          .onPressed,
      isNotNull,
    );
    await save(tester);

    expect(fixture.posts, hasLength(1));
    expect(fixture.posts.single.$2['model'], 'gpt-6-astra');
    expect(result, isTrue);
  });

  testWidgets('search and save actions fit above a small-screen keyboard', (
    tester,
  ) async {
    await open(tester, size: const Size(320, 640), keyboard: 240);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('profile-model-search')), findsOneWidget);
    expect(find.byKey(const Key('profile-model-save')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byKey(const Key('profile-model-save'))).dy,
      lessThanOrEqualTo(400),
    );
  });
}
