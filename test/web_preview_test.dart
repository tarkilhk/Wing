import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/web_preview.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Browser extends UrlLauncherPlatform {
  bool supported = true;
  bool previewFails = false;
  bool externalFails = false;
  final calls = <(String, LaunchOptions)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => supported;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url, options));
    if (options.mode == PreferredLaunchMode.inAppBrowserView && previewFails ||
        options.mode == PreferredLaunchMode.externalApplication &&
            externalFails) {
      throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    }
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UrlLauncherPlatform original;
  late _Browser browser;
  final uri = Uri.parse('https://example.com/report?q=a#section');

  setUp(() {
    original = UrlLauncherPlatform.instance;
    browser = _Browser();
    UrlLauncherPlatform.instance = browser;
  });
  tearDown(() => UrlLauncherPlatform.instance = original);

  test(
    'opens the exact web URL in a titled browser preview without headers',
    () async {
      expect(await openWebPreview(uri), isTrue);
      expect(browser.calls.single.$1, uri.toString());
      final options = browser.calls.single.$2;
      expect(options.mode, PreferredLaunchMode.inAppBrowserView);
      expect(options.browserConfiguration.showTitle, isTrue);
      expect(options.webViewConfiguration.headers, isEmpty);
    },
  );

  test('unsupported previews use the external browser', () async {
    browser.supported = false;
    expect(await openWebPreview(uri), isTrue);
    expect(
      browser.calls.single.$2.mode,
      PreferredLaunchMode.externalApplication,
    );
  });

  test('preview failure falls back and total failure is recoverable', () async {
    browser.previewFails = true;
    expect(await openWebPreview(uri), isTrue);
    expect(browser.calls.map((call) => call.$2.mode), [
      PreferredLaunchMode.inAppBrowserView,
      PreferredLaunchMode.externalApplication,
    ]);
    browser.externalFails = true;
    expect(await openWebPreview(uri), isFalse);
  });

  test('invalid or credential-bearing links never reach the browser', () async {
    for (final href in [
      'javascript:alert(1)',
      'file:///private/file',
      'content://private/file',
      '/relative',
      'https:///missing-host',
      'https://user:password@example.com/',
    ]) {
      expect(externalWebLink(href), isNull);
      expect(await openWebPreview(Uri.parse(href)), isFalse);
    }
    expect(browser.calls, isEmpty);
    expect(externalWebLink('http://example.com/'), isNotNull);
  });
}
