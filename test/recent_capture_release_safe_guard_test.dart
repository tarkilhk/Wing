import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/architecture/rules/recent_capture_release_safe.dart' as rule;

const _invalid = '''
import 'package:flutter/rendering.dart' as rendering;
typedef Boundary = rendering.RenderRepaintBoundary;
bool direct(Boundary boundary) => boundary.debugNeedsPaint;
bool? nullable(Boundary? boundary) => boundary?.debugNeedsPaint;
Boundary cascade(Boundary boundary) => boundary..debugNeedsPaint;
class Inherited extends rendering.RenderRepaintBoundary {
  bool capture() => debugNeedsPaint;
}
''';

const _valid = '''
import 'package:flutter/rendering.dart' as rendering;
import 'package:flutter/scheduler.dart';
class Unrelated {
  bool get debugNeedsPaint => false;
}
bool ordinary(Unrelated value) => value.debugNeedsPaint;
class Checked extends rendering.RenderRepaintBoundary {
  Checked(rendering.RenderObject other) : assert(!other.debugNeedsPaint);
  bool checked() {
    assert(!debugNeedsPaint);
    assert(() { return !debugNeedsPaint; }());
    return true;
  }
}
Future<void> capture(rendering.RenderRepaintBoundary boundary) async {
  await SchedulerBinding.instance.endOfFrame;
  assert(!boundary.debugNeedsPaint);
  await boundary.toImage();
}
''';

void main() {
  test('production recent capture is safe with assertions disabled', () async {
    expect(await rule.check(Directory.current), isEmpty);
  });

  test(
    'resolved Flutter reads fail while asserts and unrelated getters pass',
    () async {
      final root = Directory.systemTemp.createTempSync('wing-capture-guard-');
      addTearDown(() => root.deleteSync(recursive: true));
      final original = File('.dart_tool/package_config.json').absolute;
      final config = jsonDecode(original.readAsStringSync()) as Map;
      final target = File('${root.path}/${rule.owner}');
      target.parent.createSync(recursive: true);
      final fixtureConfig = File('${root.path}/.dart_tool/package_config.json');
      fixtureConfig.parent.createSync(recursive: true);
      fixtureConfig.writeAsStringSync(
        jsonEncode({
          ...config,
          'packages': [
            for (final package in config['packages'] as List)
              {
                ...package as Map,
                'rootUri': package['name'] == 'wing'
                    ? root.uri.toString()
                    : original.uri.resolve(package['rootUri']).toString(),
              },
          ],
        }),
      );

      target.writeAsStringSync(_invalid);
      final findings = await rule.check(root);
      expect(findings, hasLength(4));
      expect(findings.map((finding) => finding.id).toSet(), {rule.id});
      expect(findings.map((finding) => finding.file).toSet(), {rule.owner});
      expect(findings.map((finding) => finding.line).toSet(), {3, 4, 5, 7});
      final invalidCli = await _cli(root);
      expect(invalidCli.exitCode, 1, reason: _output(invalidCli));
      expect(invalidCli.stdout, contains(rule.id));

      target.writeAsStringSync(_valid);
      expect(await rule.check(root), isEmpty);
      final validCli = await _cli(root);
      expect(validCli.exitCode, 0, reason: _output(validCli));

      target.deleteSync();
      final inputCli = await _cli(root);
      expect(inputCli.exitCode, 2, reason: _output(inputCli));
      expect(inputCli.stderr, contains('${rule.id} INPUT'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<ProcessResult> _cli(Directory root) => Process.run('dart', [
  'run',
  'tools/architecture/rules/recent_capture_release_safe.dart',
  '--root',
  root.path,
]);

String _output(ProcessResult result) => '${result.stdout}\n${result.stderr}';
