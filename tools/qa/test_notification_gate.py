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


class NotificationFixtureSetupTest(unittest.TestCase):
    def test_provisions_only_qa_permissions_before_first_launch(self):
        calls = []
        with patch.object(driver, 'SERIAL', 'emulator-5562'), \
             patch.object(driver, 'adb', side_effect=lambda *args: calls.append(args)), \
             patch.object(driver, 'until'), patch.object(driver, 'state'), \
             patch.object(driver, 'check_content_tap_clear', side_effect=RuntimeError('journey reached')):
            with self.assertRaisesRegex(RuntimeError, 'journey reached'):
                driver.run(Path('unused'), tap_only=True)
        clear = calls.index(('shell', 'pm', 'clear', driver.PACKAGE))
        grant = calls.index(('shell', 'pm', 'grant', driver.PACKAGE,
                             'android.permission.POST_NOTIFICATIONS'))
        exempt = calls.index(('shell', 'dumpsys', 'deviceidle', 'whitelist', '+' + driver.PACKAGE))
        launch = calls.index(('shell', 'am', 'start', '-n',
                              driver.PACKAGE + '/com.tarkilhk.wing.MainActivity'))
        self.assertLess(clear, grant)
        self.assertLess(grant, launch)
        self.assertLess(exempt, launch)


class NotificationDismissalTest(unittest.TestCase):
    def exercise(self, notification_dump, selected_is_target=True, delayed_publication=False):
        replied = False
        publication_reads = 0
        held = False
        released = False

        def state(path='/', data=None):
            nonlocal held, released, replied, publication_reads
            if path == '/reply':
                replied = True
            elif path == '/' and replied and not held:
                publication_reads += 1
            if path == '/hold-history':
                held = True
            if path == '/release-history':
                released = True
            return {'notices': json.dumps({json.dumps({'profile': 'a'}): {
                        'result': not delayed_publication or publication_reads >= 2,
                        'rendered': json.dumps({'id': 42001}),
                    }}), 'lifecycle': 'resumed' if held else 'paused',
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
        return publication_reads

    def test_waits_for_actual_publication_before_opening_the_shade(self):
        self.assertGreaterEqual(self.exercise('', delayed_publication=True), 2)

    def test_same_native_slot_remaining_is_a_failure(self):
        with self.assertRaisesRegex(AssertionError, 'left its notification'):
            self.exercise(f'NotificationRecord(pkg={driver.PACKAGE} id=42001 tag=null)')

    def test_other_apps_and_other_chat_slots_are_allowed(self):
        self.exercise('NotificationRecord(pkg=other.app id=42001 tag=null)\n'
                      f'NotificationRecord(pkg={driver.PACKAGE} id=42002 tag=null)')

    def test_opening_an_unrelated_chat_is_not_success(self):
        with self.assertRaisesRegex(AssertionError, 'different chat'):
            self.exercise('', selected_is_target=False)


class GroupBodyDestinationTest(unittest.TestCase):
    def exercise(self, visible_answer):
        def until(check, message, **kwargs):
            if not check():
                raise AssertionError(message)
        def adb(*args):
            return '' if 'pidof' not in args or len(args) == 2 else '123'
        with tempfile.TemporaryDirectory() as output, \
             patch.object(driver, 'adb', side_effect=adb), \
             patch.object(driver, 'state', return_value={
                 'lifecycle': 'paused', 'group_notification_id': 42, 'decisions': [],
             }), patch.object(driver, 'until', side_effect=until), \
             patch.object(driver, 'shade') as shade, patch.object(driver, 'tap'), \
             patch.object(driver, 'screenshot'), \
             patch.object(driver, 'nodes', return_value=[ET.Element('node', text=visible_answer)]):
            driver.check_group_body_taps(Path(output))
            self.assertEqual(shade.call_count, 3)
            for call in shade.call_args_list:
                self.assertEqual(call.kwargs, {'expand': False})

    def test_a_running_app_or_an_unrelated_chat_is_not_group_tap_success(self):
        with self.assertRaisesRegex(AssertionError, 'NATIVE_GROUP_BODY_TAP'):
            self.exercise('Some other chat')

    def test_default_shade_warm_approval_and_cold_taps_require_the_shared_answer(self):
        self.exercise('The shared discussion reached its exact destination.')


class NotificationGateTest(unittest.TestCase):
    def setUp(self):
        output = tempfile.TemporaryDirectory(prefix='wing-notification-unit-')
        self.addCleanup(output.cleanup)
        location = patch.object(gate, 'OUTPUT', Path(output.name))
        location.start()
        self.addCleanup(location.stop)
        sdk = patch.dict(os.environ, {'ANDROID_HOME': output.name})
        sdk.start()
        self.addCleanup(sdk.stop)

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
            executable('sdk/platform-tools/adb', '''import sys
if sys.argv[1:] == ['devices']:
    print('List of devices attached')
elif sys.argv[3:] in (['shell', 'getprop', 'ro.kernel.qemu'],
                       ['shell', 'getprop', 'sys.boot_completed']):
    print('1')
elif sys.argv[3:] == ['shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME']:
    print('com.android.launcher/.Home')
elif sys.argv[3:6] == ['shell', 'uiautomator', 'dump']:
    print('UI hierarchy dumped to: /sdcard/wing-boot-ui.xml')
elif sys.argv[3:5] == ['shell', 'cat']:
    print('<hierarchy><node package="com.android.launcher"/></hierarchy>')
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
                     'PATH': str(root / 'bin')},
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


class OwnedAndroidBootTest(unittest.TestCase):
    def exercise(self, title=None, installed=False, repeat=False, failed_dump=False):
        launcher = '<hierarchy><node package="com.android.launcher"/></hierarchy>'
        alert = ('<hierarchy><node resource-id="android:id/alertTitle" text="' +
                 (title or '') + '"/><node resource-id="android:id/aerr_wait" '
                 'bounds="[0,0][100,100]"/></hierarchy>')
        reads = iter([alert, alert if repeat else launcher] if title else [launcher])
        calls = []
        dumped = False

        def device(serial, *args):
            nonlocal dumped
            calls.append(args)
            if args[:4] == ('shell', 'pm', 'list', 'packages'):
                return 'package:com.tarkilhk.wing.notificationqa' if installed else ''
            if args[:4] == ('shell', 'cmd', 'package', 'resolve-activity'):
                return 'com.android.launcher/.Home'
            if args[:3] == ('shell', 'uiautomator', 'dump'):
                if failed_dump and not dumped:
                    dumped = True
                    return 'ERROR: null root node'
                return 'UI hierarchy dumped to: /sdcard/wing-boot-ui.xml'
            if args[:2] == ('shell', 'cat'):
                return next(reads)
            return ''

        with tempfile.TemporaryDirectory() as directory, \
             patch.object(gate, 'OUTPUT', Path(directory)), \
             patch.object(gate, 'device', side_effect=device), \
             patch.object(gate.time, 'sleep'):
            gate.prepare_owned_android('emulator-5562')
        return calls

    def test_requires_a_healthy_launcher_and_rejects_stale_dump(self):
        calls = self.exercise(failed_dump=True)
        self.assertEqual(sum(args[:3] == ('shell', 'uiautomator', 'dump') for args in calls), 2)
        self.assertEqual(sum(args[:2] == ('shell', 'cat') for args in calls), 1)

    def test_system_ui_boot_wait_is_allowed_once_before_fixture_installation(self):
        calls = self.exercise(title="System UI isn't responding")
        self.assertEqual(sum(args[:3] == ('shell', 'input', 'tap') for args in calls), 1)

    def test_never_recovers_a_fixture_anr_or_a_repeated_system_ui_anr(self):
        for title, repeat in [("Wing isn't responding", False),
                              ("System UI isn't responding", True)]:
            with self.subTest(title=title, repeat=repeat), self.assertRaises(RuntimeError):
                self.exercise(title=title, repeat=repeat)

    def test_never_runs_boot_recovery_when_fixture_is_installed(self):
        with self.assertRaises(ValueError):
            self.exercise(installed=True)


class GroupApprovalControlsTest(unittest.TestCase):
    def controls(self, *names):
        return [ET.Element('node', {'resource-id': 'android:id/action0',
                                  'text': name.title()})
                for name in names]

    def test_expands_the_exact_group_card_when_another_chat_is_first(self):
        root = ET.fromstring('''<hierarchy><node><node>
            <node text="Other chat"/>
            <node resource-id="android:id/expand_button" content-desc="Expand" bounds="[0,0][100,100]"/>
            </node><node><node text="Native group approval"/>
            <node resource-id="android:id/expand_button" content-desc="Expand" bounds="[200,200][300,300]"/>
            </node></node></hierarchy>''')
        shown = list(root.iter('node'))
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(driver, 'state'), patch.object(driver, 'shade'), \
             patch.object(driver, 'screenshot'), \
             patch.object(driver.time, 'sleep'), patch.object(driver, 'adb') as adb, \
             patch.object(driver, 'nodes', side_effect=[shown, self.controls('once', 'deny'),
                                                       shown, self.controls('review', 'deny')]):
            driver.check_group_approval_rendering(Path(directory))
        taps = [call.args for call in adb.call_args_list
                if call.args[:3] == ('shell', 'input', 'tap')]
        self.assertEqual(taps, [('shell', 'input', 'tap', '250', '250')] * 2)

    def test_supported_short_and_review_layouts_are_accepted(self):
        driver.assert_group_approval_controls(self.controls('once', 'deny'), False)
        driver.assert_group_approval_controls(self.controls('review', 'deny'), True)

    def test_unsupported_session_and_always_are_rejected(self):
        with self.assertRaisesRegex(AssertionError, 'NATIVE_GROUP_APPROVAL_RENDER'):
            driver.assert_group_approval_controls(self.controls('once', 'deny', 'session', 'always'), False)

    def test_missing_decision_or_wrong_layout_is_rejected(self):
        for names, review in [(('once',), False), (('once', 'deny'), True)]:
            with self.subTest(names=names, review=review), self.assertRaisesRegex(AssertionError, 'NATIVE_GROUP_APPROVAL_RENDER'):
                driver.assert_group_approval_controls(self.controls(*names), review)


if __name__ == '__main__':
    unittest.main()
