"""Keep the notification regression harness fail-closed at its OS boundary."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import check_notification_revamp as driver
import run_notification_gate as gate


class NotificationCaptureTest(unittest.TestCase):
    def test_failed_dump_cannot_reuse_a_previous_successful_capture(self):
        with patch.object(driver, 'adb', side_effect=[
            'ERROR: null root node', '<hierarchy><node text="stale reply"/></hierarchy>',
        ]) as adb:
            with self.assertRaises(ValueError):
                driver.nodes()
        self.assertEqual(adb.call_count, 1, 'Failed dump must not read stale XML')

    def test_successful_dump_reads_current_hierarchy(self):
        with patch.object(driver, 'adb', side_effect=[
            'UI hierchary dumped to: /sdcard/wing-notification-ui.xml',
            '<hierarchy><node text="current reply"/></hierarchy>',
        ]):
            self.assertEqual(driver.nodes()[0].get('text'), 'current reply')


class NotificationDismissalTest(unittest.TestCase):
    def exercise(self, notification_dump, selected_is_target=True):
        held = False
        released = False

        def state(path='/', data=None):
            nonlocal held, released
            if path == '/reply':
                return {'notices': json.dumps({json.dumps({'profile': 'a'}): {
                    'result': True, 'rendered': json.dumps({'id': 42001}),
                }})}
            if path == '/hold-history':
                held = True
            if path == '/release-history':
                released = True
            return {'lifecycle': 'resumed' if held else 'paused',
                    'chat_visible': held, 'history_held': held,
                    'read_guards': {'selected_is_target': selected_is_target}}

        def adb(*args):
            if args[:2] == ('shell', 'dumpsys'):
                self.assertTrue(held)
                self.assertFalse(released, 'Check Android before releasing history')
                return notification_dump
            return ''

        try:
            with patch.object(driver, 'state', side_effect=state), \
                 patch.object(driver, 'adb', side_effect=adb), \
                 patch.object(driver, 'shade'), patch.object(driver, 'tap'), \
                 patch.object(driver, 'nodes', return_value=[ET.Element(
                     'node', text='Read this notification while history is held.')]):
                driver.check_content_tap_clear()
        finally:
            self.assertTrue(released, 'Release held history even after assertion failure')

    def test_same_native_slot_remaining_is_a_failure(self):
        with self.assertRaisesRegex(AssertionError, 'left its notification'):
            self.exercise(f'NotificationRecord(pkg={driver.PACKAGE} id=42001 tag=null)')

    def test_other_apps_and_other_chat_slots_are_allowed(self):
        self.exercise('NotificationRecord(pkg=other.app id=42001 tag=null)\n'
                      f'NotificationRecord(pkg={driver.PACKAGE} id=42002 tag=null)')

    def test_opening_an_unrelated_chat_is_not_success(self):
        with self.assertRaisesRegex(AssertionError, 'different chat'):
            self.exercise('', selected_is_target=False)


class NotificationGateTest(unittest.TestCase):
    def setUp(self):
        output = tempfile.TemporaryDirectory(prefix='wing-notification-unit-')
        self.addCleanup(output.cleanup)
        location = patch.object(gate, 'OUTPUT', Path(output.name))
        location.start()
        self.addCleanup(location.stop)

    @unittest.skipUnless(os.name == 'posix', 'Exercises the Linux CI SDK executables')
    def test_real_ci_entry_point_propagates_device_driver_failure(self):
        with tempfile.TemporaryDirectory(prefix='wing-notification-cli-') as directory:
            root = Path(directory)

            def executable(relative, source):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f'#!{sys.executable}\n' + source)
                path.chmod(0o700)

            executable('bin/flutter', 'print("QA fixture build reached")\n')
            executable('bin/adb', '''import sys
if sys.argv[1:] == ['devices']:
    print('List of devices attached')
elif sys.argv[3:] in (['shell', 'getprop', 'ro.kernel.qemu'],
                       ['shell', 'getprop', 'sys.boot_completed']):
    print('1')
elif sys.argv[3] == 'forward':
    sys.exit(23)
''')
            executable('sdk/cmdline-tools/latest/bin/avdmanager', 'pass\n')
            executable('sdk/emulator/emulator', 'import time\ntime.sleep(30)\n')
            (root / 'tools/qa').mkdir(parents=True)
            shutil.copyfile(driver.__file__, root / 'tools/qa/check_notification_revamp.py')
            result = subprocess.run(
                [sys.executable, str(Path(gate.__file__).resolve())], cwd=root,
                env={**os.environ, 'ANDROID_HOME': str(root / 'sdk'),
                     'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH']},
                capture_output=True, text=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('QA fixture build reached', result.stdout)
            self.assertIn('forward', result.stderr)
            self.assertIn('exit status 23', result.stderr)

    def test_never_installs_or_resets_a_phone(self):
        with patch.object(gate, 'device') as device, patch.object(gate, 'command') as command:
            with self.assertRaises(ValueError):
                gate.check_on_emulator('physical-phone')
        device.assert_not_called()
        command.assert_not_called()

    def test_emulator_name_alone_is_insufficient(self):
        with patch.object(gate, 'device', return_value='0'), patch.object(gate, 'command') as command:
            with self.assertRaises(ValueError):
                gate.check_on_emulator('emulator-5562')
        command.assert_not_called()

    def test_shade_driver_failure_fails_the_gate(self):
        calls = []

        def command(*args, **kwargs):
            calls.append(args)
            if 'tools/qa/check_notification_revamp.py' in args:
                self.assertIn('--tap-only', args)
                raise subprocess.CalledProcessError(1, args)

        with patch.object(gate, 'device', return_value='1'), \
             patch.object(gate, 'command', side_effect=command):
            with self.assertRaises(subprocess.CalledProcessError):
                gate.check_on_emulator('emulator-5562')
        self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
