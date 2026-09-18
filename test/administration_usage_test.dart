import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:wing/core/screens/administration/admin_health_page.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/screens/administration/usage_charts.dart';
import 'support/administration_fixture.dart';

class _Browser extends UrlLauncherPlatform {
  final urls = <String>[];
  bool opens = true;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return opens;
  }
}

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
  late _Browser browser;
  bool offline = false;
  setUp(() {
    fixture = AdministrationFixture('Claw');
    addTearDown(fixture.server.close);
    rows = [_sol(), _astra()];
    offline = false;
    browser = _Browser();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = browser;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
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
        home: AdminUsagePage(profile: fixture.server.profile('personal')),
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
          matching: find.byType(Scrollable),
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
    expect(fixture.requests.length, 2);
    await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
    expect(find.text('Breakdown per token type'), findsOneWidget);
    expect(find.text('Cached input'), findsOneWidget);
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    await tap(tester, find.byKey(ValueKey('usage-day-$today')));
    expect(find.text('12.0K'), findsOneWidget);
    expect(find.text('35.0K'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
    expect(
      find.text('Hermes does not provide a model breakdown by day.'),
      findsOneWidget,
    );
    await tap(tester, find.text('Show daily tokens'));
    expect(find.text('12.0K'), findsOneWidget);
    await tap(tester, find.text('Show token trend'));
    expect(find.byType(UsageAreaChart), findsOneWidget);
    expect(fixture.requests.length, 2);
    await tap(tester, find.text('All days'));
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
    await tap(tester, find.byTooltip('Earlier dates'));
    expect(fixture.requests.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cost and token controls are independent and sources remain accessible',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('Cost').first);
      expect(find.text('USD 5.00'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
      expect(find.text('USD 2.70'), findsOneWidget);
      expect(find.text('USD 1.04'), findsOneWidget);
      expect(find.text('USD 1.70'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('usage-breakdown-group')));
      await tap(tester, find.text('gpt-6-astra'));
      await tap(tester, find.text('OpenAI pricing source'));
      expect(
        browser.urls.single,
        'https://developers.openai.com/api/docs/models/gpt-6-astra',
      );
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
    expect(find.textContaining('2 recorded contributions'), findsOneWidget);
    await tap(tester, find.byTooltip('Close details'));
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
        home: AdminUsagePage(profile: fixture.server.profile('personal')),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load'), findsOneWidget);
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
    expect(fixture.requests.length, 4);
  });

  testWidgets('failed browser launch leaves a copyable source', (tester) async {
    browser.opens = false;
    await show(tester);
    await tap(tester, find.text('gpt-6-astra'));
    await tap(tester, find.text('OpenAI pricing source'));
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      find.text('Could not open the browser. Copy this pricing link:'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('usage renders ${brightness.name} at $scale text', (
        tester,
      ) async {
        await show(tester, brightness: brightness, scale: scale);
        await snapshot(tester, '${brightness.name}-$scale-summary');
        await tap(tester, find.text('Show token trend'));
        await snapshot(tester, '${brightness.name}-$scale-trend');
        await tap(tester, find.text('90D'));
        await snapshot(tester, '${brightness.name}-$scale-calendar');
        await tap(tester, find.text('365D'));
        await reveal(tester, find.byKey(const ValueKey('usage-activity-grid')));
        await snapshot(tester, '${brightness.name}-$scale-year');
        await tap(tester, find.text('gpt-6-astra'));
        await reveal(tester, find.text('Uncached input').last);
        await snapshot(tester, '${brightness.name}-$scale-breakdown');
        await reveal(tester, find.text('OpenAI pricing source'));
        await snapshot(tester, '${brightness.name}-$scale-source');
        await tap(tester, find.byTooltip('Close details'));
        await reveal(tester, find.text('Refresh'));
        expect(find.text('Refresh').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
