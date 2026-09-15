import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/widgets/profile_editor_sheet.dart';

class _ProfileEditorFixture {
  String description = 'Work profile';
  String soul = 'Be precise.';
  bool failConfigure = false;
  bool partial = false;
  bool rejectDescriptionAndChangeSoul = false;
  Completer<void>? discoveryDelay;
  int discoveryCalls = 0;
  final calls = <(String, Map<String, dynamic>)>[];

  late final ProfileGateway gateway = ProfileGateway(
    scope: WorkspaceScope(
      connectionId: 'central',
      connectionIdentity: 'editor-test',
      profileName: 'work',
    ),
    get: (_, _) async => {},
    discover: () async {
      discoveryCalls++;
      await discoveryDelay?.future;
      return const ProfileDiscovery(
        profiles: [HermesProfile(name: 'work')],
        currentName: 'work',
        activeName: 'work',
      );
    },
    rpc: (method, params) async {
      calls.add((method, params));
      if (method == 'profiles.describe') {
        return {
          'name': 'work',
          'description': description,
          'soul': soul,
          'skills': const [],
          'toolsets': const [],
        };
      }
      if (method == 'profiles.configure') {
        if (failConfigure) {
          throw StateError('private server failure');
        }
        if (rejectDescriptionAndChangeSoul) {
          soul = 'Central update';
          return {
            'ok': false,
            'applied': {'description': false},
          };
        }
        if (partial) {
          if (params['description'] case final String value) {
            description = value.trim();
          }
          return {
            'ok': false,
            'applied': {'description': true, 'soul': false},
          };
        }
        if (params['description'] case final String value) {
          description = value.trim();
        }
        if (params['soul'] case final String value) {
          soul = value;
        }
        return {
          'ok': true,
          'applied': {
            if (params.containsKey('description')) 'description': true,
            if (params.containsKey('soul')) 'soul': true,
          },
        };
      }
      return {};
    },
  );
}

void main() {
  late _ProfileEditorFixture fixture;
  bool? result;

  setUp(() {
    fixture = _ProfileEditorFixture();
    result = null;
  });

  Future<void> openEditor(
    WidgetTester tester, {
    Size size = const Size(800, 900),
    double textScale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showProfileEditorSheet(
                  context,
                  gateway: fixture.gateway,
                  connectionLabel: 'Central server',
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(ValueKey(key));

  Future<void> tapSave(WidgetTester tester, {bool settle = true}) async {
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('loads captured scope and writes only the dirty field', (
    tester,
  ) async {
    await openEditor(tester);
    expect(find.text('Central server · work'), findsOneWidget);
    expect(
      find.text(
        'Changes are stored on the central Hermes server for this profile.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(field('profile-description-field'))
          .controller!
          .text,
      'Work profile',
    );

    await tester.enterText(
      field('profile-description-field'),
      '  Mobile work  ',
    );
    await tapSave(tester);

    final write = fixture.calls.singleWhere(
      (call) => call.$1 == 'profiles.configure',
    );
    expect(write.$2, {
      'name': 'work',
      'description': '  Mobile work  ',
      'profile': 'work',
    });
    expect(fixture.discoveryCalls, 1);
    expect(fixture.description, 'Mobile work');
    expect(result, isTrue);
  });

  testWidgets('reports partial ACK and preserves the unapplied SOUL edit', (
    tester,
  ) async {
    fixture.partial = true;
    await openEditor(tester);
    await tester.enterText(field('profile-description-field'), '  Updated  ');
    await tester.enterText(field('profile-soul-field'), 'Keep this exact.\n');
    await tapSave(tester);

    expect(find.text('Saved: description.'), findsOneWidget);
    expect(
      find.text('Not applied: SOUL. Review the fields before trying again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(field('profile-description-field'))
          .controller!
          .text,
      'Updated',
    );
    expect(
      tester.widget<TextField>(field('profile-soul-field')).controller!.text,
      'Keep this exact.\n',
    );
    expect(
      fixture.calls.where((call) => call.$1 == 'profiles.configure'),
      hasLength(1),
    );
    await tester.tap(find.byTooltip('Close profile editor'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('keeps intentional empty edits after an uncertain save', (
    tester,
  ) async {
    fixture.failConfigure = true;
    await openEditor(tester);
    await tester.enterText(field('profile-description-field'), '');
    await tester.enterText(field('profile-soul-field'), '');
    await tapSave(tester);

    expect(
      find.text(
        'The save could not be confirmed. Your edits are still here; review them before trying again.',
      ),
      findsOneWidget,
    );
    expect(field('profile-description-field'), findsOneWidget);
    expect(field('profile-soul-field'), findsOneWidget);
    expect(
      fixture.calls.where((call) => call.$1 == 'profiles.configure'),
      hasLength(1),
    );
    expect(result, isNull);
  });

  testWidgets('refreshes untouched fields without adding them to a retry', (
    tester,
  ) async {
    fixture.rejectDescriptionAndChangeSoul = true;
    await openEditor(tester);
    await tester.enterText(field('profile-description-field'), 'Keep pending');
    await tapSave(tester);

    expect(
      tester
          .widget<TextField>(field('profile-description-field'))
          .controller!
          .text,
      'Keep pending',
    );
    expect(
      tester.widget<TextField>(field('profile-soul-field')).controller!.text,
      'Central update',
    );
    await tapSave(tester);
    final writes = fixture.calls
        .where((call) => call.$1 == 'profiles.configure')
        .toList();
    expect(writes, hasLength(2));
    expect(writes.last.$2.containsKey('soul'), isFalse);
  });

  testWidgets('keeps fields and Save reachable on a narrow keyboard layout', (
    tester,
  ) async {
    await openEditor(
      tester,
      size: const Size(320, 700),
      textScale: 1.6,
      keyboard: 260,
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(field('profile-soul-field'), 'Phone edit');
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocks route and barrier dismissal while saving', (
    tester,
  ) async {
    final pending = Completer<void>();
    fixture.discoveryDelay = pending;
    await openEditor(tester);
    await tester.enterText(field('profile-description-field'), 'Captured edit');
    await tapSave(tester, settle: false);

    await tester.tapAt(const Offset(4, 4));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Edit profile'), findsOneWidget);
    final close = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Close profile editor'),
        matching: find.byType(IconButton),
      ),
    );
    expect(close.onPressed, isNull);

    pending.complete();
    await tester.pumpAndSettle();
    expect(
      fixture.calls.where((call) => call.$1 == 'profiles.configure'),
      hasLength(1),
    );
    expect(result, isTrue);
  });

  testWidgets('keeps the captured gateway when the parent owner changes', (
    tester,
  ) async {
    final pending = Completer<void>();
    fixture.discoveryDelay = pending;
    final other = _ProfileEditorFixture();
    const editorKey = ValueKey('captured-profile-editor');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileEditorSheet(
            key: editorKey,
            gateway: fixture.gateway,
            connectionLabel: 'First server',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('profile-description-field'), 'First edit');
    await tapSave(tester, settle: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileEditorSheet(
            key: editorKey,
            gateway: other.gateway,
            connectionLabel: 'Other server',
          ),
        ),
      ),
    );
    pending.complete();
    await tester.pumpAndSettle();

    expect(
      fixture.calls.where((call) => call.$1 == 'profiles.configure'),
      hasLength(1),
    );
    expect(
      other.calls.where((call) => call.$1 == 'profiles.configure'),
      isEmpty,
    );
  });
}
