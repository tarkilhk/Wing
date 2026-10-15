"""Native drivers reject disabled assertions and incomplete journey matrices."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
from scripts.test_native_bots import input_view_visible, require_completed_cases
from scripts.test_native_recents import require_completed_cases as require_recents
from tools.qa.check_background_monitoring import require_single_monitoring_card
from tools.qa import check_notification_revamp as notification_ui

ROOT = Path(__file__).resolve().parents[2]
DRIVERS = (
    'scripts/test_native_notification_counts.py',
    'scripts/test_native_cold_notification.py',
    'scripts/test_native_config_backup.py',
    'scripts/test_native_notification_restore.py',
    'tools/qa/check_activity_reentry.py',
    'tools/qa/check_background_monitoring.py',
    'tools/qa/check_external_share.py',
    'tools/qa/check_notification_revamp.py',

)


class NativeMonitoringForwardOwnership(unittest.TestCase):
    def test_failed_attempt_removes_its_allocated_forward_once(self):
        from tools.qa import check_background_monitoring as monitoring
        calls = []

        def adb(command, **kwargs):
            parts = command[3:]
            calls.append(parts)
            if parts == ['forward', '--no-rebind', 'tcp:0', 'tcp:18765']:
                return '43123\n'
            if parts == ['shell', 'cmd', 'statusbar', 'collapse']:
                raise RuntimeError('primary fixture failure')
            return ''

        with tempfile.TemporaryDirectory() as directory, \
             patch.object(sys, 'argv', ['monitoring', '--serial', 'emulator-5562', '--output', directory]), \
             patch.object(monitoring.subprocess, 'check_output', side_effect=adb), \
             patch.object(monitoring.urllib.request, 'urlopen', side_effect=RuntimeError('fixture not started')):
            with self.assertRaisesRegex(RuntimeError, 'primary fixture failure'):
                monitoring.main()
        self.assertEqual([c for c in calls if c[0] == 'forward'], [
            ['forward', '--no-rebind', 'tcp:0', 'tcp:18765'],
            ['forward', '--remove', 'tcp:43123'],
        ])

    def test_occupied_explicit_port_is_neither_rebound_nor_removed(self):
        from tools.qa import check_background_monitoring as monitoring
        calls = []

        def adb(command, **kwargs):
            parts = command[3:]
            calls.append(parts)
            if parts[0] == 'forward':
                raise subprocess.CalledProcessError(1, command, 'port already bound')
            return ''

        with tempfile.TemporaryDirectory() as directory, \
             patch.object(sys, 'argv', ['monitoring', '--serial', 'emulator-5562', '--port', '43210', '--output', directory]), \
             patch.object(monitoring.subprocess, 'check_output', side_effect=adb):
            with self.assertRaises(subprocess.CalledProcessError):
                monitoring.main()
        self.assertEqual([c for c in calls if c[0] == 'forward'], [
            ['forward', '--no-rebind', 'tcp:43210', 'tcp:18765'],
        ])


class MonitoringCardCardinality(unittest.TestCase):
    package = 'com.tarkilhk.wing.dev'

    def record(self, identifier=214601, package=None, channel='hermes_monitoring', foreground=True):
        flags = 'FOREGROUND_SERVICE|ONGOING_EVENT' if foreground else 'ONGOING_EVENT'
        return (f'  NotificationRecord(0x1: pkg={package or self.package} '
                f'user=UserHandle{{0}} id={identifier} tag=null '
                f'Notification(channel={channel} flags={flags}))\n')

    def test_one_foreground_card_ignores_other_packages_and_channels(self):
        dump = (self.record() + self.record(214603, package=self.package + '.other')
                + self.record(240001, channel='wing_attention_notifications')
                + self.record(240002, channel='hermes_monitoring_other'))
        require_single_monitoring_card(dump, self.package)

    def test_unknown_duplicate_monitoring_id_cannot_hide_behind_the_known_summary_check(self):
        with self.assertRaisesRegex(AssertionError, 'Expected one monitoring card, got 2'):
            require_single_monitoring_card(self.record() + self.record(214603), self.package)

    def test_missing_monitoring_card_is_not_success(self):
        with self.assertRaisesRegex(AssertionError, 'Expected one monitoring card, got 0'):
            require_single_monitoring_card('', self.package)

    def test_an_ordinary_notification_cannot_stand_in_for_the_foreground_card(self):
        with self.assertRaises(AssertionError):
            require_single_monitoring_card(self.record(foreground=False), self.package)

    def test_the_only_card_must_have_the_monitoring_identity(self):
        with self.assertRaises(AssertionError):
            require_single_monitoring_card(self.record(214603), self.package)


class NativeNotificationPresentation(unittest.TestCase):
    def card(self, text='3 questions', *, title='Outside task', app='Wing Dev', expanded=True):
        row = ET.Element('node', {'resource-id': 'com.android.systemui:id/expandableNotificationRow'})
        ET.SubElement(row, 'node', {'resource-id': 'android:id/app_name_text', 'text': app})
        ET.SubElement(row, 'node', {'resource-id': 'android:id/conversation_text', 'text': title})
        ET.SubElement(row, 'node', {'resource-id': 'android:id/message_text', 'text': text})
        ET.SubElement(row, 'node', {
            'resource-id': 'android:id/expand_button', 'enabled': 'true',
            'content-desc': 'Collapse' if expanded else 'Expand', 'bounds': '[10,20][50,60]',
        })
        return row

    def test_content_on_another_conversation_cannot_satisfy_the_target(self):
        other = self.card(title='Another task')
        self.assertIsNone(notification_ui.notification_card(list(other.iter()), 'Outside task'))

    def test_matching_content_in_another_apps_card_is_not_the_qa_notification(self):
        other = self.card(app='Another app')
        self.assertIsNone(notification_ui.notification_card(list(other.iter()), 'Outside task'))

    def test_duplicate_target_cards_are_rejected(self):
        rows = [self.card(), self.card()]
        with self.assertRaisesRegex(AssertionError, 'More than one native notification'):
            notification_ui.notification_card(rows, 'Outside task')

    def test_question_count_cannot_match_the_suffix_of_a_different_number(self):
        self.assertFalse(notification_ui.notification_text_matches(self.card('13 questions'), ['3 questions']))
        self.assertTrue(notification_ui.notification_text_matches(self.card('3 questions\nEnvironment?'), ['3 questions']))

    def test_private_preview_cannot_leak_in_an_accessibility_label(self):
        card = self.card('1 question')
        ET.SubElement(card, 'node', {'content-desc': 'Summary'})
        self.assertFalse(notification_ui.notification_text_matches(card, ['1 question'], ['Summary']))

    def test_expanded_check_waits_for_both_actual_mode_and_current_content(self):
        collapsed = self.card(expanded=False)
        stale = self.card('2 questions')
        current = self.card()
        with patch.object(notification_ui, 'shade'), \
             patch.object(notification_ui, 'nodes', side_effect=[[collapsed], [collapsed], [stale], [current]]), \
             patch.object(notification_ui.time, 'sleep'), patch.object(notification_ui, 'adb') as adb:
            result = notification_ui.shown_notification('Outside task', expanded=True, required=['3 questions'])
        self.assertIs(result, current)
        adb.assert_called_once_with('shell', 'input', 'tap', '30', '40')

    def test_collapsed_check_uses_the_real_collapse_control(self):
        expanded = self.card()
        collapsed = self.card(expanded=False)
        with patch.object(notification_ui, 'shade'), \
             patch.object(notification_ui, 'nodes', side_effect=[[expanded], [collapsed]]), \
             patch.object(notification_ui, 'adb') as adb:
            result = notification_ui.shown_notification('Outside task', expanded=False, required=['3 questions'])
        self.assertIs(result, collapsed)
        adb.assert_called_once_with('shell', 'input', 'tap', '30', '40')


class NativeDriverGuards(unittest.TestCase):
    def test_optimized_invocation_refuses_before_device_access(self):
        for driver in DRIVERS:
            for mode in ('flag', 'environment'):
                with self.subTest(driver=driver, mode=mode):
                    environment = dict(os.environ)
                    environment.pop('PYTHONOPTIMIZE', None)
                    flags = ['-O'] if mode == 'flag' else []
                    if mode == 'environment':
                        environment['PYTHONOPTIMIZE'] = '1'
                    result = subprocess.run(
                        [sys.executable, *flags, str(ROOT / driver), '--help'],
                        capture_output=True, text=True, timeout=10, env=environment,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('Native acceptance requires Python assertions', result.stderr)


class NativeBotsKeyboard(unittest.TestCase):
    def test_stale_show_request_does_not_make_hidden_input_view_visible(self):
        self.assertFalse(input_view_visible(
            'mInputShown=true\n  mWindowVisible=false mIsInputViewShown=false mStatusIcon=0'))

    def test_retained_input_view_does_not_make_hidden_ime_window_visible(self):
        self.assertFalse(input_view_visible(
            'mInputShown=false\n  mWindowVisible=false mIsInputViewShown=true mStatusIcon=0'))

    def test_actual_input_view_is_visible(self):
        self.assertTrue(input_view_visible(
            'mInputShown=true\n  mWindowVisible=true mIsInputViewShown=true mStatusIcon=0'))

    def test_missing_actual_view_state_is_not_assumed_hidden(self):
        with self.assertRaises(RuntimeError):
            input_view_visible('mInputShown=false')


class NativeBotsCompletion(unittest.TestCase):
    def records(self):
        return [{'name': f'{theme}-{size}-complete'}
                for theme in ('dark', 'light') for size in ('normal', 'large')]

    def test_full_matrix_requires_all_four_completed_journeys(self):
        self.assertEqual(len(require_completed_cases(self.records())), 4)

    def test_empty_success_is_rejected(self):
        with self.assertRaises(RuntimeError):
            require_completed_cases([])

    def test_each_missing_configuration_is_rejected(self):
        records = self.records()
        for missing in records:
            with self.subTest(missing=missing):
                with self.assertRaises(RuntimeError):
                    require_completed_cases([r for r in records if r != missing])

    def test_duplicate_completion_cannot_replace_a_missing_configuration(self):
        with self.assertRaises(RuntimeError):
            require_completed_cases([self.records()[0]] * 4)

    def test_named_recovery_only_requires_its_selected_journey(self):
        self.assertEqual(require_completed_cases([{'name': 'light-large-complete'}],
                                                'Android Bots light-large'),
                         ['light-large-complete'])

    def test_unknown_filter_cannot_accept_an_empty_run(self):
        with self.assertRaises(RuntimeError):
            require_completed_cases([], 'nonexistent journey')


class NativeRecentsCompletion(unittest.TestCase):
    def records(self, mode='standard'):
        prefix = 'events-' if mode == 'events' else ''
        suffix = '-code' if mode == 'code' else ''
        return [{'name': f'{prefix}{theme}-{size}{suffix}-complete'}
                for theme in ('dark', 'light') for size in ('normal', 'large')]

    def test_each_mode_requires_its_own_complete_matrix(self):
        for mode in ('standard', 'code', 'events'):
            with self.subTest(mode=mode):
                self.assertEqual(len(require_recents(self.records(mode), mode=mode)), 4)
                with self.assertRaises(RuntimeError):
                    require_recents(self.records(mode)[:-1], mode=mode)

    def test_momentum_requires_its_explicit_completion(self):
        self.assertEqual(require_recents([{'name': 'dark-normal-momentum-complete'}], mode='momentum'),
                         ['dark-normal-momentum-complete'])
        with self.assertRaises(RuntimeError):
            require_recents([{'name': 'dark-normal-momentum-select'}], mode='momentum')

    def test_wrong_mode_completion_does_not_count(self):
        with self.assertRaises(RuntimeError):
            require_recents(self.records('code'))

    def test_duplicate_completion_does_not_count(self):
        with self.assertRaises(RuntimeError):
            require_recents(self.records() + [self.records()[0]])

    def test_selected_recovery_case_can_complete_alone(self):
        self.assertEqual(require_recents([{'name': 'events-light-large-complete'}],
                                        name='native incoming messages light large', mode='events'),
                         ['events-light-large-complete'])

    def test_unknown_name_cannot_accept_an_empty_run(self):
        with self.assertRaises(RuntimeError):
            require_recents([], name='not a journey')


class NativeBackupChooser(unittest.TestCase):
    def node(self, resource, bounds, *, text='', package='com.android.intentresolver'):
        from scripts import test_native_config_backup as backup
        return backup.ET.Element('node', {'resource-id': resource, 'bounds': bounds,
                                         'text': text, 'package': package, 'enabled': 'true'})

    def driver(self, directory):
        from scripts import test_native_config_backup as backup

        class Device:
            def __init__(self):
                self.calls = []

            def shell(self, *args):
                self.calls.append(args)
                return ''

        return backup.Driver(Device(), Path(directory), 'wing-backup-qa-test-')

    def test_hidden_share_destination_is_revealed_before_the_actual_target_is_tapped(self):
        from unittest.mock import patch
        from scripts import test_native_config_backup as backup
        driver = self.driver('unused')
        hidden = [self.node('android:id/contentPanel', '[0,0][1080,1920]'),
                  self.node('android:id/drag', '[456,921][624,932]')]
        target = [self.node('android:id/text1', '[20,1200][500,1250]', text='Save Wing QA backup')]
        snapshots = iter([hidden, target])
        driver.nodes = lambda _: next(snapshots)
        driver.status = lambda: {}
        driver.capture = lambda _: None
        driver.process = type('Process', (), {'poll': lambda _: None})()

        class TargetTapped(Exception):
            pass

        def tap(node):
            self.assertIs(node, target[0])
            raise TargetTapped()

        driver.tap = tap
        with patch.object(backup.time, 'sleep'), self.assertRaises(TargetTapped):
            driver.drive('share-plain')
        command = driver.device.calls[0]
        self.assertEqual(command[:2], ('input', 'swipe'))
        self.assertGreater(int(command[3]), int(command[5]))

    def test_expanded_chooser_scrolls_its_target_list_upward(self):
        driver = self.driver('unused')
        shown = [self.node('android:id/contentPanel', '[0,0][1080,1920]'),
                 self.node('android:id/drag', '[456,50][624,60]'),
                 self.node('android:id/resolver_list', '[0,600][1080,1800]')]
        self.assertTrue(driver.reveal_share_targets(shown))
        command = driver.device.calls[0]
        self.assertEqual(command[:2], ('input', 'swipe'))
        start, end = int(command[3]), int(command[5])
        self.assertTrue(600 < end < start < 1800)

    def test_another_apps_similar_controls_do_not_receive_a_chooser_gesture(self):
        driver = self.driver('unused')
        shown = [self.node('android:id/contentPanel', '[0,0][1080,1920]', package='other.app'),
                 self.node('android:id/drag', '[456,921][624,932]', package='other.app')]
        self.assertFalse(driver.reveal_share_targets(shown))
        self.assertEqual(driver.device.calls, [])

    def test_failed_ui_capture_never_reads_the_previous_hierarchy(self):
        driver = self.driver('unused')
        with self.assertRaisesRegex(RuntimeError, 'discard the previous hierarchy'):
            driver.nodes('failed')
        self.assertEqual(driver.device.calls, [('uiautomator', 'dump', driver.dump_path)])


if __name__ == '__main__':
    unittest.main()
