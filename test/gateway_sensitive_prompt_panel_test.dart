import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_sensitive_prompt.dart';
import 'package:hermes_android/core/widgets/gateway_sensitive_prompt_panel.dart';

void main() {
  const sudo = GatewaySensitivePromptRequest(
    kind: GatewaySensitivePromptKind.sudo,
    requestId: 'sudo-1',
    title: 'Administrator password needed',
    description: 'Hermes needs a sudo password.',
    fieldLabel: 'Sudo password',
  );

  Widget app(
    GatewaySensitivePromptRequest request,
    SensitivePromptResponder respond,
  ) => MaterialApp(
    home: Scaffold(
      body: GatewaySensitivePromptPanel(request: request, onRespond: respond),
    ),
  );

  testWidgets('masks the value and disables duplicate responses', (
    tester,
  ) async {
    final pending = Completer<void>();
    final values = <String>[];
    await tester.pumpWidget(
      app(sudo, (value) {
        values.add(value);
        return pending.future;
      }),
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('sensitive-prompt-field')),
    );
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);

    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-field')),
      'synthetic-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sensitive-prompt-submit')));
    await tester.pump();

    expect(values, ['synthetic-password']);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('sensitive-prompt-submit')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('sensitive-prompt-cancel')))
          .onPressed,
      isNull,
    );

    pending.complete();
  });

  testWidgets('cancel sends the explicit empty response', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(app(sudo, (value) async => values.add(value)));

    await tester.tap(find.byKey(const Key('sensitive-prompt-cancel')));
    await tester.pump();

    expect(values, ['']);
  });

  testWidgets('shows a generic error without rendering the exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(sudo, (_) => Future<void>.error('server echoed a credential')),
    );
    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-field')),
      'fixture-secret',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sensitive-prompt-submit')));
    await tester.pump();

    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('sensitive-prompt-error')),
              matching: find.byType(Text),
            ),
          )
          .data,
      'Hermes could not accept the response. Please try again.',
    );
    expect(find.textContaining('server echoed'), findsNothing);
  });

  testWidgets('a newer request clears the prior value and remains usable', (
    tester,
  ) async {
    await tester.pumpWidget(app(sudo, (_) async {}));
    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-field')),
      'old-value',
    );
    const secret = GatewaySensitivePromptRequest(
      kind: GatewaySensitivePromptKind.secret,
      requestId: 'secret-2',
      title: 'FIXTURE_TOKEN',
      description: 'Enter a token.',
      fieldLabel: 'FIXTURE_TOKEN',
    );

    await tester.pumpWidget(app(secret, (_) async {}));

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sensitive-prompt-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sensitive-prompt-field')))
          .enabled,
      isTrue,
    );
  });

  testWidgets('the same recovered request preserves the typed value', (
    tester,
  ) async {
    await tester.pumpWidget(app(sudo, (_) async {}));
    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-field')),
      'still-typing',
    );
    const refreshed = GatewaySensitivePromptRequest(
      kind: GatewaySensitivePromptKind.sudo,
      requestId: 'sudo-1',
      title: 'Administrator password still needed',
      description: 'The same request remains pending.',
      fieldLabel: 'Sudo password',
    );

    await tester.pumpWidget(app(refreshed, (_) async {}));

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sensitive-prompt-field')))
          .controller!
          .text,
      'still-typing',
    );
  });

  testWidgets('save login submits a trimmed identifier and masked password', (
    tester,
  ) async {
    const request = GatewaySensitivePromptRequest(
      kind: GatewaySensitivePromptKind.vaultSaveLogin,
      requestId: 'save-1',
      title: 'Save login for Example',
      description: 'Save a login for Example.',
      fieldLabel: 'Identifier',
    );
    final responses = <String>[];
    await tester.pumpWidget(
      app(request, (value) async => responses.add(value)),
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sensitive-prompt-field')))
          .obscureText,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sensitive-prompt-password')))
          .obscureText,
      isTrue,
    );
    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-field')),
      '  person@example.test  ',
    );
    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-password')),
      'synthetic-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sensitive-prompt-submit')));
    await tester.pump();

    expect(jsonDecode(responses.single), {
      'identifier': 'person@example.test',
      'password': 'synthetic-password',
    });
  });

  testWidgets('one-time code stays visible and removes spaces and hyphens', (
    tester,
  ) async {
    const request = GatewaySensitivePromptRequest(
      kind: GatewaySensitivePromptKind.vaultCode,
      requestId: 'code-1',
      title: 'Enter code for Example',
      description: 'Enter a one-time code.',
      fieldLabel: 'One-time code',
    );
    final responses = <String>[];
    await tester.pumpWidget(
      app(request, (value) async => responses.add(value)),
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sensitive-prompt-field')))
          .obscureText,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const Key('sensitive-prompt-field')),
      '123 456-78',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sensitive-prompt-submit')));
    await tester.pump();

    expect(responses, ['12345678']);
  });
}
