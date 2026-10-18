import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/web_preview.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _Browser extends UrlLauncherPlatform {
  bool supported = true;
  bool previewFails = false;
  bool externalFails = false;
  bool previewAccepted = true;
  bool externalAccepted = true;
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
    return options.mode == PreferredLaunchMode.inAppBrowserView
        ? previewAccepted
        : externalAccepted;
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

  for (final failure in ['exception', 'refusal']) {
    test('preview $failure opens the exact URL externally', () async {
      browser.previewFails = failure == 'exception';
      browser.previewAccepted = false;
      expect(await openWebPreview(uri), isTrue);
      expect(browser.calls.map((call) => call.$1), [
        uri.toString(),
        uri.toString(),
      ]);
      expect(browser.calls.map((call) => call.$2.mode), [
        PreferredLaunchMode.inAppBrowserView,
        PreferredLaunchMode.externalApplication,
      ]);
    });

    test('external $failure reports that no browser opened', () async {
      browser.supported = false;
      browser.externalFails = failure == 'exception';
      browser.externalAccepted = false;
      expect(await openWebPreview(uri), isFalse);
      expect(
        browser.calls.single.$2.mode,
        PreferredLaunchMode.externalApplication,
      );
    });
  }

  for (final href in [
    'javascript:alert(1)',
    'file:///private/file',
    'content://private/file',
    '/relative',
    'https:///missing-host',
    'https://user:password@example.com/',
  ]) {
    test('unsafe link never reaches the browser: $href', () async {
      expect(externalWebLink(href), isNull);
      expect(await openWebPreview(Uri.parse(href)), isFalse);
      expect(browser.calls, isEmpty);
    });
  }

  test('an ordinary HTTP address is an eligible external link', () {
    expect(
      externalWebLink('http://example.com/'),
      Uri.parse('http://example.com/'),
    );
  });
}
