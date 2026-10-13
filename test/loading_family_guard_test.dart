import 'package:flutter_test/flutter_test.dart';

import '../tools/architecture/rules/loading_family.dart' as loading;
import 'architecture_contract_test.dart' show FixtureWorkspace;

void main() {
  final cases = <String, bool>{
    'const CircularProgressIndicator()': false,
    'LinearProgressIndicator()': false,
    'ActivityShimmer(active: true, child: Text())': false,
    'ChatWorkingBorder(working: true, child: Text())': false,
    "StudioActivityIndicator(active: true, label: 'Working', icon: Icons.pending, color: Colors.blue)":
        true,
    'material.CircularProgressIndicator()': false,
    'const cupertino.CupertinoActivityIndicator.partiallyRevealed()': false,
    'RefreshIndicator.noSpinner(child: Widget())': false,
    "StudioLoading(label: 'Loading')": true,
    "StudioLoadingRegion(busy: true, available: false, label: 'Loading', child: Widget())":
        true,
    'StudioRefresh(available: true, onRefresh: refresh, child: Widget())': true,
    "StudioCapacityMeter(fraction: .5, label: 'Capacity')": true,
    "Text('CircularProgressIndicator()')": true,
  };
  for (final entry in cases.entries) {
    test('loading family guard: ${entry.key}', () {
      final fixture = FixtureWorkspace({
        'files': {
          'lib/view.dart': {
            'role': 'view',
            'source': 'void build() { final widget = ${entry.key}; }',
          },
        },
      });
      addTearDown(fixture.dispose);
      final findings = loading.check(fixture.snapshot);
      expect(findings, entry.value ? isEmpty : isNotEmpty);
    });
  }
  test('only the shared owner may integrate native refresh mechanics', () {
    final fixture = FixtureWorkspace({
      'files': {
        loading.owner: {
          'role': 'presentation',
          'source': 'void build() { RefreshIndicator.noSpinner(); }',
        },
      },
    });
    addTearDown(fixture.dispose);
    expect(loading.check(fixture.snapshot), isEmpty);
  });
}
