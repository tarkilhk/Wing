import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/connection.dart';
import 'package:wing/core/widgets/gateway_headers_editor.dart';

void main() {
  test('shared validator rejects managed, duplicate and unsafe headers', () {
    expect(
      validateGatewayHeaders({'CF-Access-Client-Id': 'value'}),
      isNotEmpty,
    );
    for (final headers in <Map<String, String>>[
      {'Host': 'value'},
      {'X-Test': 'one', 'x-test': 'two'},
      {'X-Test': 'bad\r\nvalue'},
      {'Bad Header': 'value'},
      {'X-Blank': '   '},
    ]) {
      expect(() => validateGatewayHeaders(headers), throwsFormatException);
    }
  });

  testWidgets('emits saved keep, replacement and removal', (tester) async {
    final values = <Map<String, String?>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GatewayHeadersEditor(
            savedNames: const {'CF-Access-Client-Id'},
            onChanged: values.add,
          ),
        ),
      ),
    );

    expect(find.text('Keep saved value'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'replacement');
    expect(values.last, {'CF-Access-Client-Id': 'replacement'});
    await tester.tap(find.byTooltip('Remove header'));
    expect(values.last, isEmpty);
  });

  testWidgets('rejects duplicates and a renamed saved header without a value', (
    tester,
  ) async {
    final values = <Map<String, String?>>[];
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: GatewayHeadersEditor(
              savedNames: const {'X-Saved'},
              onChanged: values.add,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'X-Renamed');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Value is required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.text('Add header'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(2), 'x-renamed');
    await tester.enterText(find.byType(TextFormField).at(3), 'another');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Header names must be unique.'), findsNWidgets(2));
    expect(values.last, {'X-Renamed': 'secret'});
  });

  testWidgets('disabled and owner changes preserve safe controller ownership', (
    tester,
  ) async {
    final values = <Map<String, String?>>[];
    Widget editor(Set<String> names, {required bool enabled}) => MaterialApp(
      home: Scaffold(
        body: GatewayHeadersEditor(
          savedNames: names,
          enabled: enabled,
          onChanged: values.add,
        ),
      ),
    );

    await tester.pumpWidget(editor(const {'X-Old'}, enabled: false));
    await tester.tap(find.byTooltip('Remove header'));
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(values, isEmpty);

    await tester.pumpWidget(editor(const {'X-New'}, enabled: true));
    await tester.pump();
    expect(find.text('X-New'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates a new value at 320px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final values = <Map<String, String?>>[];
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: GatewayHeadersEditor(
                savedNames: const {},
                onChanged: values.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add header'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, 'X-Test');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.enterText(find.byType(TextFormField).last, '   ');
    expect(formKey.currentState!.validate(), isFalse);
    expect(values, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
