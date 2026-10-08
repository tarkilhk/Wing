import 'dart:io';

import 'package:yaml/yaml.dart';

const _qaCommand = "python3 -m unittest discover -s tools/qa -p 'test_*.py' -v";
const _architectureCommand = 'dart run tools/architecture/check_all.dart';
const _changedTestsCommand =
    r'python3 scripts/test.py --changed-since "$TEST_BASE_REF"';
const _fullTestsCommand = 'python3 scripts/test.py --full';
const _testBaseRef =
    r'${{ github.event.pull_request.base.sha || github.event.before }}';
const _fixtureNames = [
  'workspace_search_owner',
  'profile_discovery_writer',
  'saved_prompt_journal_admission',
  'retired_answer_versions_namespace',
  'current_tool_events',
  'activity_density',
];

const _nativeBoundaryCommand =
    'python3 tools/architecture/native_share/provider_boundary.py';
const _nativeFixtureCommand =
    'python3 tools/architecture/native_share/prove_boundary.py';
const _voiceBoundaryCommand =
    'python3 tools/architecture/native_voice/file_api_boundary.py';
const _voicePermissionCommand =
    'python3 tools/architecture/native_voice/permission_lifecycle.py';
const _voiceFixtureCommand =
    'python3 tools/architecture/native_voice/prove_boundary.py';

const _notificationBoundaryCommand =
    'python3 tools/architecture/native_notification/retired_action.py';
const _notificationFixtureCommand =
    'python3 tools/architecture/native_notification/prove_boundary.py';
const _declarationBoundaryCommand =
    'python3 tools/architecture/native_notification/retired_declaration.py';
const _declarationFixtureCommand =
    'python3 tools/architecture/native_notification/prove_declarations.py';

/// Protect mandatory gates in their actual workflow/job structure.
/// Commands must be plain single shell commands: comments, echo, soft-failing
/// steps and shell failure-swallowing suffixes cannot satisfy this contract.
List<String> checkRequiredQualityGates(Directory root) {
  final failures = <String>[];
  for (final target in [
    ('.github/workflows/pr-quality.yml', 'quality'),
    ('.github/workflows/release.yml', 'build'),
  ]) {
    try {
      final document = loadYaml(
        File('${root.path}/${target.$1}').readAsStringSync(),
      );
      if (document is! Map || document['jobs'] is! Map) {
        throw const FormatException('Expected workflow jobs.');
      }
      if (target.$2 == 'quality' && !_allBranchPushes(document['on'])) {
        failures.add(
          '${target.$1}:on:push REQUIRED_QUALITY_GATE: '
          'Run quality checks on pushes to every branch without path filters.',
        );
      }
      final job = (document['jobs'] as Map)[target.$2];
      if (job is! Map || job['steps'] is! List) {
        throw FormatException('Expected job ${target.$2} with steps.');
      }
      final steps = (job['steps'] as List).whereType<Map>().toList();
      for (final gate in [
        ('offline-qa', _qaCommand),
        ('architecture', _architectureCommand),
        (
          'authored-census',
          'python3 tools/architecture/rules/authored_census.py',
        ),
        for (final name in const [
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
          'activity_density',
          'retired_answer_versions_namespace',
          'resume_durable_identity',
          'intelligence_read_admission',
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
        ])
          ('independent-$name', 'dart run tools/architecture/rules/$name.dart'),
        (
          'native-retired-resources',
          'python3 tools/architecture/rules/native_retired_resources.py',
        ),
        for (final name in _fixtureNames)
          if (target.$2 == 'build' || name == 'workspace_search_owner')
            (
              'fixture-$name',
              'dart run tools/architecture/tests/${name}_test.dart',
            ),
        (
          'host-tests',
          target.$2 == 'quality' ? _changedTestsCommand : _fullTestsCommand,
        ),
        ('native-share-boundary', _nativeBoundaryCommand),
        ('native-share-fixtures', _nativeFixtureCommand),
        ('native-notification-action', _notificationBoundaryCommand),
        ('native-notification-fixtures', _notificationFixtureCommand),
        ('native-retired-declarations', _declarationBoundaryCommand),
        ('native-retired-declaration-fixtures', _declarationFixtureCommand),
        ('native-voice-boundary', _voiceBoundaryCommand),
        ('native-voice-permission-lifecycle', _voicePermissionCommand),
        ('native-voice-fixtures', _voiceFixtureCommand),
      ]) {
        final native =
            gate.$2 == _nativeBoundaryCommand ||
            gate.$2 == _nativeFixtureCommand ||
            gate.$2 == _notificationBoundaryCommand ||
            gate.$2 == _notificationFixtureCommand ||
            gate.$2 == _declarationBoundaryCommand ||
            gate.$2 == _declarationFixtureCommand ||
            gate.$2 == _voiceBoundaryCommand ||
            gate.$2 == _voicePermissionCommand ||
            gate.$2 == _voiceFixtureCommand;
        final protected =
            _hardFailure(job['continue-on-error']) &&
            _mandatoryJob(job['if'], target.$2) &&
            steps.indexed.any(
              (entry) =>
                  _hardFailure(entry.$2['continue-on-error']) &&
                  _mandatory(entry.$2['if']) &&
                  _runsFinalCommand(entry.$2['run'], gate.$2) &&
                  (gate.$2 != _changedTestsCommand ||
                      _boundTestBase(entry.$2['env'])) &&
                  (!native || steps.take(entry.$1).any(_nativeToolingReady)),
            );
        if (!protected) {
          failures.add(
            '${target.$1}:${target.$2}:${gate.$1} REQUIRED_QUALITY_GATE: '
            'Run ${gate.$2} as a mandatory hard-failing step'
            '${native ? ' after native Gradle dependency setup' : ''}.',
          );
        }
      }
    } on FileSystemException catch (error) {
      failures.add('${target.$1} QUALITY_WORKFLOW_INPUT: ${error.message}');
    } on YamlException catch (error) {
      failures.add('${target.$1} QUALITY_WORKFLOW_INPUT: ${error.message}');
    } on FormatException catch (error) {
      failures.add('${target.$1} QUALITY_WORKFLOW_INPUT: ${error.message}');
    }
  }
  failures.addAll(_checkNightly(root));
  return failures..sort();
}

bool _boundTestBase(Object? environment) =>
    environment is Map && environment['TEST_BASE_REF'] == _testBaseRef;

List<String> _checkNightly(Directory root) {
  const path = '.github/workflows/nightly-tests.yml';
  final failures = <String>[];
  try {
    final document = loadYaml(File('${root.path}/$path').readAsStringSync());
    if (document is! Map || document['jobs'] is! Map) {
      throw const FormatException('Expected workflow jobs.');
    }
    final events = document['on'];
    final schedules = events is Map ? events['schedule'] : null;
    if (schedules is! List ||
        !schedules.any(
          (entry) => entry is Map && entry['cron'] == '0 19 * * *',
        ) ||
        events is! Map ||
        !events.containsKey('workflow_dispatch')) {
      failures.add(
        '$path:on REQUIRED_QUALITY_GATE: '
        'Run exhaustive proofs nightly and support manual verification.',
      );
    }
    final job = (document['jobs'] as Map)['exhaustive'];
    if (job is! Map || job['steps'] is! List) {
      throw const FormatException('Expected exhaustive job with steps.');
    }
    final steps = (job['steps'] as List).whereType<Map>().toList();
    for (final command in [
      _fullTestsCommand,
      for (final name in _fixtureNames)
        'dart run tools/architecture/tests/${name}_test.dart',
    ]) {
      final protected =
          _hardFailure(job['continue-on-error']) &&
          _mandatory(job['if']) &&
          steps.indexed.any(
            (entry) =>
                _hardFailure(entry.$2['continue-on-error']) &&
                _mandatory(entry.$2['if']) &&
                _runsFinalCommand(entry.$2['run'], command) &&
                steps
                    .take(entry.$1)
                    .any(
                      (setup) =>
                          _hardFailure(setup['continue-on-error']) &&
                          _mandatory(setup['if']) &&
                          _runsFinalCommand(setup['run'], 'flutter pub get'),
                    ),
          );
      if (!protected) {
        failures.add(
          '$path:exhaustive REQUIRED_QUALITY_GATE: '
          'Run $command as a mandatory hard-failing step after dependencies.',
        );
      }
    }
  } on FileSystemException catch (error) {
    failures.add('$path QUALITY_WORKFLOW_INPUT: ${error.message}');
  } on YamlException catch (error) {
    failures.add('$path QUALITY_WORKFLOW_INPUT: ${error.message}');
  } on FormatException catch (error) {
    failures.add('$path QUALITY_WORKFLOW_INPUT: ${error.message}');
  }
  return failures;
}

bool _hardFailure(Object? value) => value == null || value == false;

bool _allBranchPushes(Object? events) {
  if (events is! Map || !events.containsKey('push')) return false;
  final push = events['push'];
  if (push == null) return true;
  if (push is! Map ||
      ['branches-ignore', 'paths', 'paths-ignore'].any(push.containsKey)) {
    return false;
  }
  final branches = push['branches'];
  if (branches == null) {
    return !push.containsKey('tags') && !push.containsKey('tags-ignore');
  }
  return branches is List && branches.length == 1 && branches.single == '**';
}

/// These existing Gradle commands populate the pinned Kotlin compiler cache.
/// This checks placement, not build success: absent tooling fails the native CLI.
bool _nativeToolingReady(Map step) =>
    _mandatory(step['if']) &&
    step['run'] is String &&
    const {
      './android/gradlew -p android :app:testDebugUnitTest --no-daemon',
      '(cd android && ./gradlew :app:testDebugUnitTest --no-daemon) '
          '2>&1 | tee native_test_output.txt\nexit \${PIPESTATUS[0]}',
    }.contains((step['run'] as String).trim());

bool _mandatoryJob(Object? condition, String job) {
  if (_mandatory(condition)) return true;
  // The release workflow intentionally accepts pushes and manual releases from
  // main only. Quality checks still have to run on every accepted release.
  return job == 'build' &&
      condition is String &&
      condition.replaceAll(RegExp(r'\s+'), '') ==
          "github.event_name=='push'||github.ref=='refs/heads/main'";
}

bool _mandatory(Object? condition) {
  if (condition == null || condition == true) return true;
  if (condition is! String) return false;
  final normalized = condition.replaceAll(RegExp(r'\s+'), '');
  return const {
    'success()',
    'always()',
    r'${{success()}}',
    r'${{always()}}',
    r'${{true}}',
  }.contains(normalized);
}

bool _runsFinalCommand(Object? run, String required) {
  if (run is! String) return false;
  final lines = run
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  if (lines.length != 1) return false;
  final command = lines.single;
  if (required != _architectureCommand) return command == required;
  // The optional reference is generated by CI from the preceding commit. It
  // must remain a quoted argument; shell operators cannot bypass this gate.
  return command == required ||
      RegExp(
        '^${RegExp.escape(required)} --baseline-reference "[^"\r\n;|&]+"\$',
      ).hasMatch(command);
}

void main(List<String> arguments) {
  final failures = checkRequiredQualityGates(
    Directory(arguments.isEmpty ? '.' : arguments.single),
  );
  for (final failure in failures) {
    stderr.writeln(failure);
  }
  exitCode = failures.isEmpty ? 0 : 1;
}
