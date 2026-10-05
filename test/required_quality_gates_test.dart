import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/architecture/rules/required_quality_gates.dart';

const qaCommand = "python3 -m unittest discover -s tools/qa -p 'test_*.py' -v";
const architectureCommand = 'dart run tools/architecture/check_all.dart';
const nativeBoundaryCommand =
    'python3 tools/architecture/native_share/provider_boundary.py';
const nativeFixtureCommand =
    'python3 tools/architecture/native_share/prove_boundary.py';
const voiceBoundaryCommand =
    'python3 tools/architecture/native_voice/file_api_boundary.py';
const voicePermissionCommand =
    'python3 tools/architecture/native_voice/permission_lifecycle.py';
const voiceFixtureCommand =
    'python3 tools/architecture/native_voice/prove_boundary.py';
const notificationBoundaryCommand =
    'python3 tools/architecture/native_notification/retired_action.py';
const notificationFixtureCommand =
    'python3 tools/architecture/native_notification/prove_boundary.py';
const declarationBoundaryCommand =
    'python3 tools/architecture/native_notification/retired_declaration.py';
const declarationFixtureCommand =
    'python3 tools/architecture/native_notification/prove_declarations.py';
const nativeCommands = [
  notificationBoundaryCommand,
  notificationFixtureCommand,
  declarationBoundaryCommand,
  declarationFixtureCommand,
  nativeBoundaryCommand,
  nativeFixtureCommand,
  voiceBoundaryCommand,
  voicePermissionCommand,
  voiceFixtureCommand,
];

const independentGuards = [
  'completed_model_view',
  'public_owner_state',
  'capabilities_view_dependencies',
  'tool_setup_view_dependencies',
  'reading_view_inputs',
  'skills_view_dependencies',
  'find_view_dependencies',
  'connectors_view_dependencies',
  'mcp_setup_view_dependencies',
  'outputs_view_dependencies',
  'download_file_value',
  'logs_view_dependencies',
  'connector_detail_mount',
  'voice_view_dependencies',
  'speech_synthesis_view_dependencies',
  'plugins_view_dependencies',
  'workspace_entry_key_owner',
  'usage_view_dependencies',
  'chat_runtime_observation',
  'secure_reply_view_wire',
  'shared_draft_view_dependencies',
  'provider_recovery_view_dependencies',
  'slash_completion_view_dependencies',
  'resource_preview_view_dependencies',
  'supervision_view_dependencies',
  'workspace_voice_view_dependencies',
  'browser_view_dependencies',
  'project_actions_view_dependencies',
  'row_actions_view_dependencies',
  'browser_values',
  'workspace_canonical_state',
  'workspace_search_owner',
  'transcript_history_dispatch',
  'profile_discovery_writer',
  'saved_prompt_journal_admission',
  'current_tool_events',
  'retired_answer_versions_namespace',
  'resume_durable_identity',
  'settings_view_protocol',
  'owned_model_mutation',
  'overview_view_wire',
  'provider_view_protocol',
  'memory_view_protocol',
  'deleted_draft_cleanup_boundary',
  'model_catalog_fixture',
  'dart_main_roots',
  'completed_setup_view',
  'app_preferences_view',
  'visibility_key_owner',
  'backup_owner_boundary',
  'app_preferences_construction',
  'profiles_management_view',
  'profile_identity_view',
  'profile_colours_view',
  'browser_row_work',
  'notification_journal_ack',
];
final independentCommands = [
  'dart run tools/architecture/tests/workspace_search_owner_test.dart',
  'dart run tools/architecture/tests/profile_discovery_writer_test.dart',
  'dart run tools/architecture/tests/saved_prompt_journal_admission_test.dart',
  'dart run tools/architecture/tests/current_tool_events_test.dart',
  'dart run tools/architecture/tests/retired_answer_versions_namespace_test.dart',
  'python3 tools/architecture/rules/authored_census.py',
  'python3 tools/architecture/rules/native_retired_resources.py',
  for (final guard in independentGuards)
    'dart run tools/architecture/rules/$guard.dart',
];

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wing-quality-gates-');
    await Directory('${root.path}/.github/workflows').create(recursive: true);
    _writeWorkflows(root);
  });

  tearDown(() async => root.delete(recursive: true));

  test('normal mandatory QA and architecture gates are accepted', () {
    expect(checkRequiredQualityGates(root), isEmpty);
  });

  test('each independent production guard is mandatory and hard-failing', () {
    for (final command in independentCommands) {
      for (final invalid in [
        'echo "$command"',
        '$command || true',
        'echo fixture-only',
      ]) {
        _writeWorkflows(root);
        final file = File('${root.path}/.github/workflows/pr-quality.yml');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            'run: $command',
            'run: $invalid',
          ),
        );
        expect(checkRequiredQualityGates(root), hasLength(1));
      }
      for (final prefix in ['continue-on-error: true', 'if: false']) {
        _writeWorkflows(root);
        final file = File('${root.path}/.github/workflows/release.yml');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            'run: $command',
            '$prefix\n        run: $command',
          ),
        );
        expect(checkRequiredQualityGates(root), hasLength(1));
      }
    }
  });

  test('actual CLI rejects fixture-only provider enforcement', () async {
    final file = File('${root.path}/.github/workflows/pr-quality.yml');
    const command =
        'dart run tools/architecture/rules/provider_view_protocol.dart';
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst(
        'run: $command',
        'run: dart run tools/architecture/tests/provider_view_protocol_test.dart',
      ),
    );
    final invalid = await Process.run('dart', [
      'run',
      'tools/architecture/rules/required_quality_gates.dart',
      root.path,
    ]);
    expect(invalid.exitCode, 1);
    expect(invalid.stderr, contains('independent-provider_view_protocol'));
    _writeWorkflows(root);
    final valid = await Process.run('dart', [
      'run',
      'tools/architecture/rules/required_quality_gates.dart',
      root.path,
    ]);
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
  });

  for (final name in const [
    'completed_setup_view',
    'app_preferences_view',
    'visibility_key_owner',
    'backup_owner_boundary',
    'app_preferences_construction',
    'profiles_management_view',
    'profile_identity_view',
    'profile_colours_view',
    'browser_row_work',
    'notification_journal_ack',
  ]) {
    test('actual CLI rejects omitted $name enforcement', () async {
      final command = 'dart run tools/architecture/rules/$name.dart';
      final initiallyValid = await Process.run('dart', [
        'run',
        'tools/architecture/rules/required_quality_gates.dart',
        root.path,
      ]);
      expect(initiallyValid.exitCode, 0);
      for (final workflow in ['pr-quality.yml', 'release.yml']) {
        final file = File('${root.path}/.github/workflows/$workflow');
        final source = file.readAsStringSync();
        expect(source.split('run: $command'), hasLength(2));
        file.writeAsStringSync(
          source.replaceFirst(
            'run: $command',
            'run: echo omitted production guard',
          ),
        );
        final invalid = await Process.run('dart', [
          'run',
          'tools/architecture/rules/required_quality_gates.dart',
          root.path,
        ]);
        expect(invalid.exitCode, 1);
        expect(invalid.stderr, contains('independent-$name'));
        expect(invalid.stderr, contains(workflow));
        _writeWorkflows(root);
        final valid = await Process.run('dart', [
          'run',
          'tools/architecture/rules/required_quality_gates.dart',
          root.path,
        ]);
        expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
      }
    });
  }

  test('both native commands must be real hard-failing steps', () {
    for (final command in nativeCommands) {
      for (final invalid in ['echo "$command"', '$command || true']) {
        _writeWorkflows(root);
        for (final name in ['pr-quality.yml', 'release.yml']) {
          final file = File('${root.path}/.github/workflows/$name');
          file.writeAsStringSync(
            file.readAsStringSync().replaceFirst(
              'run: $command',
              'run: $invalid',
            ),
          );
        }
        expect(checkRequiredQualityGates(root), hasLength(2));
      }
    }
  });

  test('native steps cannot be softened or conditionally omitted', () {
    for (final command in nativeCommands) {
      for (final prefix in ['continue-on-error: true', 'if: false']) {
        _writeWorkflows(root);
        final file = File('${root.path}/.github/workflows/pr-quality.yml');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            'run: $command',
            '$prefix\n        run: $command',
          ),
        );
        expect(checkRequiredQualityGates(root), hasLength(1));
      }
    }
  });

  test('native guards follow cache-ready Gradle setup', () {
    _writeWorkflows(root, nativeSetup: false);
    expect(
      checkRequiredQualityGates(root),
      hasLength(nativeCommands.length * 2),
    );
    _writeWorkflows(root, nativeSetup: true);
    final file = File('${root.path}/.github/workflows/pr-quality.yml');
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst(
        'run: ./android/gradlew -p android :app:testDebugUnitTest --no-daemon',
        'if: false\n        run: ./android/gradlew -p android :app:testDebugUnitTest --no-daemon',
      ),
    );
    expect(checkRequiredQualityGates(root), hasLength(nativeCommands.length));
    _writeWorkflows(root);
    final contents = file.readAsStringSync();
    const setup =
        '      - name: Native dependency setup\n'
        '        run: ./android/gradlew -p android :app:testDebugUnitTest --no-daemon\n';
    file.writeAsStringSync(contents.replaceFirst(setup, '') + setup);
    expect(checkRequiredQualityGates(root), hasLength(nativeCommands.length));
  });

  test('a command in a comment or echo cannot stand in for a gate', () {
    _writeWorkflows(root, qa: '# $qaCommand\n          echo "$qaCommand"');
    expect(
      checkRequiredQualityGates(root),
      contains(contains('REQUIRED_QUALITY_GATE:')),
    );
  });

  test('a soft failure cannot protect quality', () {
    _writeWorkflows(root, softFailure: true);
    expect(
      checkRequiredQualityGates(root),
      contains(contains('REQUIRED_QUALITY_GATE:')),
    );
  });

  test('a conditionally skipped gate is not mandatory', () {
    _writeWorkflows(root, conditional: true);
    expect(
      checkRequiredQualityGates(root),
      contains(contains('REQUIRED_QUALITY_GATE:')),
    );
  });

  test('a skipped job cannot hide otherwise mandatory steps', () {
    _writeWorkflows(root, jobCondition: 'false');
    expect(
      checkRequiredQualityGates(root),
      contains(contains('REQUIRED_QUALITY_GATE:')),
    );
  });

  test('release checks accept their explicit main and push scope', () {
    _writeWorkflows(root);
    final release = File('${root.path}/.github/workflows/release.yml');
    release.writeAsStringSync(
      release.readAsStringSync().replaceFirst(
        '  build:',
        "  build:\n    if: github.event_name == 'push' || github.ref == 'refs/heads/main'",
      ),
    );
    expect(checkRequiredQualityGates(root), isEmpty);
  });

  test('a later shell success does not hide a failed command', () {
    _writeWorkflows(root, qa: '$qaCommand || true');
    expect(
      checkRequiredQualityGates(root),
      contains(contains('REQUIRED_QUALITY_GATE:')),
    );
  });

  test('an unreachable command cannot stand in for a gate', () {
    _writeWorkflows(root, qa: 'exit 0\n          $qaCommand');
    expect(
      checkRequiredQualityGates(root),
      contains(contains('REQUIRED_QUALITY_GATE:')),
    );
  });

  test('missing and malformed workflows fail closed', () {
    File('${root.path}/.github/workflows/pr-quality.yml').deleteSync();
    expect(
      checkRequiredQualityGates(root),
      contains(contains('QUALITY_WORKFLOW_INPUT:')),
    );
    File(
      '${root.path}/.github/workflows/pr-quality.yml',
    ).writeAsStringSync('[[');
    expect(
      checkRequiredQualityGates(root),
      contains(contains('QUALITY_WORKFLOW_INPUT:')),
    );
  });

  test(
    'individual CLI rejects missing gate and accepts repaired workflow',
    () async {
      _writeWorkflows(root, qa: 'echo missing');
      final invalid = await Process.run('dart', [
        'run',
        'tools/architecture/rules/required_quality_gates.dart',
        root.path,
      ]);
      expect(invalid.exitCode, 1);
      expect(invalid.stderr, contains('REQUIRED_QUALITY_GATE:'));
      _writeWorkflows(root);
      final valid = await Process.run('dart', [
        'run',
        'tools/architecture/rules/required_quality_gates.dart',
        root.path,
      ]);
      expect(valid.exitCode, 0);
      expect(valid.stderr, isNot(contains('REQUIRED_QUALITY_GATE:')));
      expect(valid.stderr, isNot(contains('QUALITY_WORKFLOW_INPUT:')));
      for (final command in [nativeBoundaryCommand, nativeFixtureCommand]) {
        _writeWorkflows(root);
        final file = File('${root.path}/.github/workflows/pr-quality.yml');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            'run: $command',
            'run: echo missing',
          ),
        );
        final omittedNative = await Process.run('dart', [
          'run',
          'tools/architecture/rules/required_quality_gates.dart',
          root.path,
        ]);
        expect(omittedNative.exitCode, 1);
        expect(omittedNative.stderr, contains('native-share-'));
      }
    },
  );
}

void _writeWorkflows(
  Directory root, {
  String qa = qaCommand,
  bool softFailure = false,
  bool conditional = false,
  String? jobCondition,
  bool nativeSetup = true,
}) {
  for (final item in [
    ('pr-quality.yml', 'quality'),
    ('release.yml', 'build'),
  ]) {
    File('${root.path}/.github/workflows/${item.$1}').writeAsStringSync('''
jobs:
  ${item.$2}:
    ${jobCondition == null ? '# mandatory job' : 'if: $jobCondition'}
    steps:
      - name: Offline QA
        ${softFailure ? 'continue-on-error: true' : '# mandatory'}
        ${conditional ? "if: github.ref == 'refs/heads/example'" : '# unconditional'}
        run: |
          $qa
      - name: Architecture
        run: $architectureCommand
${independentCommands.map((command) => '      - name: Independent production guard\n        run: $command').join('\n')}
      ${nativeSetup ? '- name: Native dependency setup\n        run: ./android/gradlew -p android :app:testDebugUnitTest --no-daemon' : '# no dependency setup'}
${nativeCommands.map((command) => '      - name: Native guard\n        run: $command').join('\n')}
''');
  }
}
