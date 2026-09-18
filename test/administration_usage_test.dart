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
    rows = [_sol(), _astra()];
    offline = false;
    browser = _Browser();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = browser;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    fixture.override = (method, path, query, body) async {
      if (offline) throw StateError('Offline');
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
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        220,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('subscription totals, breakdown and source use bundled rates', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('API-equivalent cost'), findsOneWidget);
    expect(find.text('USD 5.44'), findsOneWidget);
    expect(find.text('12 calls · USD 5.00'), findsOneWidget);
    expect(find.text('3 calls · USD 0.44'), findsOneWidget);
    await snapshot(tester, 'subscription-summary');
    expect(
      tester.getTopLeft(find.text('gpt-6-astra')).dy,
      lessThan(tester.getTopLeft(find.text('gpt-5.6-sol')).dy),
    );
    final bars = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bars.first.value, closeTo(5 / 5.44, 0.000001));
    await tester.tap(find.text('gpt-6-astra'));
    await tester.pumpAndSettle();
    expect(find.text('Uncached input'), findsOneWidget);
    expect(find.text('Cached input'), findsOneWidget);
    expect(find.text('USD 2.50'), findsOneWidget);
    expect(find.text('USD 1.00'), findsOneWidget);
    expect(find.text('USD 1.50'), findsOneWidget);
    expect(find.textContaining('1,000,000 tokens'), findsOneWidget);
    await reveal(tester, find.text('OpenAI pricing source'));
    await tester.tap(find.text('OpenAI pricing source'));
    await tester.pumpAndSettle();
    expect(
      browser.urls.single,
      'https://developers.openai.com/api/docs/models/gpt-6-astra',
    );
    expect(
      fixture.requests.every(
        (r) =>
            r.$1 == 'GET' &&
            r.$2 == 'analytics/models' &&
            r.$3['profile'] == 'personal',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed subtotal and sorting use displayed costs', (tester) async {
    rows = [_sol(), _paid(), _astra()];
    await show(tester);
    expect(find.text('Estimated usage value'), findsOneWidget);
    expect(find.text('USD 8.44'), findsOneWidget);
    expect(find.text('Hermes estimates'), findsOneWidget);
    expect(find.text('Subscription API equivalent'), findsOneWidget);
    expect(find.text('USD 5.44'), findsOneWidget);
    expect(find.text('USD 3.00'), findsOneWidget);
    await reveal(tester, find.text('Sort models'));
    await tester.tap(find.text('Estimated cost').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model name').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Paid API model')).dy,
      lessThan(tester.getTopLeft(find.text('gpt-5.6-sol')).dy),
    );
    await reveal(tester, find.text('Last 7 days'));
    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 days').last);
    await tester.pumpAndSettle();
    expect(fixture.requests.last.$3['days'], '30');
    expect(find.text('USD 8.44'), findsOneWidget);
  });

  testWidgets('unknown prices and invalid counters are partial, never zero', (
    tester,
  ) async {
    rows = [
      _astra(),
      _sol()..['model'] = 'gpt-5.3-codex-spark',
      _sol()..remove('cache_read_tokens'),
    ];
    await show(tester);
    expect(find.text('USD 5.00'), findsOneWidget);
    expect(find.textContaining('Partial total'), findsOneWidget);
    expect(find.textContaining('1 of 3 models'), findsOneWidget);
    expect(find.text('3 calls · Price unavailable'), findsOneWidget);
    expect(find.text('3 calls · Token counts unavailable'), findsOneWidget);
    await snapshot(tester, 'partial-summary');
    expect(find.textContaining('USD 0.00'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('all unknown costs and empty history remain distinct', (
    tester,
  ) async {
    rows = [_sol()..['model'] = 'unpriced'];
    await show(tester);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.textContaining('0 of 1 models'), findsOneWidget);
    rows = [];
    await reveal(tester, find.text('Refresh'));
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(
      find.text('No recorded model usage in this period.'),
      findsOneWidget,
    );
    expect(find.text('API-equivalent cost'), findsNothing);
    expect(find.textContaining('USD 0.00'), findsNothing);
  });

  testWidgets('sub-cent subscription value is not displayed as free', (
    tester,
  ) async {
    rows = [
      _sol()..addAll({
        'input_tokens': 1,
        'cache_read_tokens': 0,
        'output_tokens': 0,
      }),
    ];
    await show(tester);
    expect(find.text('< USD 0.01'), findsOneWidget);
    expect(find.text('3 calls · < USD 0.01'), findsOneWidget);
    expect(find.textContaining('USD 0.00'), findsNothing);
  });

  testWidgets(
    'duplicate model rows contribute independently and expand independently',
    (tester) async {
      rows = [_astra(), _astra()];
      await show(tester);
      expect(find.text('USD 10.00'), findsOneWidget);
      await tester.tap(find.text('gpt-6-astra').first);
      await tester.pumpAndSettle();
      expect(find.text('Uncached input'), findsOneWidget);
      await reveal(tester, find.text('Sort models'));
      await tester.tap(find.text('Estimated cost').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Calls'));
      await tester.pumpAndSettle();
      expect(find.text('Uncached input'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed refresh retains estimate and retry recovers', (
    tester,
  ) async {
    await show(tester);
    offline = true;
    await reveal(tester, find.text('Refresh'));
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('USD 5.44'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await snapshot(tester, 'refresh-error');
    offline = false;
    rows = [_astra()];
    await tester.tap(find.text('Retry'));
    await tester.runAsync(
      () => rootBundle.loadString('assets/pricing/openai.json'),
    );
    await tester.pumpAndSettle();
    expect(find.text('USD 5.00'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('loading and initial error can recover', (tester) async {
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
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('API-equivalent cost'), findsNothing);
    fixture.override = (_, _, _, _) async => {
      'models': [_astra()],
    };
    await tester.tap(find.text('Retry'));
    await tester.runAsync(
      () => rootBundle.loadString('assets/pricing/openai.json'),
    );
    await tester.pumpAndSettle();
    expect(find.text('USD 5.00'), findsOneWidget);
  });

  testWidgets('failed browser launch leaves a copyable source link', (
    tester,
  ) async {
    rows = [_astra()];
    browser.opens = false;
    await show(tester);
    await tester.tap(find.text('gpt-6-astra'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('OpenAI pricing source'));
    await tester.tap(find.text('OpenAI pricing source'));
    await tester.pumpAndSettle();
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
        rows = [_astra(), _sol(), _paid()];
        await show(tester, brightness: brightness, scale: scale);
        await snapshot(tester, '${brightness.name}-$scale-summary');
        await reveal(tester, find.text('gpt-6-astra'));
        await tester.tap(find.text('gpt-6-astra'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Uncached input'));
        await snapshot(tester, '${brightness.name}-$scale-breakdown');
        await reveal(tester, find.text('OpenAI pricing source'));
        await snapshot(tester, '${brightness.name}-$scale-source');
        await reveal(tester, find.text('Refresh'));
        expect(find.text('Refresh').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
