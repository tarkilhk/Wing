import contextlib
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from scripts import test_nightly_native as nightly


def events(*, skipped=False, failed=False, omitted=False):
    rows = [{'type': 'testStart', 'test': {'id': 1, 'name': 'owning outcome'}}]
    if not omitted:
        rows.append({'type': 'testDone', 'testID': 1, 'hidden': False,
                     'skipped': skipped, 'result': 'failure' if failed else 'success'})
    rows.append({'type': 'done', 'success': True})
    return '\n'.join(json.dumps(row) for row in rows)


class NativeExecution(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name)
        self.runner = nightly.Runner(self.output)

    def command(self, text, code=0):
        return [sys.executable, '-c', f'print({text!r}); raise SystemExit({code})']

    def test_completed_exact_case_and_registered_wrapper_pass(self):
        for expected in (frozenset({'owning outcome'}), 'registered'):
            self.runner.run('complete', self.command(events()), expected=expected)
            self.assertTrue(self.runner.steps[-1]['passed'])

    def test_skipped_failed_missing_empty_and_nonzero_cannot_pass(self):
        cases = [(events(skipped=True), 0), (events(failed=True), 0),
                 (events(omitted=True), 0), ('{"type":"done","success":true}', 0),
                 (events(), 1)]
        for expected in (frozenset({'owning outcome'}), 'registered'):
            for text, code in cases:
                with self.subTest(expected=expected, text=text, code=code), \
                     contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(RuntimeError):
                        self.runner.run('incomplete', self.command(text, code), expected=expected)
                    self.assertFalse(self.runner.steps[-1]['passed'])

    def test_unknown_or_duplicate_case_cannot_replace_expected_outcome(self):
        for text in (events().replace('owning outcome', 'different outcome'),
                     events().replace('{"type": "done", "success": true}',
                                      '{"type":"testDone","testID":1,"result":"success"}\n'
                                      '{"type":"done","success":true}')):
            with self.subTest(text=text), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(RuntimeError):
                    self.runner.run('wrong', self.command(text), expected=frozenset({'owning outcome'}))

    def test_deadline_stops_owned_process(self):
        with patch.object(nightly, 'stop_process_group', wraps=nightly.stop_process_group) as stop:
            with self.assertRaises(TimeoutError):
                self.runner.run('timeout', [sys.executable, '-c', 'import time;time.sleep(60)'], timeout=.01)
            self.assertIsNotNone(stop.call_args.args[0].poll())
        self.assertFalse(self.runner.steps[-1]['passed'])

    def test_driver_cancellation_runs_its_cleanup(self):
        marker = self.output / 'retired'
        ready = self.output / 'ready'
        script = self.output / 'driver.py'
        script.write_text('from pathlib import Path\nimport time\ntry:\n'
                          f' Path({str(ready)!r}).touch()\n time.sleep(60)\n'
                          f'finally:\n Path({str(marker)!r}).touch()\n')
        with patch.object(self.runner, 'run') as run:
            self.runner.driver(str(script))
        command = run.call_args.args[1]
        child = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(ready.exists())
            child.send_signal(signal.SIGTERM)
            self.assertNotEqual(child.wait(timeout=5), 0)
            self.assertTrue(marker.exists())
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()

    def test_forward_is_removed_after_failure(self):
        with patch.object(self.runner, 'adb', return_value='43123') as adb:
            with self.assertRaisesRegex(RuntimeError, 'test failure'):
                with self.runner.forward('tcp:18766'):
                    raise RuntimeError('test failure')
        self.assertEqual(adb.call_args_list[-1].args, ('forward', '--remove', 'tcp:43123'))


class Catalog(unittest.TestCase):
    def test_reviewed_native_boundaries_are_all_enrolled(self):
        self.assertTrue({
            'journeys', 'health-normal', 'health-large', 'backup', 'background',
            'recents', 'recents-code', 'recents-events', 'recents-momentum',
            'notification-actions', 'notification-restore', 'notification-counts',
            'notification-cold', 'voice', 'file-transfer', 'stock-hermes',
        }.issubset(nightly.FAMILIES))

    def test_empty_and_duplicate_catalogs_fail_before_publishing_outputs(self):
        for families in ((), ('backup', 'backup')):
            with self.subTest(families=families), \
                 patch.object(nightly, 'FAMILIES', families), \
                 patch.object(sys, 'argv', ['nightly', '--matrix']):
                with self.assertRaises(ValueError):
                    nightly.main()

    def test_matrix_contains_each_enrolled_family_once(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'output'
            result = subprocess.run([sys.executable, 'scripts/test_nightly_native.py', '--matrix'],
                                    cwd=nightly.ROOT, capture_output=True, text=True,
                                    env={**os.environ, 'GITHUB_OUTPUT': str(destination)}, check=True)
            families = json.loads(result.stdout)
            self.assertEqual(families, list(nightly.FAMILIES))
            self.assertEqual(len(families), len(set(families)))
            self.assertEqual(json.loads(destination.read_text().split('=', 1)[1]), families)

    def test_unknown_family_is_rejected_before_any_command(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = nightly.Runner(Path(directory))
            with patch.object(runner, 'run') as run:
                with self.assertRaises(ValueError):
                    runner.family('not-enrolled')
                run.assert_not_called()

    def test_every_enrolled_family_dispatches_a_real_suite(self):
        @contextlib.contextmanager
        def forward(_):
            yield '43123'
        with tempfile.TemporaryDirectory() as directory:
            runner = nightly.Runner(Path(directory))
            runner.device = 'emulator-5562'
            for family in nightly.FAMILIES:
                with self.subTest(family=family), \
                     patch.object(nightly.android, 'adb_path', return_value='/owned/sdk/adb'), \
                     patch.object(runner, 'run') as run, \
                     patch.object(runner, 'shell', side_effect=lambda *args:
                                  '123' if args[0] == 'pidof' else 'webview_devtools_remote_123'), \
                     patch.object(runner, 'forward', side_effect=forward), \
                     patch.object(runner, 'wait_fixture'):
                    runner.family(family, Path('/owned/hermes'))
                    self.assertTrue(run.called, family)
                    for call in run.call_args_list:
                        if '--reporter=json' in call.args[1]:
                            self.assertTrue(call.kwargs['expected'])

    def test_recents_modes_cannot_collapse_to_standard_only(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = nightly.Runner(Path(directory))
            runner.device = 'emulator-5562'
            for mode in ('code', 'events', 'momentum'):
                with patch.object(runner, 'install'), patch.object(runner, 'driver') as driver:
                    runner.family('recents-' + mode)
                self.assertIn('--' + mode + '-only', driver.call_args.args)

    def test_main_failure_retires_emulator_and_records_failed_receipt(self):
        for changing_source in (False, True):
            retired = []
            @contextlib.contextmanager
            def emulator():
                try:
                    yield 'emulator-5562'
                finally:
                    retired.append(True)
            with tempfile.TemporaryDirectory() as directory, \
                 patch.object(sys, 'argv', ['nightly', 'backup', '--output', directory]), \
                 patch.object(nightly.android, 'owned_emulator', side_effect=emulator), \
                 patch.object(nightly.android, 'require_emulator'), \
                 patch.object(nightly, 'fingerprint', side_effect=['before', 'after' if changing_source else 'before']), \
                 patch.object(nightly.Runner, 'family', side_effect=RuntimeError('driver failed')), \
                 contextlib.redirect_stdout(io.StringIO()):
                original_output = nightly.android.OUTPUT
                self.assertEqual(nightly.main(), 1)
                result = json.loads((Path(directory) / 'backup/receipt.json').read_text())
                self.assertFalse(result['passed'])
                self.assertEqual(result['error'], 'driver failed')
                self.assertEqual(retired, [True])
                self.assertEqual(nightly.android.OUTPUT, original_output)

    def test_source_change_invalidates_successful_steps(self):
        def successful(runner, *args):
            runner.steps.append({'name': 'owned driver', 'passed': True})
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(sys, 'argv', ['nightly', 'backup', '--output', directory]), \
             patch.object(nightly.android, 'owned_emulator', return_value=contextlib.nullcontext('emulator-5562')), \
             patch.object(nightly.android, 'require_emulator'), \
             patch.object(nightly, 'fingerprint', side_effect=['before', 'after']), \
             patch.object(nightly.Runner, 'family', successful), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(nightly.main(), 1)
            result = json.loads((Path(directory) / 'backup/receipt.json').read_text())
            self.assertTrue(result['source_changed'])
            self.assertFalse(result['passed'])


if __name__ == '__main__':
    unittest.main()
