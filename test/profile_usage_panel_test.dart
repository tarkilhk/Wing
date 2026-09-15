import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wing/core/models/hermes_profile.dart';
import 'package:wing/core/services/profile_gateway.dart';
import 'package:wing/core/services/profiles_repository.dart';
import 'package:wing/core/widgets/profile_usage_panel.dart';

ProfileGateway gateway(
  Future<Map<String, dynamic>> Function(String, Map<String, String>) get,
) => ProfileGateway(
  scope: WorkspaceScope(connectionId: 'c1', profileName: 'default'),
  get: get,
  rpc: (_, _) async => <String, dynamic>{},
  discover: () async =>
      const ProfileDiscovery(profiles: [], currentName: null, activeName: null),
);

void main() {
  testWidgets(
    'requests the selected profile and separates actual from estimate',
    (tester) async {
      String? endpoint;
      Map<String, String>? query;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileUsagePanel(
            connectionLabel: 'Office',
            capturedProfileGateway: gateway((path, params) async {
              endpoint = path;
              query = params;
              return const {
                'period_days': 30,
                'totals': {
                  'total_sessions': 1234,
                  'total_api_calls': 5678,
                  'total_input': 40755279,
                  'total_output': 9123456,
                  'total_estimated_cost': 12345.25,
                  'total_actual_cost': 1.10,
                },
                'by_model': [
                  {
                    'model': 'provider/model',
                    'input_tokens': 40000000,
                    'output_tokens': 9000000,
                    'estimated_cost': 12345.25,
                  },
                ],
              };
            }),
          ),
        ),
      );
      expect(endpoint, isNull);
      await tester.tap(find.text('Load usage'));
      await tester.pumpAndSettle();
      expect(endpoint, 'analytics/usage');
      expect(query, {'days': '30', 'profile': 'default'});
      expect(
        find.text('Session usage · last 30 days · Office'),
        findsOneWidget,
      );
      expect(find.text('Estimated cost'), findsOneWidget);
      expect(find.text('40,755,279'), findsOneWidget);
      expect(find.text('9,123,456'), findsOneWidget);
      expect(find.text(r'$12,345.25'), findsOneWidget);
      expect(find.text('Reported cost (where available)'), findsOneWidget);
      expect(find.text(r'$1.10'), findsOneWidget);
      await tester.tap(find.text('Models (includes auxiliary calls)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tokens: 40,000,000 in / 9,000,000 out'),
        findsOneWidget,
      );
      expect(find.textContaining(r'Estimated: $12,345.25'), findsOneWidget);
    },
  );

  testWidgets('keeps missing or malformed actual cost truthful', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileUsagePanel(
          capturedProfileGateway: gateway(
            (_, _) async => const {
              'period_days': 30,
              'totals': {
                'total_sessions': 1,
                'total_estimated_cost': 2.0,
                'total_actual_cost': 'not-a-number',
              },
              'by_model': [
                {
                  'model': 'provider/model',
                  'input_tokens': 3,
                  'output_tokens': 4,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Load usage'));
    await tester.pumpAndSettle();
    expect(find.text('Estimated cost'), findsOneWidget);
    expect(find.text(r'$2.00'), findsOneWidget);
    expect(find.text('Reported cost (where available)'), findsOneWidget);
    expect(find.text('Unknown'), findsNWidgets(4));
    await tester.tap(find.text('Models (includes auxiliary calls)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estimated: Unknown'), findsOneWidget);
  });

  testWidgets('late response from an old gateway does not replace new owner', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final oldGateway = gateway((_, _) => first.future);
    final newGateway = gateway((_, _) => second.future);
    await tester.pumpWidget(
      MaterialApp(home: ProfileUsagePanel(capturedProfileGateway: oldGateway)),
    );
    await tester.tap(find.text('Load usage'));
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: ProfileUsagePanel(capturedProfileGateway: newGateway)),
    );
    await tester.tap(find.text('Load usage'));
    second.complete(const {
      'period_days': 30,
      'totals': {'total_sessions': 2},
    });
    await tester.pumpAndSettle();
    first.complete(const {
      'period_days': 30,
      'totals': {'total_sessions': 99},
    });
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('99'), findsNothing);
  });

  testWidgets('malformed usage offers manual retry without exposing errors', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileUsagePanel(
          capturedProfileGateway: gateway((_, _) async {
            calls++;
            if (calls == 1) return {'period_days': 30, 'totals': 'invalid'};
            throw StateError('private server detail');
          }),
        ),
      ),
    );
    await tester.tap(find.text('Load usage'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Usage could not be loaded.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('private server detail'), findsNothing);
  });

  testWidgets('disposed panel ignores a pending response', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileUsagePanel(
          capturedProfileGateway: gateway((_, _) => pending.future),
        ),
      ),
    );
    await tester.tap(find.text('Load usage'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete({
      'period_days': 30,
      'totals': {'total_sessions': 99},
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in a narrow large-text viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              ProfileUsagePanel(
                capturedProfileGateway: gateway(
                  (_, _) async => const {
                    'period_days': 30,
                    'totals': {'total_sessions': 1},
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Load usage'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
