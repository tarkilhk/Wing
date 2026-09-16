import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/screens/administration/admin_providers_page.dart';
import 'package:wing/core/theme/wing_theme.dart';
import 'support/administration_fixture.dart';

Map<String, dynamic> provider(
  String id,
  Map<String, dynamic> status, {
  String flow = 'device_code',
}) => {
  'id': id,
  'name': id,
  'status': status,
  'flow': flow,
  'disconnectable': true,
};

void main() {
  final pageScroll = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  testWidgets(
    'multiple connected providers, expired tokens and defaults remain independent',
    (tester) async {
      final fixture = AdministrationFixture();
      var fail = false;
      fixture.override = (method, path, query, body) async {
        if (fail) throw StateError('Offline');
        if (path == 'env') return {};
        if (path == 'profiles') {
          return {
            'profiles': [
              {'name': 'personal', 'provider': 'alpha'},
              {'name': 'work', 'provider': 'beta'},
            ],
          };
        }
        return {
          'providers': [
            provider('alpha', {'logged_in': true}),
            provider('beta', {'logged_in': true}),
            provider('expired', {
              'logged_in': true,
              'expires_at': '2020-01-01T00:00:00Z',
              'has_refresh_token': true,
            }),
            provider('unused', {'logged_in': false}),
          ],
        };
      };
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.dark),
          home: AdminProvidersPage(
            profile: fixture.server.profile('default'),
            shared: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connected (2)'), findsOneWidget);
      expect(find.text('Needs attention (1)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('provider-expired'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('provider-alpha'))).dy,
        ),
      );
      expect(find.byTooltip('Renew expired sign-in'), findsOneWidget);
      await tester.tap(find.text('Connected (2)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign-in expired'), findsNothing);
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Default provider for: personal'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('beta'));
      await tester.pumpAndSettle();
      expect(find.text('Default provider for: work'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        fixture.requests
            .where((r) => r.$2 == 'providers/oauth')
            .every((r) => r.$3['profile'] == 'default'),
        isTrue,
      );
      fail = true;
      await tester.scrollUntilVisible(
        find.text('Refresh access'),
        -250,
        scrollable: pageScroll,
      );
      await tester.tap(find.text('Refresh access'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Last checked'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Connected (2)'),
        -250,
        scrollable: pageScroll,
      );
      expect(find.text('Connected (2)'), findsOneWidget);
      expect(fixture.requests.every((r) => r.$1 == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large text, external status and missing selections remain usable',
    (tester) async {
      final fixture = AdministrationFixture();
      fixture.override = (method, path, query, body) async {
        if (path == 'profiles') throw StateError('Unavailable');
        if (path == 'env') return {};
        return {
          'providers': [
            provider('External provider with a long display name', {
              'logged_in': false,
            }, flow: 'external'),
          ],
        };
      };
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: wingTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: AdminProvidersPage(
            profile: fixture.server.profile('personal'),
            shared: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Profile selections could not be loaded'),
        200,
        scrollable: pageScroll,
      );
      expect(
        find.textContaining('Profile selections could not be loaded'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('External provider with a long display name'),
        200,
        scrollable: pageScroll,
      );
      await tester.tap(find.text('External provider with a long display name'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Source and sign-in help'),
        200,
        scrollable: pageScroll,
      );
      await tester.ensureVisible(find.text('Source and sign-in help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source and sign-in help'));
      await tester.pumpAndSettle();
      expect(find.text('Check external sign-in'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);
      expect(find.text('Remove profile account'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
