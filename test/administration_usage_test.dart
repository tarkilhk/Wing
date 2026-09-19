import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/analytics_content.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/screens/administration/usage_charts.dart';
import 'support/administration_fixture.dart';

Map<String, dynamic> _astra() => {
  'model': 'gpt-6-astra',
  'provider': 'openai-codex',
  'input_tokens': 250000,
  'cache_read_tokens': 1000000,
  'output_tokens': 30000,
  'reasoning_tokens': 20000,
  'estimated_cost': 0,
  'sessions': 2,
  'api_calls': 12,
};
Map<String, dynamic> _sol() => {
  'model': 'gpt-5.6-sol',
  'provider': 'openai-codex',
  'input_tokens': 50000,
  'cache_read_tokens': 100000,
  'output_tokens': 10000,
  'estimated_cost': 0,
  'sessions': 1,
  'api_calls': 3,
};
Map<String, dynamic> _paid() => {
  'model': 'Paid API model',
  'provider': 'openai',
  'input_tokens': 100000,
  'output_tokens': 20000,
  'estimated_cost': 3,
  'sessions': 1,
  'api_calls': 4,
};

Map<String, dynamic> dailyData() {
  final today = DateTime.now().toUtc();
  return {
    'daily': [
      for (var i = 0; i < 6; i++)
        {
          'day': today
              .subtract(Duration(days: i))
              .toIso8601String()
              .substring(0, 10),
          'input_tokens': 12000 + i * 1000,
          'cache_read_tokens': 35000 + i * i * 4000,
          'output_tokens': 4000 + i * 2000,
        },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('CAPTURE_USAGE');
  setUpAll(() async {
    // Exercise the production bundled asset, including pubspec registration.
    await rootBundle.loadString('assets/pricing/openai.json');
    if (!capture) return;
    const root = String.fromEnvironment('CAPTURE_FONT_DIR');
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              '$root/${font.value}',
            ).readAsBytes().then((b) => b.buffer.asByteData()),
          ))
          .load();
    }
  });

  late AdministrationFixture fixture;
  late List<Map<String, dynamic>> rows;
  bool offline = false;
  setUp(() {
    fixture = AdministrationFixture('Claw');
    addTearDown(fixture.server.close);
    rows = [_sol(), _astra()];
    offline = false;
    fixture.override = (method, path, query, body) async {
      if (offline) throw StateError('Offline');
      if (path == 'analytics/usage') return dailyData();
      return {'models': rows, 'period_days': int.parse(query['days']!)};
    };
  });

  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wingTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const ValueKey('usage-capture'),
            child: child!,
          ),
        ),
        home: AnalyticsPage(profile: fixture.server.profile('personal')),
      ),
    );
    await tester.runAsync(
      () => rootBundle.loadString('assets/pricing/openai.json'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> snapshot(WidgetTester tester, String name) async {
    if (!capture) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('usage-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/usage-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        )
        .last;
    if (target.evaluate().isEmpty) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          target,
          180,
          scrollable: scrollable,
          maxScrolls: 80,
        );
      }
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('period totals, title switches and day selection stay local', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('API-equivalent cost'), findsOneWidget);
    expect(find.text('USD 5.44'), findsOneWidget);
    expect(find.text('1.4M'), findsOneWidget);
    expect(find.text('Breakdown per model'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
    await reveal(tester, find.byType(UsageAreaChart));
    expect(find.text('Trend per token type'), findsOneWidget);
    expect(find.byType(UsageAreaChart), findsOneWidget);
    expect(fixture.requests.length, 3);
    expect(find.text('Cached input'), findsWidgets);
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    await tap(tester, find.byKey(ValueKey('usage-day-$today')));
    expect(find.text('12.0K'), findsOneWidget);
    expect(find.text('35.0K'), findsOneWidget);
    expect(
      find.textContaining('51,000 tokens', findRichText: true),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
    expect(
      find.text('Hermes does not provide a model breakdown by day.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('51,000 tokens', findRichText: true),
      findsNothing,
    );
    await tap(tester, find.text('Show daily tokens'));
    expect(find.text('12.0K'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('usage-trend-group')));
    await tap(tester, find.text('Show token trend'));
    await reveal(tester, find.byType(UsageAreaChart));
    expect(find.byType(UsageAreaChart), findsOneWidget);
    expect(fixture.requests.length, 3);
    await tap(tester, find.text('Selected period'));
    expect(find.text('300K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('period chips cap at 365 and cache previously loaded periods', (
    tester,
  ) async {
    await show(tester);
    for (final label in ['1D', '7D', '30D', '90D', '365D']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('ALL'), findsNothing);
    await tap(tester, find.text('365D'));
    expect(fixture.requests.length, 4);
    expect(fixture.requests.last.$3['days'], '365');
    await tap(tester, find.text('7D'));
    expect(fixture.requests.length, 4);
    await tap(tester, find.text('365D'));
    await tester.drag(
      find.byKey(const ValueKey('usage-year-band')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('usage-year-band')), findsOneWidget);
    expect(fixture.requests.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cost and token controls are independent and model rows are passive',
    (tester) async {
      await show(tester);
      await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
      await tap(tester, find.text('Cost').first);
      expect(find.text('Breakdown per token type'), findsOneWidget);
      expect(find.text('USD 2.70'), findsOneWidget);
      expect(find.text('USD 1.04'), findsOneWidget);
      expect(find.text('USD 1.70'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
      await tap(tester, find.text('gpt-6-astra'));
      expect(find.text('Model details'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        fixture.requests.every(
          (r) => r.$1 == 'GET' && r.$3['profile'] == 'personal',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mixed providers never infer token-type costs', (tester) async {
    rows = [_astra(), _paid()];
    await show(tester);
    expect(find.text('Estimated usage value'), findsOneWidget);
    expect(find.text('USD 8.00'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
    await tap(tester, find.text('Cost').first);
    expect(
      find.textContaining('Cost per token type is available only'),
      findsOneWidget,
    );
    expect(find.byType(UsageComposition), findsNothing);
  });

  testWidgets('unknown prices and counters stay partial, never free', (
    tester,
  ) async {
    rows = [
      _astra(),
      _sol()..['model'] = 'unpriced',
      _sol()..remove('cache_read_tokens'),
    ];
    await show(tester);
    expect(find.text('USD 5.00'), findsOneWidget);
    expect(find.text('Partial total'), findsOneWidget);
    await tap(tester, find.text('Cost').first);
    expect(find.textContaining('Partial breakdown'), findsOneWidget);
    expect(find.textContaining('USD 0.00'), findsNothing);
    expect(find.textContaining('Unavailable'), findsWidgets);
  });

  testWidgets('sub-cent estimates and duplicate contributions are preserved', (
    tester,
  ) async {
    rows = [_astra(), _astra()];
    await show(tester);
    expect(find.text('USD 10.00'), findsOneWidget);
    expect(find.text('gpt-6-astra'), findsOneWidget);
    await tap(tester, find.text('gpt-6-astra'));
    expect(find.text('Model details'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    rows = [
      _sol()..addAll({
        'input_tokens': 1,
        'cache_read_tokens': 0,
        'output_tokens': 0,
      }),
    ];
    await tap(tester, find.text('Refresh'));
    await reveal(tester, find.text('< USD 0.01'));
    expect(find.textContaining('USD 0.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed refresh retains data and independent retry recovers', (
    tester,
  ) async {
    await show(tester);
    offline = true;
    await tap(tester, find.text('Refresh'));
    await reveal(tester, find.text('USD 5.44'));
    await reveal(tester, find.textContaining('Showing retained data'));
    expect(find.textContaining('Showing retained data'), findsOneWidget);
    await snapshot(tester, 'refresh-error');
    offline = false;
    rows = [_astra()];
    await tap(tester, find.text('Refresh'));
    await reveal(tester, find.text('USD 5.00'));
    expect(find.textContaining('Could not load'), findsNothing);
  });

  testWidgets('initial failure is distinct from empty history and retries', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    fixture.override = (_, _, _, _) => pending.future;
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyticsPage(profile: fixture.server.profile('personal')),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load'), findsWidgets);
    expect(find.text('No recorded model usage in this period.'), findsNothing);
    fixture.override = (_, path, _, _) async =>
        path == 'analytics/models' ? {'models': []} : {'daily': []};
    await tap(tester, find.text('Refresh'));
    await reveal(tester, find.text('No recorded model usage in this period.'));
    expect(find.textContaining('Could not load'), findsNothing);
  });

  testWidgets('late period responses cannot replace the selected range', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    fixture.override = (_, path, query, _) async {
      if (path == 'analytics/usage') return dailyData();
      if (query['days'] == '30') return pending.future;
      return {
        'models': [_paid()..['estimated_cost'] = 7],
      };
    };
    await show(tester);
    await tester.tap(find.text('30D'));
    await tester.pump();
    expect(find.text('Loading usage…'), findsOneWidget);
    await tester.tap(find.text('7D'));
    await tester.pumpAndSettle();
    pending.complete({
      'models': [_paid()..['estimated_cost'] = 30],
    });
    await tester.pumpAndSettle();
    expect(find.text('USD 7.00'), findsOneWidget);
    expect(find.text('USD 30.00'), findsNothing);
    await tap(tester, find.text('30D'));
    expect(find.text('USD 30.00'), findsOneWidget);
    expect(fixture.requests.length, 5);
  });

  testWidgets(
    'older day selects year counts without changing period or refetching',
    (tester) async {
      final date = DateTime.now().toUtc().subtract(const Duration(days: 100));
      final id = date.toIso8601String().substring(0, 10);
      fixture.override = (_, path, query, _) async {
        if (path == 'analytics/models') {
          return {
            'models': [_astra()],
          };
        }
        return {
          'daily': [
            if (query['days'] == '365')
              {
                'day': id,
                'input_tokens': 123,
                'cache_read_tokens': 456,
                'output_tokens': 789,
              },
          ],
        };
      };
      await show(tester);
      await tap(tester, find.byKey(ValueKey('usage-day-$id')));
      await tap(tester, find.text('Show daily tokens'));
      await reveal(tester, find.text('123'));
      expect(find.text('456'), findsOneWidget);
      expect(find.text('789'), findsOneWidget);
      expect(find.text('Selected period'), findsOneWidget);
      expect(fixture.requests.length, 3);
      await tap(tester, find.text('Selected period'));
      expect(find.text('Last 7 days · all models'), findsOneWidget);
    },
  );

  testWidgets('one passive row per model combines provider tokens and costs', (
    tester,
  ) async {
    rows = [
      _astra(),
      _astra()..addAll({'provider': 'openai', 'estimated_cost': 7}),
    ];
    await show(tester);
    await reveal(tester, find.text('gpt-6-astra'));
    expect(find.text('gpt-6-astra'), findsOneWidget);
    final tokenSegments = tester
        .widget<UsageComposition>(find.byType(UsageComposition))
        .segments;
    expect(tokenSegments.single.value, 2560000);
    final color = tokenSegments.single.color;
    await tap(tester, find.text('Cost').first);
    final costSegments = tester
        .widget<UsageComposition>(find.byType(UsageComposition))
        .segments;
    expect(costSegments.single.value, 12);
    expect(costSegments.single.color, color);
    await tap(tester, find.text('gpt-6-astra'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Model details'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('usage renders ${brightness.name} at $scale text', (
        tester,
      ) async {
        await show(tester, brightness: brightness, scale: scale);
        await snapshot(tester, '${brightness.name}-$scale-summary');
        await reveal(tester, find.byType(UsageAreaChart));
        await snapshot(tester, '${brightness.name}-$scale-trend');
        await tap(tester, find.text('90D'));
        await snapshot(tester, '${brightness.name}-$scale-calendar');
        final band = find.byKey(const ValueKey('usage-year-band'));
        await reveal(tester, find.byKey(const ValueKey('usage-activity-grid')));
        await tester.drag(band, const Offset(140, 0));
        await tester.pumpAndSettle();
        await snapshot(tester, '${brightness.name}-$scale-scrolled');
        await tester.drag(band, const Offset(-300, 0));
        await tester.pumpAndSettle();
        await tap(tester, find.text('365D'));
        await reveal(tester, find.byKey(const ValueKey('usage-activity-grid')));
        await snapshot(tester, '${brightness.name}-$scale-year');
        final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
        await tap(tester, find.byKey(ValueKey('usage-day-$today')));
        await snapshot(tester, '${brightness.name}-$scale-day-tooltip');
        await tap(tester, find.text('Selected period'));
        await tap(tester, find.text('gpt-6-astra'));
        await reveal(tester, find.text('gpt-6-astra'));
        await snapshot(tester, '${brightness.name}-$scale-breakdown');
        await reveal(tester, find.text('Refresh'));
        expect(find.text('Refresh').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
