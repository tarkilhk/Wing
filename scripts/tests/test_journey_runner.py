import json
import contextlib
import io
import re
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from scripts import test_journeys
from scripts.test_journeys import CRITICAL, ROADMAP, verdict


def events(expected=CRITICAL, *, skipped=None, failed=None, omitted=None):
    result = []
    for index, name in enumerate(sorted(expected)):
        if name == omitted:
            continue
        result.extend([
            {'type': 'testStart', 'test': {'id': index, 'name': name}},
            {'type': 'testDone', 'testID': index, 'hidden': False,
             'skipped': name == skipped, 'result': 'failure' if name == failed else 'success'},
        ])
    result.append({'type': 'done', 'success': True})
    return [json.dumps(item) for item in result]


class CompletedOnboardingOwnership(unittest.TestCase):
    package = 'com.tarkilhk.wing.notificationqa'

    def device(self, granted=False):
        def run(serial, *args):
            if args[:3] == ('shell', 'pm', 'path'):
                return 'package:/fixture/base.apk'
            if args[:3] == ('shell', 'dumpsys', 'package'):
                return ('android.permission.POST_NOTIFICATIONS: granted=true\n'
                        'android.permission.RECORD_AUDIO: granted=true') if granted else ''
            if args == ('shell', 'dumpsys', 'deviceidle', 'whitelist'):
                return self.package if granted else ''
            return ''
        return run

    def test_failure_restores_only_prerequisites_this_attempt_added(self):
        evidence = {}
        with patch.object(test_journeys.android, 'device', side_effect=self.device()) as device:
            with self.assertRaisesRegex(RuntimeError, 'journey failed'):
                with test_journeys.completed_onboarding('emulator-5562', evidence):
                    raise RuntimeError('journey failed')
        actions = [call.args[1:] for call in device.call_args_list]
        for permission in ('android.permission.POST_NOTIFICATIONS', 'android.permission.RECORD_AUDIO'):
            self.assertIn(('shell', 'pm', 'grant', self.package, permission), actions)
            self.assertIn(('shell', 'pm', 'revoke', self.package, permission), actions)
        self.assertIn(('shell', 'dumpsys', 'deviceidle', 'whitelist', '-' + self.package), actions)
        self.assertNotIn('restored', evidence)

    def test_existing_grants_and_exemption_survive_the_attempt(self):
        evidence = {}
        with patch.object(test_journeys.android, 'device', side_effect=self.device(granted=True)) as device:
            with test_journeys.completed_onboarding('emulator-5562', evidence):
                pass
        actions = [call.args[1:] for call in device.call_args_list]
        self.assertFalse(any('grant' in action or 'revoke' in action for action in actions))
        self.assertFalse(any('-' + self.package in action or '+' + self.package in action for action in actions))
        self.assertTrue(evidence['restored'])


class AndroidJourneyVerdict(unittest.TestCase):
    def test_current_chat_account_usage_is_a_required_native_journey(self):
        name = 'current chat account usage preserves route ownership through refresh and departure'
        self.assertIn(name, ROADMAP)
        result = verdict(events(ROADMAP, omitted=name), 0, ROADMAP)
        self.assertFalse(result['passed'])
        self.assertEqual(result['missing'], [name])

    def test_hub_updates_is_a_required_native_journey(self):
        name = 'Hub skill update checks keep browsing and group updates scoped'
        self.assertIn(name, ROADMAP)
        self.assertFalse(verdict(events(ROADMAP, omitted=name), 0, ROADMAP)['passed'])

    def test_parent_stream_completion_is_a_required_native_journey(self):
        name = 'completed child stays in current work while the parent streams'
        self.assertIn(name, ROADMAP)
        result = verdict(events(ROADMAP, omitted=name), 0, ROADMAP)
        self.assertFalse(result['passed'])
        self.assertEqual(result['missing'], [name])
        self.assertTrue(verdict(events(ROADMAP), 0, ROADMAP)['passed'])

    def test_all_required_journeys_must_complete(self):
        self.assertTrue(verdict(events(), 0, CRITICAL)['passed'])

    def test_successful_empty_run_is_not_acceptance(self):
        self.assertFalse(verdict(['{"type":"done","success":true}'], 0, CRITICAL)['passed'])

    def test_each_missing_journey_fails_even_when_flutter_claims_success(self):
        for name in CRITICAL:
            with self.subTest(name=name):
                self.assertFalse(verdict(events(omitted=name), 0, CRITICAL)['passed'])

    def test_skipping_a_required_journey_fails(self):
        self.assertFalse(verdict(events(skipped=sorted(CRITICAL)[0]), 0, CRITICAL)['passed'])

    def test_assertion_failure_overrides_success_summary(self):
        self.assertFalse(verdict(events(failed=sorted(CRITICAL)[0]), 0, CRITICAL)['passed'])

    def test_build_failure_overrides_test_success(self):
        self.assertFalse(verdict(events(), 1, CRITICAL)['passed'])

    def test_loading_error_overrides_test_success(self):
        lines = events() + [json.dumps({'type': 'error', 'testID': -1})]
        self.assertFalse(verdict(lines, 0, CRITICAL)['passed'])

    def test_interrupted_stream_fails(self):
        self.assertFalse(verdict(events()[:-1], 0, CRITICAL)['passed'])

    def test_duplicate_journeys_are_rejected(self):
        self.assertFalse(verdict(events() + events(), 0, CRITICAL)['passed'])

    def test_build_diagnostics_do_not_hide_real_verdict(self):
        self.assertTrue(verdict(['Installing APK...', '[]'] + events(), 0, CRITICAL)['passed'])

    def test_empty_enrollment_cannot_certify_a_run(self):
        self.assertFalse(verdict(events(), 0, frozenset())['passed'])

    def test_unenrolled_successful_journey_is_rejected(self):
        result = verdict(events(CRITICAL | {'unapproved workflow'}), 0, CRITICAL)
        self.assertFalse(result['passed'])
        self.assertEqual(result['unexpected'], ['unapproved workflow'])

    def test_later_success_summary_cannot_erase_a_failed_summary(self):
        lines = [json.dumps({'type': 'done', 'success': False})] + events()
        self.assertFalse(verdict(lines, 0, CRITICAL)['passed'])


class RequiredProcessRecovery(unittest.TestCase):
    def exercise(self, recovery, *, ordinary_events=None, roadmap_events=None, recovery_error=None,
                 environments=None, captures=None, wait_error=None, exports=None, frame_error=None, capture_error=None, retirements=None,
                 cases=(), preparation_exit=0, trace=None, fingerprints=None, capture_frames=False):
        with tempfile.TemporaryDirectory(prefix='wing-journey-gate-') as temporary:
            output = Path(temporary)
            selected = frozenset(cases) if cases else CRITICAL | ROADMAP
            log = output / ('critical.jsonl' if selected & CRITICAL else 'roadmap.jsonl')

            @contextlib.contextmanager
            def owned():
                if trace is not None:
                    trace.append('emulator-start')
                try:
                    yield 'emulator-5562'
                finally:
                    if trace is not None:
                        trace.append('emulator-retired')

            def run_flutter(*args, **kwargs):
                if environments is not None:
                    environments.append(kwargs['env'])
                command = args[0]
                if command[0] != 'flutter' or command[1] != 'test':
                    if trace is not None:
                        trace.append('build' if command[0] == 'flutter' else 'install')
                    return Mock(wait=Mock(return_value=preparation_exit))
                if trace is not None:
                    trace.append('test')
                expected = ROADMAP if 'integration_test/roadmap_emulator_test.dart' in command else CRITICAL
                supplied = roadmap_events if expected == ROADMAP else ordinary_events
                kwargs['stdout'].write('\n'.join(events(expected & selected) if supplied is None else supplied))
                return Mock(wait=Mock(return_value=0, side_effect=wait_error))

            def capture(device, path):
                if captures is not None:
                    captures.append((device, path.name))
                if capture_error is not None:
                    raise capture_error

            def export_frame(*args, **kwargs):
                if trace is not None:
                    trace.append('export')
                if frame_error is not None:
                    raise frame_error
                kwargs['stdout'].write(b'frame bytes')

            with patch.object(test_journeys.sys, 'argv', [
                    'test_journeys.py', '--output', temporary,
                    *[item for name in cases for item in ('--case', name)],
                    *(['--capture-frames'] if capture_frames else [])]), \
                 patch.object(test_journeys.os, 'chdir'), \
                 patch.object(test_journeys, 'fingerprint', return_value={'source': 'fixed'},
                              side_effect=fingerprints), \
                 patch.object(test_journeys.android, 'OUTPUT', output), \
                 patch.object(test_journeys.android, 'owned_emulator', side_effect=owned), \
                 patch.object(test_journeys.android, 'require_emulator'), \
                 patch.object(test_journeys.android, 'device', side_effect=lambda serial, *args: 'package:/fixture/base.apk' if args[:2] == ('shell', 'pm') and args[2] == 'path' else ''), \
                 patch.object(test_journeys.subprocess, 'Popen', side_effect=run_flutter), \
                 patch.object(test_journeys, 'stop_process_group',
                              side_effect=lambda process: retirements.append(process) if retirements is not None else None), \
                 patch.object(test_journeys.subprocess, 'run', side_effect=export_frame) as export, \
                 patch.object(test_journeys.android, 'adb_path', return_value='/owned/sdk/adb'), \
                 patch.object(test_journeys.android, 'capture_failure',
                              side_effect=capture), \
                 patch.object(test_journeys.process_recovery, 'run', return_value=recovery,
                              side_effect=recovery_error) as run, \
                 contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                code = test_journeys.main()
                if exports is not None:
                    exports.extend(export.call_args_list)
            if not preparation_exit:
                self.assertTrue(log.exists())
            return code, json.loads((output / 'receipt.json').read_text()), run.call_args_list

    def test_exact_focused_roadmap_prepares_package_and_retires_owned_emulator(self):
        name = 'activity approvals and queued work keep their chat owner'
        trace, environments, retired = [], [], []
        code, receipt, recovery = self.exercise(None, cases=[name], trace=trace,
            environments=environments, retirements=retired, capture_frames=True)
        self.assertEqual(code, 0)
        self.assertEqual(receipt['scope'], 'focused')
        self.assertEqual(receipt['selected_cases'], [name])
        self.assertEqual(set(receipt['suites']), {'roadmap'})
        self.assertEqual(receipt['suites']['roadmap']['completed'], [name])
        self.assertEqual(trace, ['emulator-start', 'build', 'install', 'test', 'emulator-retired'])
        self.assertEqual(len(retired), 3)
        self.assertTrue(all(env['ORG_GRADLE_PROJECT_notificationQa'] == 'true' for env in environments))
        self.assertEqual(recovery, [])
        self.assertNotIn('process_recovery', receipt)
        command = receipt['suites']['roadmap']['command']
        self.assertIn('--dart-define=CAPTURE_JOURNEYS=true', command)
        pattern = command[command.index('--name') + 1]
        self.assertIsNotNone(re.fullmatch(pattern, name))
        self.assertIsNone(re.fullmatch(pattern, name + ' extra'))

    def test_selected_critical_and_roadmap_share_existing_preparation(self):
        names = [sorted(CRITICAL)[0], sorted(ROADMAP)[0]]
        trace = []
        code, receipt, recovery = self.exercise(None, cases=names, trace=trace)
        self.assertEqual(code, 0)
        self.assertEqual(trace, ['emulator-start', 'test', 'test', 'emulator-retired'])
        self.assertNotIn('preparation', receipt)
        self.assertEqual(recovery, [])

    def test_focused_empty_skipped_failed_or_unrequested_outcomes_fail(self):
        name = sorted(ROADMAP)[0]
        for lines in ([], events({name}, skipped=name), events({name}, failed=name), events(ROADMAP)):
            with self.subTest(lines=lines):
                trace = []
                code, receipt, recovery = self.exercise(None, cases=[name], roadmap_events=lines, trace=trace)
                self.assertEqual(code, 1)
                self.assertFalse(receipt['passed'])
                self.assertEqual(recovery, [])
                self.assertEqual(trace[-1], 'emulator-retired')

    def test_preparation_failure_never_drives_and_retires_emulator(self):
        trace, retired = [], []
        code, receipt, recovery = self.exercise(None, cases=[sorted(ROADMAP)[0]],
            preparation_exit=1, trace=trace, retirements=retired)
        self.assertEqual(code, 1)
        self.assertEqual(trace, ['emulator-start', 'build', 'emulator-retired'])
        self.assertFalse(receipt['preparation']['build']['passed'])
        self.assertEqual(receipt['suites'], {})
        self.assertEqual(len(retired), 1)
        self.assertEqual(recovery, [])

    def test_focused_passing_results_cannot_hide_changed_source(self):
        code, receipt, _ = self.exercise(None, cases=[sorted(CRITICAL)[0]],
            fingerprints=[{'source': 'before'}, {'source': 'after'}])
        self.assertEqual(code, 1)
        self.assertTrue(receipt['source_changed'])

    def test_unknown_case_is_rejected_before_any_device_or_build(self):
        with patch.object(test_journeys.sys, 'argv', ['test_journeys.py', '--case', 'unknown']), \
             patch.object(test_journeys.android, 'owned_emulator') as owned, \
             patch.object(test_journeys.subprocess, 'Popen') as process, \
             contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as result:
                test_journeys.main()
        self.assertEqual(result.exception.code, 2)
        owned.assert_not_called()
        process.assert_not_called()

    def test_failure_frame_is_exported_without_opt_in_capture_flag(self):
        exports = []
        lines = events(failed=sorted(CRITICAL)[0]) + [json.dumps({
            'type': 'print', 'message': 'Journey frame: /data/user/0/qa/failure.png'})]
        code, receipt, _ = self.exercise(None, ordinary_events=lines, exports=exports)
        self.assertEqual(code, 1)
        self.assertEqual(len(exports), 1)
        self.assertIn('/data/user/0/qa/failure.png', exports[0].args[0])
        self.assertEqual(len(receipt['suites']['critical']['frames']), 1)
        self.assertTrue(receipt['suites']['critical']['failed'])

    def test_frames_are_exported_once_from_qa_before_emulator_retirement(self):
        name = sorted(CRITICAL)[0]
        marker = json.dumps({'type': 'print', 'message': 'Journey frame: /data/user/0/qa/screen.png'})
        exports, trace = [], []
        code, receipt, _ = self.exercise(None, cases=[name], capture_frames=True,
            ordinary_events=events({name}) + [marker, marker], exports=exports, trace=trace)
        self.assertEqual(code, 0)
        self.assertEqual(trace, ['emulator-start', 'test', 'export', 'emulator-retired'])
        self.assertEqual(exports[0].args[0], ['/owned/sdk/adb', '-s', 'emulator-5562',
            'exec-out', 'run-as', 'com.tarkilhk.wing.notificationqa', 'cat',
            '/data/user/0/qa/screen.png'])
        self.assertTrue(exports[0].kwargs['check'])
        self.assertEqual(exports[0].kwargs['timeout'], 25)
        self.assertEqual(len(receipt['suites']['critical']['frames']), 1)

    def test_frame_export_error_fails_an_otherwise_passing_journey(self):
        name = sorted(CRITICAL)[0]
        lines = events({name}) + [json.dumps({
            'type': 'print', 'message': 'Journey frame: /data/user/0/qa/screen.png'})]
        code, receipt, _ = self.exercise(None, cases=[name], ordinary_events=lines,
            frame_error=OSError('device unavailable'))
        self.assertEqual(code, 1)
        suite = receipt['suites']['critical']
        self.assertEqual(suite['completed'], [name])
        self.assertEqual(suite['frames'], [])
        self.assertEqual(suite['capture_errors'], ['device unavailable'])

    def test_frame_export_error_keeps_original_failure(self):
        lines = events(failed=sorted(CRITICAL)[0]) + [json.dumps({
            'type': 'print', 'message': 'Journey frame: /data/user/0/qa/failure.png'})]
        code, receipt, _ = self.exercise(None, ordinary_events=lines,
            frame_error=OSError('device unavailable'))
        self.assertEqual(code, 1)
        self.assertTrue(receipt['suites']['critical']['failed'])
        self.assertEqual(receipt['suites']['critical']['capture_errors'], ['device unavailable'])

    def test_failed_suite_captures_owned_device_without_running_next_suite(self):
        captures = []
        code, receipt, _ = self.exercise({'passed': True}, ordinary_events=[], captures=captures)
        self.assertEqual(code, 1)
        self.assertEqual(captures, [('emulator-5562', 'critical-failure')])
        # Flutter 3.44 crashes its native LiveTest runner with --fail-fast.
        self.assertNotIn('--fail-fast', receipt['suites']['critical']['command'])
        self.assertNotIn('roadmap', receipt['suites'])

    def test_timeout_keeps_failed_receipt_and_captures_before_retirement(self):
        captures = []
        code, receipt, calls = self.exercise(None, captures=captures,
            wait_error=test_journeys.subprocess.TimeoutExpired('flutter', 900))
        self.assertEqual(code, 1)
        self.assertFalse(receipt['passed'])
        self.assertIn('timed out', receipt['suites']['critical']['error'])
        self.assertEqual(captures, [('emulator-5562', 'critical-failure')])
        self.assertEqual(calls, [])

    def test_capture_exception_preserves_timeout_and_retires_flutter(self):
        for error in [OSError('disk full'), RuntimeError('capture failed')]:
            with self.subTest(error=error):
                retired = []
                code, receipt, calls = self.exercise(None, capture_error=error, retirements=retired,
                    wait_error=test_journeys.subprocess.TimeoutExpired('flutter', 900))
                self.assertEqual(code, 1)
                self.assertEqual(len(retired), 1)
                self.assertIn('timed out', receipt['error'])
                self.assertEqual(receipt['suites']['critical']['capture_errors'], [str(error)])
                self.assertEqual(calls, [])

    def test_success_requires_completed_process_recovery_on_same_emulator(self):
        code, receipt, calls = self.exercise({'passed': True})
        self.assertEqual(code, 0)
        self.assertTrue(receipt['passed'])
        self.assertEqual(receipt['scope'], 'full')
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0].args[0], 'emulator-5562')
        self.assertEqual(calls[0].args[1].name, 'process-recovery')

    def test_journeys_override_conflicting_inherited_android_variants(self):
        flavors = {'ORG_GRADLE_PROJECT_' + name: value for name, value in {
            'notificationQa': 'true', 'performanceQa': 'false',
            'nativeShareQa': 'false', 'wingDevelopment': 'false',
        }.items()}
        environments = []
        with patch.dict(test_journeys.os.environ,
                        {name: 'false' if value == 'true' else 'true'
                         for name, value in flavors.items()}):
            code, _, _ = self.exercise({'passed': True}, environments=environments)
        self.assertEqual(code, 0)
        self.assertEqual(len(environments), 2)
        for environment in environments:
            self.assertEqual({name: environment[name] for name in flavors}, flavors)

    def test_failed_process_recovery_blocks_otherwise_passing_journeys(self):
        code, receipt, _ = self.exercise({'passed': False, 'error': 'restoration failed'})
        self.assertEqual(code, 1)
        self.assertFalse(receipt['passed'])
        self.assertEqual(receipt['process_recovery']['error'], 'restoration failed')

    def test_missing_or_non_boolean_recovery_success_cannot_pass(self):
        for recovery in ({}, {'passed': 'true'}, {'passed': 1}):
            with self.subTest(recovery=recovery):
                code, receipt, _ = self.exercise(recovery)
                self.assertEqual(code, 1)
                self.assertFalse(receipt['passed'])

    def test_failed_initial_journey_never_runs_additional_device_work(self):
        code, receipt, calls = self.exercise({'passed': True}, ordinary_events=[])
        self.assertEqual(code, 1)
        self.assertFalse(receipt['passed'])
        self.assertEqual(calls, [])

    def test_each_missing_roadmap_journey_blocks_recovery_and_acceptance(self):
        for missing in ROADMAP:
            with self.subTest(missing=missing):
                code, receipt, calls = self.exercise(
                    {'passed': True}, roadmap_events=events(ROADMAP, omitted=missing))
                self.assertEqual(code, 1)
                self.assertFalse(receipt['passed'])
                self.assertEqual(receipt['suites']['roadmap']['missing'], [missing])
                self.assertEqual(calls, [])

    def test_recovery_exception_cannot_leave_a_successful_receipt(self):
        code, receipt, _ = self.exercise(None, recovery_error=RuntimeError('device stopped'))
        self.assertEqual(code, 1)
        self.assertFalse(receipt['passed'])
        self.assertEqual(receipt['error'], 'device stopped')
